require("dotenv").config();

const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const OpenAI = require("openai");

const {
  initializeApp,
  getApps,
  applicationDefault,
} = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

// Helper khusus fitur sumber proyek (ekstraksi teks + konteks AI).
const {
  EXTRACT_MAX_BYTES,
  EXTRACT_MAX_CHARS,
  decodeBase64Payload,
  extractTextFromFile,
  buildSourceContext,
} = require("./source_extract");

// Secret di Cloud Functions dibaca dari Secret Manager.
// Saat development lokal, nilainya dibaca dari functions/.env.
const dashscopeSecret = defineSecret("DASHSCOPE_API_KEY");

// Konfigurasi AI dapat diubah lewat environment variable.
const AI_MODEL = process.env.AI_MODEL || "qwen3.8-max";
const AI_BASE_URL =
  process.env.AI_BASE_URL ||
  "https://ws-gtnn1g4470a876t0.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1";

// Model yang dipakai saat pesan menyertakan gambar (butuh model vision).
// Default memakai AI_MODEL; atur AI_VISION_MODEL bila modelnya berbeda,
// mis. qwen-vl-max / qwen2.5-vl-7b-instruct.
const AI_VISION_MODEL = process.env.AI_VISION_MODEL || AI_MODEL;

// Konfigurasi pembuatan gambar (text-to-image).
//
// Model gambar seperti Qwen-Image dipanggil lewat API NATIVE DashScope,
// bukan mode OpenAI-compatible, karena compatible-mode tidak melayani
// pembuatan gambar. Endpoint native diturunkan dari AI_BASE_URL
// (mis. .../compatible-mode/v1 -> .../api/v1) atau diatur lewat
// AI_IMAGE_BASE_URL bila memakai domain/region yang berbeda.
const AI_IMAGE_MODEL = process.env.AI_IMAGE_MODEL || "qwen-image-2.0-pro";
const AI_IMAGE_SIZE = process.env.AI_IMAGE_SIZE || "1024*1024";

// Batas lampiran gambar yang dikirim ke AI (multimodal).
const MAX_IMAGES = 3;
const MAX_IMAGE_DATA_URL_LENGTH = 6 * 1024 * 1024; // sekitar 3 MB gambar

const RATE_LIMIT = Number(process.env.AI_RATE_LIMIT || 30);
const RATE_WINDOW_MS = Number(process.env.AI_RATE_WINDOW_MS || 60 * 1000);

// Mode "thinking" ala Qwen membuat balasan pertama jauh lebih lambat.
// Default dimatikan agar respons terasa cepat; set AI_ENABLE_THINKING=true
// bila menginginkan penalaran panjang.
const AI_ENABLE_THINKING = process.env.AI_ENABLE_THINKING === "true";

// Inisialisasi Firebase Admin sekali saja.
function ensureFirebaseAdmin() {
  if (getApps().length > 0) return;

  if (process.env.FIREBASE_PROJECT_ID) {
    initializeApp({
      credential: applicationDefault(),
      projectId: process.env.FIREBASE_PROJECT_ID,
    });
  } else {
    // Di Cloud Functions kredensial diambil otomatis.
    initializeApp();
  }
}

// Klien AI dibuat lazily supaya secret bisa dibaca saat request masuk.
let aiClient = null;

function getAiClient() {
  if (aiClient) return aiClient;

  const apiKey = process.env.DASHSCOPE_API_KEY;

  if (!apiKey) {
    throw new Error("DASHSCOPE_API_KEY belum diatur.");
  }

  aiClient = new OpenAI({
    apiKey,
    baseURL: AI_BASE_URL,
  });

  return aiClient;
}

