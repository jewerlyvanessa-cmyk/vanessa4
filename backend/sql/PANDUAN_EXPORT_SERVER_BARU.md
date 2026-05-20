# Panduan export database Vanessa ke server baru

Database aplikasi: **PostgreSQL** (nama default: `vanessa_store`).

## Cara yang disarankan (skema + semua data)

Dari **server lama** (yang masih berjalan), jalankan:

```bash
cd backend
cp .env.example .env   # isi DB_HOST, DB_USER, DB_PASSWORD, DB_NAME, DB_PORT
chmod +x scripts/export_full_database.sh scripts/import_full_database.sh
./scripts/export_full_database.sh
```

Hasil: `backend/sql/exports/vanessa_store_full_YYYYMMDD_HHMMSS.sql`  
(symlink: `vanessa_store_full_latest.sql`)

### Import di server baru

1. Install PostgreSQL 14+ (disarankan 16).
2. Salin file `.sql` ke server baru.
3. Atur `backend/.env` dengan kredensial PostgreSQL server baru.
4. Jalankan:

```bash
cd backend
chmod +x scripts/import_full_database.sh
./scripts/import_full_database.sh sql/exports/vanessa_store_full_latest.sql
```

5. Update `JWT_SECRET` dan variabel production di `.env` server baru.
6. Restart backend Node.js.

### Export manual (tanpa script)

```bash
export PGPASSWORD='password_anda'
pg_dump -h HOST_LAMA -p 5432 -U postgres -d vanessa_store \
  --format=plain --encoding=UTF8 --no-owner --no-acl \
  --clean --if-exists --create \
  -f vanessa_store_full.sql
```

Import:

```bash
psql -h HOST_BARU -p 5432 -U postgres -f vanessa_store_full.sql
```

---

## Format dump terpisah (opsional)

**Hanya skema** (tanpa data):

```bash
pg_dump -h HOST -U postgres -d vanessa_store --schema-only --no-owner --no-acl \
  -f vanessa_store_schema_only.sql
```

**Hanya data**:

```bash
pg_dump -h HOST -U postgres -d vanessa_store --data-only --no-owner \
  -f vanessa_store_data_only.sql
```

---

## Referensi skema (tanpa data, April 2026)

File referensi lama (belum termasuk semua migrasi terbaru):

- `unesential/sql_reference/pg_dump_schema_20260421.sql`

Jangan pakai ini saja untuk server baru production — gunakan **pg_dump dari database production** yang aktual.

Migrasi tambahan setelah April 2026 ada di `backend/migrations/` (54+ file).  
Jika membangun dari skema lama + migrasi:

```bash
psql ... -f unesential/sql_reference/pg_dump_schema_20260421.sql
./scripts/run_all_migrations.sh   # hati-hati: bisa error jika sudah pernah dijalankan
```

---

## Tabel utama

| Tabel | Keterangan |
|-------|------------|
| `branches` | Cabang / gudang / workshop |
| `users` | Pengguna |
| `user_branch_roles` | Role per cabang |
| `customers` | Pelanggan |
| `items` | Stok barang |
| `orders` | Order jual / buyback / service |
| `order_items` | Detail order |
| `order_cost_breakdowns` | Rincian biaya order |
| `payments` | Pembayaran |
| `item_conditions` | Kondisi buyback |
| `transfers` | Transfer antar cabang |
| `stock_mutations` | Mutasi stok |
| `stock_history` | Riwayat stok |
| `uploads` / `uploaded_files` | File upload |
| `store_operational_entries` | Entri operasional toko |

---

## Checklist server baru

- [ ] PostgreSQL terinstall & service jalan
- [ ] Database di-import dari `vanessa_store_full_*.sql`
- [ ] `backend/.env` (DB_*, JWT_SECRET, CORS_ORIGINS)
- [ ] Firewall: port 5432 hanya untuk app server (jangan expose publik)
- [ ] Backup otomatis harian (`pg_dump` cron)
- [ ] Test login aplikasi & satu transaksi sample

---

## Troubleshooting

| Masalah | Solusi |
|---------|--------|
| `permission denied` | `chmod +x scripts/*.sh` |
| `database already exists` | Hapus DB lama atau edit dump, hapus baris `CREATE DATABASE` |
| `role does not exist` | Dump sudah pakai `--no-owner`; buat user `postgres` atau sesuaikan |
| Ukuran dump besar | Normal jika banyak foto/metadata; bisa `gzip vanessa_store_full.sql` |
