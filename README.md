# Upatt AI

Aplikasi chatbot AI berbasis **Flutter** dengan backend **Firebase Cloud Functions**
dan penyimpanan riwayat chat di **Cloud Firestore**.

Upatt = asisten AI yang menjawab dalam bahasa pengguna, menyimpan riwayat
percakapan per akun, dan memiliki memori jangka panjang melalui ringkasan
percakapan otomatis.

---

## Fitur

- **Autentikasi** — daftar & login dengan email/password, login Google (web),
  serta reset password lewat email.
- **Auto-login** — sesi login tersimpan; pengguna langsung masuk ke halaman chat.
- **Chat AI** — jawaban dari model AI (Aliyun DashScope / Model Studio,
  default `qwen3.8-max`).
- **Dukungan Markdown** — jawaban bot di-render (judul, daftar, tebal,
  tabel, tautan); teksnya bisa dipilih (selectable).
- **Blok kode berwarna** — blok kode berpagar dengan penanda bahasa disorot
  (syntax highlighting, tema Atom One Dark) dan punya tombol salin.
- **Rumus matematika (LaTeX)** — rumus inline (`$...$` atau `\(...\)`) dan
  rumus blok (`$$...$$` atau `\[...\]`) dirender rapi.
- **Gambar Markdown** — gambar (`![alt](url)`) ditampilkan dengan placeholder
  saat memuat dan tampilan fallback bila gagal.
- **Respons streaming** — jawaban AI dikirim bertahap (Server-Sent Events)
  sehingga terasa lebih cepat dan langsung terlihat.
- **Riwayat chat** — daftar percakapan per pengguna, buka/lihat ulang, hapus.
- **Memori percakapan** — pesan lama otomatis diringkas agar konteks tetap
  terjaga tanpa melampaui batas jumlah pesan yang dikirim ke backend.
- **UI responsif** — sidebar riwayat pada layar lebar, drawer overlay pada
  layar sempit.
- **Device Preview** — hanya aktif saat mode debug.

### Belum tersedia (placeholder)
- Input suara (voice)
- Lampiran: kamera, foto, file

---

## Teknologi

| Lapisan | Teknologi |
|---|---|
| Aplikasi | Flutter 3.x, Dart 3.12+, Material 3 |
| Auth | Firebase Authentication (`firebase_auth`) |
| Database | Cloud Firestore (`cloud_firestore`) |
| Backend AI | Node.js 24, Express 5, Firebase Functions v2 |
| SDK AI | `openai` (kompatibel endpoint DashScope) |
| Keamanan backend | Verifikasi Firebase ID token + rate limit + helmet |
| Font | Google Fonts (Poppins) |
| Render Markdown | `flutter_markdown_plus`, `url_launcher` |
| Rumus matematika | `flutter_math_fork` (LaTeX) |
| Syntax highlight | `re_highlight` (tema Atom One Dark) |

---

## Arsitektur

```
┌─────────────────────┐        ID token (Bearer)        ┌──────────────────────────┐
│   Flutter App       │ ──────────────────────────────► │  Backend AI              │
│  (Upatt / aichatbot)│                                 │  Cloud Functions / Express│
│                     │ ◄────────── { reply } ───────── │  /api/chat /api/summarize │
└─────────┬───────────┘                                 └────────────┬─────────────┘
          │                                                          │
          │ Firestore SDK                                            │ HTTPS
          ▼                                                          ▼
┌─────────────────────┐                                 ┌──────────────────────────┐
│  Cloud Firestore    │                                 │  Model AI (DashScope)    │
│  users/{uid}/chats  │                                 │  qwen3.8-max             │
└─────────────────────┘                                 └──────────────────────────┘
```

Backend memverifikasi ID token Firebase sebelum meneruskan permintaan ke model AI.
Aplikasi tidak pernah menyimpan API key penyedia AI.

---

## Struktur Folder

```
Upatt-AI/
├─ lib/
│  ├─ main.dart                     # Entry point, DevicePreview, tema
│  ├─ firebase_options.dart         # Konfigurasi Firebase (generated)
│  ├─ core/
│  │  ├─ theme/                     # Warna, teks, tema aplikasi
│  │  └─ widgets/upatt_auth_background.dart
│  ├─ screens/
│  │  ├─ auth/                      # Login, register, forgot password, AuthGate
│  │  └─ home/home_screen.dart      # Layar chat
│  └─ services/
│     ├─ ai_service.dart            # HTTP client ke backend AI
│     └─ chat_repository.dart       # CRUD chat & memori di Firestore
├─ functions/                       # Backend AI (Cloud Functions)
│  ├─ index.js
│  ├─ .env.example
│  └─ package.json
├─ android/ · ios/ · web/ · ...     # Platform
└─ pubspec.yaml
```

---

## Prasyarat

- Flutter SDK 3.12+ (dites dengan 3.47)
- Node.js 20+ (backend `functions` menargetkan Node 24)
- Akun Firebase dengan proyek (default: `ai-chatbot-be649`)
- API key penyedia AI (DashScope / Alibaba Cloud Model Studio)
- (Untuk deploy backend) Firebase CLI + paket Blaze

---

## Setup

### 1. Aplikasi Flutter

```bash
flutter pub get
```

Konfigurasi Firebase sudah tersedia di `lib/firebase_options.dart` dan
`android/app/google-services.json`. Bila memakai proyek Firebase lain, jalankan
ulang konfigurasi:

```bash
flutterfire configure
```

