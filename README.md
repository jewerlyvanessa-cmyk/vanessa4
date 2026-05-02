# Vanessa (vanessa3)

Aplikasi operasional toko & workshop berbasis **Flutter** dengan backend **Node.js (Express)**, database **PostgreSQL**, upload storage, dan realtime WebSocket.

## Dokumentasi utama

- **Arsitektur**: `ARCHITECTURE.md`
- Dokumen lain: `DOKUMENTASI_INDEX.md`, `START_HERE.md`, `arsitektur_aplikasi.md`

## Struktur repo (ringkas)

- Frontend Flutter: `lib/`
- Backend Express: `backend/`

## Menjalankan aplikasi (ringkas)

### Frontend (Flutter)

```bash
flutter pub get
flutter run
```

### Backend (Express)

```bash
cd backend
npm install
node server.js
```

Catatan:
- Port backend **default** ditentukan di `backend/server.js` (`process.env.PORT || 3000`).
- Aplikasi Flutter mengambil base URL dari `lib/utils/network_config.dart` (saat ini diarahkan ke port `4000`).
- Jika kamu menjalankan backend lokal dan Flutter tidak bisa konek, cek bagian **“Port & Deployment”** di `ARCHITECTURE.md`.

## Database migrations (node-pg-migrate)

Repo ini mendukung migrasi via `node-pg-migrate` (JS) di folder `backend/migrations_js/`.

```bash
# Create a new migration
npm run migrate:create -- add_new_table

# Run migrations
npm run migrate:up

# Rollback one migration
npm run migrate:down
```

Konfigurasi DB dibaca dari env (lihat `backend/.env.example`) melalui `backend/migrate.config.cjs`.
