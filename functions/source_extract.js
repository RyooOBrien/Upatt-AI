// Helper untuk fitur "sumber proyek" (tanpa Firebase Storage).
//
// Aplikasi mengirim isi file sebagai base64 ke backend, backend mengekstrak
// teksnya (PDF/teks), lalu teks itulah yang disimpan di Firestore dan dipakai
// sebagai konteks AI.

// Batas ukuran file sumber yang diproses (byte setelah decode).
const EXTRACT_MAX_BYTES = 10 * 1024 * 1024; // 10 MB

// Batas panjang teks yang dikembalikan ke klien untuk disimpan.
const EXTRACT_MAX_CHARS = 100000;

// Batas total teks sumber yang disuntikkan ke prompt AI (hemat token).
const SOURCE_CONTEXT_MAX_CHARS = 60000;

// Decode payload base64 menjadi Buffer dengan batas ukuran.
// Menerima string base64 murni maupun data URL ("data:...;base64,...").
function decodeBase64Payload(dataBase64, maxBytes) {
  if (typeof dataBase64 !== "string" || !dataBase64.trim()) {
    throw new Error("Isi file sumber kosong.");
  }

  const withoutPrefix = dataBase64.includes(",")
    ? dataBase64.slice(dataBase64.indexOf(",") + 1)
    : dataBase64;
  const trimmed = withoutPrefix.trim();

  // Base64 berukuran ~4/3 dari data aslinya.
  if (trimmed.length > Math.ceil((maxBytes * 4) / 3) + 4096) {
    throw new Error("Ukuran file sumber terlalu besar (maks 10 MB).");
  }

  const buffer = Buffer.from(trimmed, "base64");

  if (!buffer.length) {
    throw new Error("Isi file sumber tidak valid.");
  }

  if (buffer.length > maxBytes) {
    throw new Error("Ukuran file sumber terlalu besar (maks 10 MB).");
  }

  return buffer;
}

const TEXT_EXTENSIONS = new Set([
  "txt", "text", "md", "markdown", "csv", "tsv", "json", "xml",
  "html", "htm", "log", "yaml", "yml", "ini", "conf", "sql", "css",
  "js", "ts", "jsx", "tsx", "dart", "py", "java", "kt", "c", "cpp",
  "h", "cs", "go", "rs", "php", "rb", "sh", "swift",
]);

function fileExtension(name) {
  if (typeof name !== "string" || !name.includes(".")) return "";

  return name.split(".").pop().trim().toLowerCase();
}

function isTextLikeFile(name, mimeType) {
  if (typeof mimeType === "string" && mimeType) {
    if (
      mimeType.startsWith("text/") ||
      mimeType === "application/json" ||
      mimeType === "application/xml" ||
      mimeType === "application/javascript"
    ) {
      return true;
    }
  }

  return TEXT_EXTENSIONS.has(fileExtension(name));
}

// Ekstraksi teks dari file sumber (PDF atau file teks).
async function extractTextFromFile({ buffer, name, mimeType }) {
  const ext = fileExtension(name);

  if (mimeType === "application/pdf" || ext === "pdf") {
    // Dimuat lazily agar kegagalan dependensi tidak mematikan backend.
    const { PDFParse } = require("pdf-parse");
    const parser = new PDFParse({ data: buffer });

    try {
      const parsed = await parser.getText();
      const text = (parsed.text || "")
        .replace(/\r\n/g, "\n")
        .replace(/[ \t]+\n/g, "\n")
        .replace(/\n{3,}/g, "\n\n")
        .trim();

      return {
        text,
        pages: parsed.total || parsed.pages || 0,
        kind: "pdf",
      };
    } finally {
      await parser.destroy().catch(() => {});
    }
  }

  if (isTextLikeFile(name, mimeType)) {
    const text = buffer.toString("utf8").replace(/\r\n/g, "\n").trim();

    return { text, pages: 0, kind: "text" };
  }

  return { text: "", pages: 0, kind: "binary" };
}

// Susun bagian sistem berisi teks sumber proyek, dengan pemotongan hemat token.
function buildSourceContext(sources) {
  if (!Array.isArray(sources) || sources.length === 0) return "";

  const parts = [];
  let used = 0;

  for (const source of sources) {
    const name =
      typeof source?.name === "string" && source.name.trim()
        ? source.name.trim().slice(0, 200)
        : "Sumber";
    const text =
      typeof source?.text === "string" ? source.text.trim() : "";

    if (!text) continue;

    const remaining = SOURCE_CONTEXT_MAX_CHARS - used;

    if (remaining <= 200) break;

    let body = text;

    if (body.length > remaining) {
      body = `${body.slice(0, remaining)}\n…(dipotong)`;
    }

    parts.push(`### ${name}\n${body}`);
    used += name.length + body.length + 8;
  }

  if (parts.length === 0) return "";

  return (
    "\n\nKonteks proyek: berikut sumber materi dari pengguna. " +
    "Pakai informasi ini untuk menjawab bila relevan dan sebutkan nama " +
    "sumbernya. Jika jawabannya tidak ada di sumber, katakan dengan jujur " +
    "lalu jawab sebisamu.\n\n" +
    parts.join("\n\n---\n\n")
  );
}

module.exports = {
  EXTRACT_MAX_BYTES,
  EXTRACT_MAX_CHARS,
  SOURCE_CONTEXT_MAX_CHARS,
  decodeBase64Payload,
  isTextLikeFile,
  extractTextFromFile,
  buildSourceContext,
};