### 2. Backend (lokal)

```bash
cd functions
npm install
```

Buat file `functions/.env` (salin dari `.env.example`):

```dotenv
DASHSCOPE_API_KEY=isi_api_key_anda
FIREBASE_PROJECT_ID=ai-chatbot-be649
PORT=3000
```

Untuk verifikasi token Firebase saat lokal, siapkan Application Default
Credentials:

```bash
gcloud auth application-default login
```

Jalankan server:

```bash
npm start          # http://localhost:3000
```

### 3. Jalankan aplikasi

```bash
# Android Emulator (default otomatis ke http://10.0.2.2:3000)
flutter run

# Arahkan ke backend tertentu
flutter run --dart-define=API_BASE_URL=https://<url-backend>
```

---

## Konfigurasi

### Aplikasi (`--dart-define`)

| Variabel | Deskripsi | Default |
|---|---|---|
| `API_BASE_URL` | URL root backend AI (tanpa `/api`). Path `/api/chat` ditambahkan otomatis. | `http://10.0.2.2:3000` (Android) / `http://localhost:3000` |

Contoh build rilis:

```bash
flutter build apk --dart-define=API_BASE_URL=https://<url-cloud-function>
```

### Backend (`functions/.env` / Secret Manager)

| Variabel | Wajib | Deskripsi |
|---|---|---|
| `DASHSCOPE_API_KEY` | ✅ | API key penyedia AI |
| `FIREBASE_PROJECT_ID` | | ID proyek Firebase (verifikasi token) |
| `PORT` | | Port server lokal (default `3000`) |
| `AI_MODEL` | | Model AI (default `qwen3.8-max`) |
| `AI_ENABLE_THINKING` | | Aktifkan mode "thinking" model (default `false`) |

---

## Deploy Backend (Cloud Functions)

1. Aktifkan paket **Blaze** di Firebase Console.
2. Login Firebase CLI:
   ```bash
   firebase login
   ```
3. Set secret API key:
   ```bash
   firebase functions:secrets:set DASHSCOPE_API_KEY
   ```
4. Deploy:
   ```bash
   firebase deploy --only functions
   ```
5. Catat URL fungsi, lalu build aplikasi dengan `--dart-define=API_BASE_URL=<url>`.

---

## API Backend

### `POST /api/chat`

Request:

```json
{
  "message": "Halo",
  "history": [{ "role": "user", "content": "..." }],
  "memorySummary": "...",
  "stream": true
}
```

- `history` maksimal 20 pesan.
- `stream: true` mengaktifkan Server-Sent Events: `data: {"delta":"..."}` diakhiri `data: [DONE]`.
- Tanpa `stream`, respons berupa `{ "reply": "..." }`.

### `POST /api/summarize`

```json
{ "previousSummary": "...", "messages": [{ "role": "user", "content": "..." }] }
```

---

## Model Data Firestore

```
users/{uid}
└─ chats/{chatId}
   ├─ title             : string
   ├─ createdAt         : timestamp
   ├─ updatedAt         : timestamp
   ├─ memorySummary     : string   (ringkasan percakapan lama)
   ├─ summarizedCount   : number   (jumlah pesan yang sudah diringkas)
   ├─ memoryUpdatedAt   : timestamp
   └─ messages/{msgId}
      ├─ role           : "user" | "assistant"
      ├─ content        : string
      └─ createdAt      : timestamp
```

### Cara kerja memori

1. Aplikasi hanya mengirim maksimal **20 pesan terakhir** ke backend
   (batas backend).
2. Setelah **12 pesan baru** menumpuk, pesan lama (kecuali **6 pesan terakhir**)
   diringkas lewat `/api/summarize` dan disimpan di `memorySummary`.
3. Ringkasan ini ikut dikirim sebagai konteks sehingga percakapan lama tetap
   dikenali tanpa memperbesar payload.

---

## Catatan Keamanan

- API key penyedia AI **hanya** ada di backend, tidak pernah di aplikasi.
- Setiap request AI wajib menyertakan Firebase ID token yang valid.
- Rate limit per IP untuk mencegah penyalahgunaan.
- Android: `INTERNET` permission dideklarasikan; cleartext HTTP hanya
  diizinkan untuk host development lokal (`localhost`, `127.0.0.1`, `10.0.2.2`)
  lewat `android/app/src/main/res/xml/network_security_config.xml`.
  Trafik lain wajib HTTPS.
- `DevicePreview` dinonaktifkan pada build rilis.

---

## Troubleshooting

| Gejala | Kemungkinan penyebab & solusi |
|---|---|
| Chat gagal setelah beberapa pesan | Riwayat melebihi batas. Sudah ditangani dengan pemotongan + memori; pastikan backend versi terbaru. |
| "Gagal mengirim pesan / respons AI" | Backend tidak berjalan, `API_BASE_URL` salah, atau token kedaluwarsa. |
| Tidak bisa akses backend dari HP fisik | Bound ke `0.0.0.0` + tambahkan IP LAN komputer ke `network_security_config.xml`, lalu set `API_BASE_URL` ke `http://<ip-lan>:3000`. |
| `401 Token login tidak valid` | `gcloud auth application-default login` belum dilakukan (dev lokal). |
| `403 / deploy gagal` | Firebase belum di paket Blaze, atau secret `DASHSCOPE_API_KEY` belum dibuat. |

---

## Lisensi

Proyek privat. Hak cipta © pemilik Upatt.