// Daftar origin yang diizinkan untuk akses browser (Flutter Web).
function buildCorsOrigin() {
  const extra = (process.env.ALLOWED_ORIGINS || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

  return function originCheck(origin, callback) {
    if (
      !origin ||
      /^https?:\/\/localhost:\d+$/.test(origin) ||
      /^https?:\/\/127\.0\.0\.1:\d+$/.test(origin) ||
      extra.includes(origin)
    ) {
      return callback(null, true);
    }

    return callback(new Error("Origin tidak diizinkan."));
  };
}

// Susun parameter chat completion. Model vision (VL) umumnya tidak
// mendukung mode "thinking", jadi parameter itu hanya dikirim ke model teks.
function buildChatParams({ model, messages, stream }) {
  const params = {
    model,
    messages,
    temperature: 0.7,
    max_completion_tokens: 4096,
  };

  if (stream) {
    params.stream = true;
  }

  if (!/vl/i.test(model)) {
    params.enable_thinking = AI_ENABLE_THINKING;
  }

  return params;
}

// Rapikan judul yang dihasilkan AI: buang awalan "Judul:", tanda kutip,
// newline, dan batasi panjangnya.
function sanitizeTitle(raw) {
  if (typeof raw !== "string") return "";

  let title = raw
    .replace(/\r?\n/g, " ")
    .replace(/^\s*(judul|title)\s*[:：-]\s*/i, "")
    .trim();

  title = title
    .replace(/^["'“”‘’`]+/, "")
    .replace(/["'“”‘’`]+$/, "")
    .replace(/[.。!?,;:]+$/, "")
    .replace(/\s+/g, " ")
    .trim();

  const MAX_TITLE_LENGTH = 60;

  if (title.length > MAX_TITLE_LENGTH) {
    title = `${title.substring(0, MAX_TITLE_LENGTH).trim()}...`;
  }

  return title;
}

// Turunkan base URL API native DashScope untuk pembuatan gambar.
//
// AI_BASE_URL default berakhiran "/compatible-mode/v1"; API native memakai
// prefix "/api/v1" pada host yang sama (host memuat Workspace ID).
function resolveImageApiBaseUrl() {
  const explicit = (process.env.AI_IMAGE_BASE_URL || "").trim();

  if (explicit) {
    return explicit.replace(/\/+$/, "");
  }

  const compatible = (AI_BASE_URL || "").replace(/\/+$/, "");

  if (compatible.endsWith("/compatible-mode/v1")) {
    return `${compatible.slice(0, -"/compatible-mode/v1".length)}/api/v1`;
  }

  return "https://dashscope.aliyuncs.com/api/v1";
}

// Ukuran gambar memakai format "lebar*tinggi" (mis. 1024*1024).
const IMAGE_SIZE_PATTERN = /^\d{3,4}\*\d{3,4}$/;

function normalizeImageSize(size) {
  if (typeof size === "string" && IMAGE_SIZE_PATTERN.test(size.trim())) {
    return size.trim();
  }

  return AI_IMAGE_SIZE;
}

// Minta gambar baru ke API native DashScope (mode sinkron) dan kembalikan
// URL gambar sementara (berlaku ~24 jam).
async function requestGeneratedImage({ prompt, negativePrompt, size }) {
  const apiKey = process.env.DASHSCOPE_API_KEY;

  if (!apiKey) {
    throw new Error("DASHSCOPE_API_KEY belum diatur.");
  }

  const url =
    `${resolveImageApiBaseUrl()}` +
    "/services/aigc/multimodal-generation/generation";

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: AI_IMAGE_MODEL,
      input: {
        messages: [
          {
            role: "user",
            content: [{ text: prompt }],
          },
        ],
      },
      parameters: {
        negative_prompt: negativePrompt || " ",
        prompt_extend: true,
        watermark: false,
        size,
      },
    }),
  });

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    const detail = data?.message || `HTTP ${response.status}`;
    throw new Error(`Penyedia gambar menolak permintaan: ${detail}`);
  }

  const content = data?.output?.choices?.[0]?.message?.content;
  const imageUrl = Array.isArray(content)
    ? content.map((item) => item?.image).find(Boolean)
    : null;

  if (!imageUrl) {
    const detail = data?.message || "respons tidak memuat gambar.";
    throw new Error(`Gagal membuat gambar: ${detail}`);
  }

  return imageUrl;
}

// Unduh gambar hasil lalu ubah menjadi data URL base64. Ini menghindari
// masalah CORS di Flutter Web dan membuat klien bisa langsung menampilkannya.
async function downloadImageAsDataUrl(imageUrl) {
  const response = await fetch(imageUrl);

  if (!response.ok) {
    throw new Error(`Gagal mengunduh gambar hasil (${response.status}).`);
  }

  const contentType = response.headers.get("content-type") || "image/png";
  const buffer = Buffer.from(await response.arrayBuffer());

  return `data:${contentType};base64,${buffer.toString("base64")}`;
}

