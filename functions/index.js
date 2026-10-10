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

// Secret di Cloud Functions dibaca dari Secret Manager.
// Saat development lokal, nilainya dibaca dari functions/.env.
const dashscopeSecret = defineSecret("DASHSCOPE_API_KEY");

// Konfigurasi AI dapat diubah lewat environment variable.
const AI_MODEL = process.env.AI_MODEL || "qwen3.8-max";
const AI_BASE_URL =
  process.env.AI_BASE_URL ||
  "https://ws-gtnn1g4470a876t0.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1";

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

// Kirim respons AI secara bertahap (Server-Sent Events) agar terasa cepat.
async function streamChatResponse(res, messages) {
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

  let stream;

  try {
    stream = await getAiClient().chat.completions.create({
      model: AI_MODEL,
      messages,
      temperature: 0.7,
      max_completion_tokens: 1024,
      stream: true,
      enable_thinking: AI_ENABLE_THINKING,
    });
  } catch (error) {
    console.error("AI stream start error:", error.message);
    writeEvent({ error: "Gagal mendapatkan respons AI. Coba lagi nanti." });
    writeDone();
    return res.end();
  }

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
  app.use(express.json({ limit: "256kb" }));

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
                : ""),
          },
          ...history,
          {
            role: "user",
            content: message.trim(),
          },
        ];

        // Mode streaming (SSE): jawaban dikirim bertahap.
        if (req.body?.stream === true) {
          return streamChatResponse(res, messages);
        }

        const completion = await getAiClient().chat.completions.create({
          model: AI_MODEL,
          messages,
          temperature: 0.7,
          max_completion_tokens: 1024,
          enable_thinking: AI_ENABLE_THINKING,
        });

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

  // Penanganan error.
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
