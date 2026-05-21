# SQL database Vanessa3

## Urutan yang benar (production / server baru)

| Langkah | File | Kapan |
|--------|------|--------|
| 1 | `vanessa3_schema_new_database.sql` | Database kosong |
| 2 | **`patch_vanessa3_production_complete.sql`** | **Wajib** setelah skema atau DB lama |
| 3 | `seed_minimal.sql` | User/cabang awal (opsional) |
| 4 | `backend/.env` + `pm2 restart` | API harus baca env DB yang sama |

**Jangan** menjalankan semua 54 file di `backend/migrations/` pada DB yang sudah pakai skema baru — berisiko bentrok.

```bash
createdb -U postgres vanessa_store
psql -U postgres -d vanessa_store -f backend/sql/vanessa3_schema_new_database.sql
psql -U postgres -d vanessa_store -f backend/sql/patch_vanessa3_production_complete.sql
psql -U postgres -d vanessa_store -f backend/sql/seed_minimal.sql
chmod +x backend/scripts/check_db_schema.sh
DB_NAME=vanessa_store backend/scripts/check_db_schema.sh
```

## Error umum

| Gejala | Penyebab | Perbaikan |
|--------|----------|-----------|
| `column "ownership" does not exist` | DB belum di-patch | `patch_vanessa3_production_complete.sql` |
| `function generate_nota_order does not exist` | Sama | Patch di atas |
| `current transaction is aborted` | Query pertama gagal; lanjutan diabaikan | `ROLLBACK;` lalu patch; deploy backend terbaru |
| Submit OK di SQL client, gagal di app | API pakai DB lain (tanpa `.env`) | `backend/.env` + `STRICT_DB_ENV=true` + `pm2 restart` |
| Login HTTP 500 | Kolom `branches` / `user_branch_roles` atau user tanpa role | Patch lengkap + `seed_minimal` / `setup_superadmin.js` |
| Pembayaran DP gagal `orders_status_check` | Status `confirmed` tidak ada di CHECK | Patch lengkap (perluas status) |
| Bayar Today / laporan kasir kosong padahal sudah bayar | `validated_by` kosong/salah, filter cabang, atau kolom belum ada | Deploy `payments_core.js` + app kasir terbaru; jalankan patch (`validated_by`); login ulang; cek SQL di bawah |
| Order Today kosong (CS / admin toko) | Filter tanggal WIB, `user_id` CS, atau `branch_id` tidak cocok | Deploy `order_calendar_date_sql` + `orders_daily_handler`; pastikan cabang aktif & login ulang; CS: order harus `user_id` = user login |
| Order / pembayaran **gagal memuat** (403) | `user_branch_roles` tidak punya cabang yang diminta | Deploy `order_branch_scope.js` terbaru; login ulang; pastikan `branch_id` di UI = cabang JWT |
| Order / pembayaran **gagal memuat** (500) | Query menyentuh `payment_date` / `o.jumlah` padahal kolom tidak ada | Deploy `payments_core.js` + `order_today_stats_compute.js` + `payments_schema_helpers.js` |
| Manajer laporan kosong | Token tanpa cabang atau 403 cabang | Role `manajer` boleh semua cabang; kirim `branch_id` per cabang di query |

**Cek pembayaran di DB (ganti tanggal & cabang):**

```sql
SELECT p.payment_id, p.order_id, p.amount, p.status, p.validated_by,
       o.branch_id, p.revenue_branch_id,
       (timezone('Asia/Jakarta', p.created_at))::date AS hari_wib
FROM payments p
JOIN orders o ON o.order_id = p.order_id
WHERE p.status = 'completed'
  AND (timezone('Asia/Jakarta', p.created_at))::date = CURRENT_DATE
  AND o.branch_id = 6;
```

## File patch (legacy)

| File | Gunakan |
|------|---------|
| **`patch_vanessa3_production_complete.sql`** | **Utama** — gabungan semua patch penting |
| `patch_submit_penjualan.sql` | Subset (nota + items saja) |
| `patch_missing_columns.sql` | Subset kolom tanpa status orders |
| `patch_items_ownership_only.sql` | Minimal setelah transaksi error |

## Pindah server (data + struktur)

```bash
pg_dump -h HOST_LAMA -U postgres -d vanessa_store \
  --format=plain --no-owner --no-acl --clean --if-exists \
  -f vanessa_store_full.sql
psql -U postgres -d vanessa_store -f vanessa_store_full.sql
psql -U postgres -d vanessa_store -f backend/sql/patch_vanessa3_production_complete.sql
```

## PM2 / `.env` (wajib — error `auth_failed` = password DB salah)

Log `routine: auth_failed` + `Missing env vars` = **file `.env` tidak ada atau tidak terbaca**. API memakai password default `password` yang ditolak PostgreSQL.

Buat file **`backend/.env`** (satu folder dengan `server.js`):

```env
NODE_ENV=production
STRICT_DB_ENV=true
DB_HOST=vanessa.id
DB_NAME=vanessa_store
DB_USER=postgres
DB_PASSWORD=PASSWORD_POSTGRES_ANDA
DB_PORT=5432
JWT_SECRET=...
CORS_ORIGINS=https://mobile.vanessa.id,https://app.vanessa.id
PORT=3000
```

Di server (sesuaikan path deploy):

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
cp .env.example .env   # lalu edit DB_PASSWORD
nano .env
pm2 delete vanessa
pm2 start ecosystem.config.cjs
pm2 logs vanessa --lines 30
```

Log harus:

```
[db] Pool: postgres@vanessa.id:5432/vanessa_store (.env loaded)
```

**Penting:** `DB_HOST` harus hostname/IP server PostgreSQL (`vanessa.id` → `103.247.10.211`), **bukan** `localhost`, kecuali Postgres jalan di mesin yang sama dengan API.

**Bukan** `NO .env file` atau `Missing env vars` atau `auth_failed`.