// Helper sumber proyek dipindah ke ./source_extract.js

// Kirim respons AI secara bertahap (Server-Sent Events) agar terasa cepat.
// Bila panggilan dengan model vision gagal dan `fallback` diisi, coba sekali
// lagi memakai model teks biasa (tanpa gambar).
async function streamChatResponse(res, { messages, model, fallback }) {

  let stream = null;

  try {
    stream = await getAiClient().chat.completions.create(
      buildChatParams({ model, messages, stream: true })
    );
  } catch (error) {
    console.error("AI stream start error:", error.message);

    if (fallback) {
      try {
        stream = await getAiClient().chat.completions.create(
          buildChatParams({
            model: AI_MODEL,
            messages: fallback.messages,
            stream: true,
          })
        );
      } catch (fallbackError) {
        console.error("AI stream fallback error:", fallbackError.message);
      }
    }
  }

  if (!stream) {
    return res.status(502).json({
      error: "Gagal mendapatkan respons AI. Coba lagi nanti.",
    });
  }

  res.status(200);
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  // Cegah buffering oleh proxy (mis. Cloud Run / nginx).
  res.setHeader("X-Accel-Buffering", "no");

  if (typeof res.flushHeaders === "function") {
    res.flushHeaders();
  }

  const writeEvent = (data) => {
    res.write(`data: ${JSON.stringify(data)}\n\n`);
  };

  const writeDone = () => {
    res.write("data: [DONE]\n\n");
  };

  try {
    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;

      if (delta) {
        writeEvent({ delta });
      }
    }

    writeDone();
  } catch (error) {
    console.error("AI streaming error:", error.message);
    writeEvent({ error: "Koneksi ke AI terputus. Coba lagi." });
    writeDone();
  } finally {
    res.end();
  }
}

