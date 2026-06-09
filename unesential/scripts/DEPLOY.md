# Deploy Backend & PM2

## Layout server production

| Layout | Path PM2 | Perintah restart |
|--------|----------|------------------|
| **Flat** (umum) | `nodeapp/ecosystem.config.cjs` | `bash scripts/restart-production.sh` |
| **Repo** | `nodeapp/backend/ecosystem.config.cjs` | `bash unesential/scripts/restart-backend-production.sh` |

Salin `backend/ecosystem.flat.config.cjs` → `ecosystem.config.cjs` di root flat jika belum ada.

Detail P0 (JWT, migrasi, preflight): [`P0_DEPLOY_SERVER.md`](P0_DEPLOY_SERVER.md)

## Migrasi SQL tanpa date-prefix

File di `backend/migrations/` tanpa prefix tanggal (mis. `add_kode_produk_...sql`) di-sort **sebelum** file `2026*.sql`. DB production yang sudah jalan aman — jangan rename di server. DB baru: urutan sudah benar karena file legacy dijalankan lebih dulu.

## Import Excel (`xlsx`)

- Batas upload: **15 MB** (`import_data.js` multer limit)
- Hanya superadmin (`POST /api/import/:dataType`)
- Jenis: `customers`, `branches`, `items`, `users`, `orders`
