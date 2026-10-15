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
- **UI responsif** — sidebar riwayat di layar lebar; di layar sempit sidebar
  tampil penuh dari sisi kiri (menutupi bilah atas) dan bisa ditutup dengan
  menekan area di luarnya.
- **Lampiran** — kirim dari **kamera** (kamera in-app, jalan di Android/iOS/web),
  **galeri foto**, atau **file** (bisa beberapa sekaligus). Lampiran tampil di
  bubble pesan, thumbnail gambar tetap tampil setelah chat dimuat ulang, dan
  gambar dikirim ke AI agar bisa benar-benar "dibaca" (multimodal).
  Ketuk lampiran gambar untuk membukanya layar penuh (bisa di-zoom).
- **Pustaka** — menu **Pustaka** di sidebar menampilkan riwayat **gambar &
  file** yang pernah dikirim ke chatbot, dikumpulkan dari seluruh percakapan.
  Ada filter **Semua/Gambar/File** dan pencarian nama; gambar bisa dibuka
  layar penuh dan tiap item bisa ditautkan kembali ke percakapan asalnya.
- **Buat Gambar (text-to-image)** — menu **Buat Gambar** di sidebar membuka
  halaman khusus: tulis prompt, pilih rasio (1:1, 16:9, 3:4, 9:16), lalu model
  gambar (mis. `qwen-image-2.0-pro`) membuat gambar. Hasil tampil sebagai
  galeri di halaman itu dan bisa dibuka layar penuh.
- **Proyek** — menu **Proyek** di sidebar mengelompokkan percakapan berdasarkan
  topik. Tiap proyek bisa menyimpan **sumber materi** (mis. PDF matkul) yang
  isinya **dibaca AI** dan dipakai sebagai konteks jawaban, serta punya daftar
  chat sendiri. Chat di dalam proyek **terpisah** dari riwayat chat umum (di
  luar proyek) supaya tidak bercampur.
- **Device Preview** — hanya aktif saat mode debug.

### Belum tersedia (placeholder)
- Input suara (voice)

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
| Lampiran | `camera` (kamera in-app), `image_picker` (galeri), `file_picker` (file) |
| Penyimpanan sumber | Cloud Firestore (hanya teks hasil ekstraksi; tanpa Firebase Storage) |
| Ekstraksi dokumen | `pdf-parse` (backend) untuk PDF + file teks |
| Buat gambar | API native DashScope (Qwen-Image) lewat `fetch` di backend |

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

Pembuatan gambar (`/api/image`) memakai **API native DashScope** (model
Qwen-Image) karena mode OpenAI-compatible tidak melayani pembuatan gambar.

Sumber materi proyek **tidak** memakai Firebase Storage (butuh paket berbayar).
Saat sebuah sumber ditambahkan, aplikasi mengirim isi file (base64) ke backend
(`/api/extract`); backend mengekstrak teksnya (PDF memakai `pdf-parse`, file
teks dibaca langsung) dan mengembalikannya. Teks itulah yang disimpan di
Firestore dan dikirim sebagai konteks `sources` pada `/api/chat` saat pengguna
mengobrol di dalam proyek. File aslinya tidak disimpan (hanya teksnya).

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
│  │  ├─ home/home_screen.dart      # Layar chat
│  │  ├─ image/                     # Buat Gambar + penampil gambar
│  │  ├─ library/                   # Pustaka (riwayat lampiran)
│  │  └─ projects/                  # Proyek: daftar, detail (sumber + chat)
│  └─ services/
│     ├─ ai_service.dart            # HTTP client ke backend AI
│     ├─ chat_repository.dart       # CRUD chat & memori di Firestore
│     └─ project_repository.dart    # CRUD proyek, sumber (teks), chat proyek
├─ functions/                       # Backend AI (Cloud Functions)
│  ├─ index.js
│  ├─ source_extract.js             # Ekstraksi teks sumber proyek
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

### 2. Fitur Proyek (tanpa Firebase Storage)

Fitur **Proyek** tidak memerlukan Firebase Storage (yang butuh paket Blaze).
Sumber materi disimpan **hanya sebagai teks** di Cloud Firestore, yang sudah
dipakai aplikasi ini pada kuota gratis. Jadi tidak ada langkah setup tambahan.

Saat menambahkan sumber, aplikasi mengirim isi file ke backend `/api/extract`;
backend mengembalikan teksnya, teks itu disimpan di dokumen sumber. File asli
tidak diunggah/disimpan, tetapi teksnya bisa dilihat lewat tombol **Lihat
teks**. Batas ukuran file sumber 10 MB dan batas teks ± 1 MB per dokumen
(batas dokumen Firestore).

### 3. Backend (lokal)

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

### 4. Jalankan aplikasi