function createApp() {
  ensureFirebaseAdmin();

  const firebaseAuth = getAuth();
  const app = express();

  app.disable("x-powered-by");
  app.use(helmet());
  app.use(cors({ origin: buildCorsOrigin() }));
  // Lampiran gambar dikirim sebagai data URL base64, jadi limit dinaikkan.
  app.use(express.json({ limit: "25mb" }));

  // Batasi request per IP untuk kedua endpoint AI.
  const chatLimiter = rateLimit({
    windowMs: RATE_WINDOW_MS,
    limit: RATE_LIMIT,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: {
      error: "Terlalu banyak request. Coba lagi sebentar.",
    },
  });

  // Ekstraksi teks lebih berat, jadi limitnya lebih ketat.
  const extractLimiter = rateLimit({
    windowMs: 10 * 60 * 1000,
    limit: 30,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: {
      error: "Terlalu banyak permintaan ekstraksi. Coba lagi nanti.",
    },
  });

  // Verifikasi Firebase ID token.
  async function requireFirebaseAuth(req, res, next) {
    const authorization = req.headers.authorization || "";
    const match = authorization.match(/^Bearer (.+)$/);

    if (!match) {
      return res.status(401).json({
        error: "Login diperlukan.",
      });
    }

    try {
      const decodedToken = await firebaseAuth.verifyIdToken(match[1]);

      req.user = {
        uid: decodedToken.uid,
      };

      return next();
    } catch (error) {
      console.warn(
        "Firebase authentication ditolak:",
        error.code || error.message
      );

      return res.status(401).json({
        error: "Token login tidak valid atau sudah kedaluwarsa.",
      });
    }
  }

  // Endpoint pemeriksaan backend.
  app.get("/", (req, res) => {
    res.json({
      app: "Upatt AI Backend",
      status: "running",
    });
  });

  // Endpoint chat.
  app.post(
    "/api/chat",
    chatLimiter,
    requireFirebaseAuth,
    async (req, res) => {
      try {
        const {
          message,
          history = [],
          memorySummary = "",
        } = req.body || {};

        if (
          typeof message !== "string" ||
          !message.trim() ||
          message.length > 10000
        ) {
          return res.status(400).json({
            error: "Pesan harus diisi dan maksimal 10.000 karakter.",
          });
        }

        if (
          typeof memorySummary !== "string" ||
          memorySummary.length > 12000
        ) {
          return res.status(400).json({
            error: "Format memori percakapan tidak valid.",
          });
        }

        if (
          !Array.isArray(history) ||
          history.length > 20 ||
          !history.every(
            (item) =>
              item &&
              ["user", "assistant"].includes(item.role) &&
              typeof item.content === "string" &&
              item.content.length <= 10000
          )
        ) {
          return res.status(400).json({
            error: "Format riwayat chat tidak valid.",
          });
        }

        const rawImages = req.body.images;
        let images = [];

        if (rawImages !== undefined && rawImages !== null) {
          if (!Array.isArray(rawImages) || rawImages.length > MAX_IMAGES) {
            return res.status(400).json({
              error: `Maksimal ${MAX_IMAGES} gambar per pesan.`,
            });
          }

          for (const image of rawImages) {
            if (
              typeof image !== "string" ||
              !/^data:image\/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+$/.test(
                image
              ) ||
              image.length > MAX_IMAGE_DATA_URL_LENGTH
            ) {
              return res.status(400).json({
                error: "Format gambar tidak valid atau terlalu besar.",
              });
            }
          }

          images = rawImages;
        }

        // Sumber proyek (opsional): daftar {name, text} yang jadi konteks.
        const rawSources = req.body.sources;
        let sources = [];

        if (rawSources !== undefined && rawSources !== null) {
          if (
            !Array.isArray(rawSources) ||
            rawSources.length > 20 ||
            !rawSources.every(
              (item) =>
                item &&
                typeof item.name === "string" &&
                item.name.length <= 200 &&
                typeof item.text === "string" &&
                item.text.length <= 200000
            )
          ) {
            return res.status(400).json({
              error: "Format sumber proyek tidak valid.",
            });
          }

          sources = rawSources;
        }

        const sourceContext = buildSourceContext(sources);

        const messages = [
          {
            role: "system",
            content:
              "Kamu adalah Upatt, asisten AI yang ramah, jelas, " +
              "dan membantu. Jawab menggunakan bahasa pengguna. " +
              "Jika pengguna menggunakan bahasa Indonesia, balas " +
              "dengan bahasa Indonesia yang natural. " +
              "Format jawaban menggunakan Markdown bila membantu " +
              "(judul, daftar poin, **tebal**, `kode inline`, dan blok " +
              "kode dengan penanda bahasa). " +
              "Untuk rumus atau ekspresi matematika, gunakan LaTeX: " +
              "$...$ untuk rumus inline dan $$...$$ untuk rumus blok. " +
              "Tabel Markdown boleh dipakai bila membantu " +
              "perbandingan atau data. " +
              "Jangan membungkus seluruh jawaban dalam satu blok kode." +
              (memorySummary.trim()
                ? "\n\nRingkasan memori percakapan sebelumnya:\n" +
                  memorySummary
                : "") +
              sourceContext,
          },
          ...history,
          {
            role: "user",
            content: images.length
              ? [
                  { type: "text", text: message },
                  ...images.map((url) => ({
                    type: "image_url",
                    image_url: { url },
                  })),
                ]
              : message,
          },
        ];

        // Bila model vision gagal, ulangi tanpa gambar (teks saja).
        const fallback = images.length
          ? {
              messages: [
                ...messages.slice(0, messages.length - 1),
                { role: "user", content: message },
              ],
            }
          : null;

        const model = images.length ? AI_VISION_MODEL : AI_MODEL;

        // Mode streaming (SSE): jawaban dikirim bertahap.
        if (req.body?.stream === true) {
          return streamChatResponse(res, { messages, model, fallback });
        }

        let completion;

        try {
          completion = await getAiClient().chat.completions.create(
            buildChatParams({ model, messages })
          );
        } catch (error) {
          if (!fallback) throw error;

          console.error("AI vision error:", error.message);

          completion = await getAiClient().chat.completions.create(
            buildChatParams({ model: AI_MODEL, messages: fallback.messages })
          );
        }

        const reply = completion.choices[0]?.message?.content ?? "";

        return res.json({ reply });
      } catch (error) {
        console.error("AI API error:", error.message);

        if (res.headersSent) {
          return;
        }

        return res.status(500).json({
          error: "Gagal mendapatkan respons AI. Coba lagi nanti.",
        });
      }
    }
  );

  // Endpoint ringkasan memori.
  app.post(
    "/api/summarize",
    chatLimiter,
    requireFirebaseAuth,
    async (req, res) => {
      try {
        const {
          previousSummary = "",
          messages = [],
        } = req.body || {};

        if (
          typeof previousSummary !== "string" ||
          previousSummary.length > 12000 ||
          !Array.isArray(messages) ||
          messages.length < 1 ||
          messages.length > 100 ||
          !messages.every(
            (item) =>
              item &&
              ["user", "assistant"].includes(item.role) &&
              typeof item.content === "string" &&
              item.content.length <= 10000
          )
        ) {
          return res.status(400).json({
            error: "Data ringkasan tidak valid.",
          });
        }

        const completion = await getAiClient().chat.completions.create({
          model: AI_MODEL,
          messages: [
            {
              role: "system",
              content:
                "Buat ringkasan memori percakapan untuk asisten AI. " +
                "Gabungkan ringkasan lama dengan pesan baru. " +
                "Pertahankan tujuan pengguna, preferensi, keputusan, " +
                "konteks pekerjaan, fakta penting, dan hal yang belum selesai. " +
                "Jangan mengarang fakta. Tandai informasi yang belum pasti. " +
                "Tulis ringkas dalam bahasa Indonesia. Maksimal 1500 kata.",
            },
            {
              role: "user",
              content:
                "RINGKASAN SEBELUMNYA:\n" +
                (previousSummary || "(Belum ada)") +
                "\n\nPESAN BARU:\n" +
                messages
                  .map(
                    (item) =>
                      `${item.role === "user" ? "Pengguna" : "Upatt"}: ${item.content}`
                  )
                  .join("\n\n"),
            },
          ],
          temperature: 0.2,
          max_completion_tokens: 1800,
          enable_thinking: AI_ENABLE_THINKING,
        });

        const summary = completion.choices[0]?.message?.content?.trim();

        if (!summary) {
          return res.status(502).json({
            error: "Gagal membuat ringkasan percakapan.",
          });
        }

        return res.json({ summary });
      } catch (error) {
        console.error("Summarization error:", error.message);

        return res.status(500).json({
          error: "Gagal memperbarui memori percakapan.",
        });
      }
    }
  );

  // Endpoint judul sesi percakapan.
  // Membuat judul singkat dari TOPIK utama percakapan (bukan sekadar
  // mengulang pesan pertama pengguna).
  app.post(
    "/api/title",
    chatLimiter,
    requireFirebaseAuth,
    async (req, res) => {
      try {
        const { messages = [] } = req.body || {};

        if (
          !Array.isArray(messages) ||
          messages.length < 1 ||
          messages.length > 12 ||
          !messages.every(
            (item) =>
              item &&
              ["user", "assistant"].includes(item.role) &&
              typeof item.content === "string" &&
              item.content.trim().length > 0 &&
              item.content.length <= 4000
          )
        ) {
          return res.status(400).json({
            error: "Data judul percakapan tidak valid.",
          });
        }

        const completion = await getAiClient().chat.completions.create({
          ...buildChatParams({
            model: AI_MODEL,
            messages: [
              {
                role: "system",
                content:
                  "Kamu membuat judul singkat untuk sebuah sesi percakapan. " +
                  "Rangkum topik atau maksud utama percakapan, bukan sekadar " +
                  "mengulang kalimat pertama. Gunakan bahasa yang sama dengan " +
                  "pengguna. Maksimal 6 kata. Tanpa tanda kutip, tanpa tanda " +
                  "baca di akhir, dan tanpa awalan seperti 'Judul:'. " +
                  "Balas hanya judulnya saja.",
              },
              {
                role: "user",
                content: messages
                  .map(
                    (item) =>
                      `${item.role === "user" ? "Pengguna" : "Upatt"}: ${item.content}`
                  )
                  .join("\n"),
              },
            ],
          }),
          temperature: 0.3,
          max_completion_tokens: 32,
        });

        const title = sanitizeTitle(
          completion.choices[0]?.message?.content
        );

        if (!title) {
          return res.status(502).json({
            error: "Gagal membuat judul percakapan.",
          });
        }

        return res.json({ title });
      } catch (error) {
        console.error("Title generation error:", error.message);

        return res.status(500).json({
          error: "Gagal membuat judul percakapan.",
        });
      }
    }
  );

  // Penanganan error.
  // Endpoint pembuatan gambar dari prompt teks (text-to-image).
  app.post(
    "/api/image",
    chatLimiter,
    requireFirebaseAuth,
    async (req, res) => {
      try {
        const { prompt, negativePrompt = "", size } = req.body || {};

        if (
          typeof prompt !== "string" ||
          !prompt.trim() ||
          prompt.length > 2000
        ) {
          return res.status(400).json({
            error: "Tulis prompt gambar (maksimal 2000 karakter).",
          });
        }

        const imageUrl = await requestGeneratedImage({
          prompt: prompt.trim(),
          negativePrompt:
            typeof negativePrompt === "string"
              ? negativePrompt.trim().slice(0, 500)
              : "",
          size: normalizeImageSize(size),
        });

        const image = await downloadImageAsDataUrl(imageUrl);

        return res.json({ image, prompt: prompt.trim() });
      } catch (error) {
        console.error("Image generation error:", error.message);

        return res.status(502).json({
          error:
            error.message || "Gagal membuat gambar. Coba lagi sebentar.",
        });
      }
    }
  );

  // Endpoint ekstraksi teks dari file sumber proyek (mis. PDF materi).
  // Klien mengirim isi file sebagai base64; teks hasilnya disimpan di
  // Firestore oleh klien (tanpa Firebase Storage).
  app.post(
    "/api/extract",
    extractLimiter,
    requireFirebaseAuth,
    async (req, res) => {
      try {
        const { dataBase64, name = "", mimeType = "" } = req.body || {};

        let buffer;

        try {
          buffer = decodeBase64Payload(dataBase64, EXTRACT_MAX_BYTES);
        } catch (error) {
          return res.status(400).json({
            error: error.message || "File sumber tidak valid.",
          });
        }

        const result = await extractTextFromFile({
          buffer,
          name: typeof name === "string" ? name : "",
          mimeType: typeof mimeType === "string" ? mimeType : "",
        });

        const truncated = result.text.length > EXTRACT_MAX_CHARS;

        return res.json({
          text: truncated
            ? result.text.slice(0, EXTRACT_MAX_CHARS)
            : result.text,
          truncated,
          pages: result.pages,
          kind: result.kind,
          charCount: result.text.length,
        });
      } catch (error) {
        console.error("Extract error:", error.message);

        return res.status(502).json({
          error: error.message || "Gagal membaca isi file sumber.",
        });
      }
    }
  );

  app.use((err, req, res, next) => {
    if (res.headersSent) {
      return next(err);
    }

    if (err.type === "entity.too.large") {
      return res.status(413).json({
        error: "Ukuran request terlalu besar.",
      });
    }

    if (err instanceof SyntaxError && "body" in err) {
      return res.status(400).json({
        error: "Format JSON tidak valid.",
      });
    }

    console.error("Backend error:", err.message);

    return res.status(500).json({
      error: "Terjadi kesalahan pada backend.",
    });
  });

  return app;
}

const app = createApp();

// Cloud Function (v2). URL publik didapat setelah `firebase deploy`.
exports.api = onRequest(
  {
    region: process.env.FUNCTION_REGION || "asia-southeast1",
    secrets: [dashscopeSecret],
    maxInstances: 10,
    // Pembuatan gambar bisa memakan waktu lebih lama dari chat biasa.
    timeoutSeconds: 120,
  },
  app
);

// Server lokal untuk development: jalankan `node index.js`.
if (require.main === module) {
  const PORT = process.env.PORT || 3000;

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Upatt backend berjalan di http://localhost:${PORT}`);
  });
}