```bash
# Android Emulator (default otomatis ke http://10.0.2.2:3000)
flutter run

# Arahkan ke backend tertentu
flutter run --dart-define=API_BASE_URL=https://<url-backend>
```

### Testing di HP fisik

`10.0.2.2` hanya berlaku untuk Android **emulator**, jadi di HP fisik alamat itu
akan timeout. Ada dua cara:

**A. Atur dari dalam aplikasi (tanpa rebuild)**

1. Pastikan HP dan komputer berada di jaringan Wi-Fi yang sama.
2. Jalankan backend (`npm start`) dan izinkan port `3000` di firewall Windows.
3. Cari IP LAN komputer (`ipconfig`), misal `192.168.1.20`.
4. Buka sidebar → ikon ⚙️ **Alamat server** → isi `http://192.168.1.20:3000`
   → **Simpan**. Alamat disimpan di perangkat dan dipakai sampai diubah.

**B. `adb reverse` (kabel USB)**

```bash
adb reverse tcp:3000 tcp:3000
```

Lalu set alamat server ke `http://localhost:3000` (lewat dialog yang sama).

> Alternatif saat build: `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000`

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
| `AI_MODEL` | | Model AI teks (default `qwen3.8-max`) |
| `AI_VISION_MODEL` | | Model vision untuk membaca gambar (default sama dengan `AI_MODEL`, contoh `qwen-vl-max`) |
| `AI_IMAGE_MODEL` | | Model pembuat gambar (default `qwen-image-2.0-pro`; alternatif `qwen-image-2.0`, `qwen-image-3.0-pro`) |
| `AI_IMAGE_SIZE` | | Ukuran gambar default, format `lebar*tinggi` (default `1024*1024`) |
| `AI_IMAGE_BASE_URL` | | Override base URL API native DashScope (default diturunkan dari `AI_BASE_URL`) |
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
  "sources": [{ "name": "Materi A.pdf", "text": "isi materi..." }],
  "images": ["data:image/png;base64,..."],
  "stream": true
}
```

- `history` maksimal 20 pesan.
- `sources` opsional (maks. 20): teks sumber proyek sebagai konteks AI.
- `images` opsional: gambar (data URL base64) untuk model vision.
- `stream: true` mengaktifkan Server-Sent Events: `data: {"delta":"..."}` diakhiri `data: [DONE]`.
- Tanpa `stream`, respons berupa `{ "reply": "..." }`.

### `POST /api/summarize`

```json
{ "previousSummary": "...", "messages": [{ "role": "user", "content": "..." }] }
```

### `POST /api/title`

Membuat judul singkat untuk riwayat dari topik utama percakapan
(bukan sekadar menyalin pesan pertama pengguna).

```json
{ "messages": [{ "role": "user", "content": "..." }, { "role": "assistant", "content": "..." }] }
```

Respons: `{ "title": "Cara membuat kue bolu" }`

---

### `POST /api/image`

Membuat gambar dari prompt teks (text-to-image). Backend memanggil API native
DashScope dengan model `AI_IMAGE_MODEL`, lalu mengembalikan gambar sebagai data
URL base64 (aman dari CORS di Flutter Web).

```json
{
  "prompt": "poster healing bergaya gambar tangan, langit senja",
  "negativePrompt": "teks blur, tangan cacat",
  "size": "1024*1024"
}
```

- `prompt` wajib, maksimal 2000 karakter.
- `size` opsional, format `lebar*tinggi` (default `AI_IMAGE_SIZE`).
- Respons: `{ "image": "data:image/png;base64,...", "prompt": "..." }`.

---

### `POST /api/extract`

Mengekstrak teks dari file sumber proyek. Klien mengirim **isi file sebagai
base64** (tanpa Firebase Storage). Backend membaca isinya: PDF memakai
`pdf-parse`, file teks (txt, md, csv, json, dst.) dibaca langsung.

```json
{ "name": "Materi A.pdf", "mimeType": "application/pdf", "dataBase64": "JVBERi0xLjQK..." }
```

- `dataBase64` wajib (menerima string base64 murni maupun data URL).
- Batas ukuran file: 10 MB; teks yang dikembalikan maksimal 100.000 karakter.
- Respons: `{ "text": "...", "truncated": false, "pages": 12, "kind": "pdf", "charCount": 42000 }`.
- `kind`: `pdf`, `text`, atau `binary` (file yang tidak bisa dibaca).

---

## Model Data Firestore

```
users/{uid}
├─ chats/{chatId}
│  ├─ title             : string
│  ├─ projectId         : string | null   (null = chat umum)
│  ├─ createdAt         : timestamp
│  ├─ updatedAt         : timestamp
│  ├─ memorySummary     : string   (ringkasan percakapan lama)
│  ├─ summarizedCount   : number   (jumlah pesan yang sudah diringkas)
│  ├─ memoryUpdatedAt   : timestamp
│  └─ messages/{msgId}
│     ├─ role           : "user" | "assistant"
│     ├─ content        : string
│     └─ createdAt      : timestamp
└─ projects/{projectId}
   ├─ name              : string
   ├─ description       : string
   ├─ createdAt         : timestamp
   ├─ updatedAt         : timestamp
   └─ sources/{sourceId}
      ├─ name           : string
      ├─ type           : "pdf" | "text" | "image" | "file"
      ├─ size           : number
      ├─ text           : string   (teks hasil ekstraksi; file asli tidak disimpan)
      ├─ textTruncated  : boolean
      ├─ charCount      : number
      └─ createdAt      : timestamp
```

### Cara kerja memori

1. Aplikasi hanya mengirim maksimal **20 pesan terakhir** ke backend
   (batas backend).
2. Setelah **12 pesan baru** menumpuk, pesan lama (kecuali **6 pesan terakhir**)
   diringkas lewat `/api/summarize` dan disimpan di `memorySummary`.
3. Ringkasan ini ikut dikirim sebagai konteks sehingga percakapan lama tetap
   dikenali tanpa memperbesar payload.

### Cara kerja judul riwayat

1. Saat sesi baru dibuat, judul awalnya `New Chat`.
2. Setelah balasan AI pertama, aplikasi meminta `/api/title` untuk membuat
   judul dari **topik utama** percakapan (maks. 6 kata).
3. Sebelum hasil AI tiba, judul sementara dari pesan pertama sudah disimpan
   sebagai cadangan, jadi riwayat tidak pernah tertinggal sebagai `New Chat`.
4. Chat lama yang masih berjudul `New Chat` otomatis diperbarui saat dibuka.

### Cara kerja Pustaka

1. Pustaka membaca metadata lampiran (`attachments`) dari pesan-pesan di
   percakapan pengguna (mis. 50 percakapan terbaru), lalu menggabungkannya
   menjadi satu daftar, terbaru lebih dulu.
2. Lampiran **gambar** ditampilkan sebagai grid memakai thumbnail PNG (base64)
   yang tersimpan di pesan — sama dengan yang dipakai saat chat dimuat ulang,
   jadi resolusinya mengikuti thumbnail (bukan file asli).
3. Lampiran **file** hanya menyimpan metadata (nama, ukuran, jenis), jadi bisa
   dilihat detailnya tetapi isinya tidak dapat dibuka dari Pustaka.
4. Menekan **Buka chat** mengembalikan ID percakapan asal sehingga aplikasi
   langsung membuka percakapan tersebut.

### Cara kerja Proyek

1. Menu **Proyek** menampilkan daftar proyek. Tiap proyek punya halaman detail
   berisi **sumber materi** dan **chat** yang termasuk di dalamnya.
2. Menambahkan sumber: isi file dikirim (base64) ke `/api/extract`, backend
   mengembalikan teksnya, lalu teks itu disimpan di dokumen sumber (Firestore).
   File aslinya **tidak** diunggah/disimpan.
3. Chat yang dibuat saat sebuah proyek aktif diberi `projectId`. Riwayat di
   sidebar menampilkan **chat umum** saat di luar proyek, dan **chat proyek**
   saat berada di dalam proyek, sehingga keduanya tidak bercampur.
4. Saat mengirim pesan di dalam proyek, teks semua sumber dikirim ke
   `/api/chat` sebagai `sources`, lalu disuntikkan ke prompt AI (dengan
   pemotongan agar hemat token). Jika isi sumber tidak memuat jawaban, AI
   diminta menjawab jujur lalu menjawab sebisanya.
5. Menghapus proyek akan menghapus semua sumber dan chat di dalamnya.

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
| Menu **Buat Gambar** gagal/error | Model gambar belum aktif di workspace, atau backend belum versi terbaru. Set `AI_IMAGE_MODEL` (mis. `qwen-image-2.0-pro`) di `functions/.env`, lalu jalankan ulang/deploy backend. |
| Menambah sumber **Proyek** gagal | Backend belum versi terbaru (endpoint `/api/extract` kini menerima `dataBase64`), atau ukuran file melebihi 10 MB. Perbarui backend lalu coba file yang lebih kecil. |
| Isi PDF sumber kosong | PDF hasil pindai (gambar) tidak punya lapisan teks, jadi tidak ada yang bisa dibaca. Pakai PDF yang teksnya bisa diseleksi, atau file teks biasa. |
| Sumber gagal diekstrak (`/api/extract`) | Backend belum versi terbaru atau dependensi `pdf-parse` belum terpasang. Jalankan `npm install` di `functions`, lalu jalankan ulang/deploy backend. |

---

## Lisensi

Proyek privat. Hak cipta © pemilik Upatt.
