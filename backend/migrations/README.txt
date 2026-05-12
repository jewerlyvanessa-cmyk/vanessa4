MIGRASI DATABASE — vanessa3 backend
====================================

1) File SQL di folder ini (backend/migrations/*.sql)
   - Biasanya dijalankan manual di PostgreSQL (psql / GUI) atau oleh skrip deploy tim.
   - Urutan: gunakan prefix tanggal pada nama file; jangan loncat versi.

2) node-pg-migrate (package.json: migrate:up / migrate:down)
   - Konfigurasi: backend/migrate.config.cjs
   - Folder migrasi JS: backend/migrations_js (terpisah dari file .sql di atas).

3) Rekomendasi operasional
   - Pilih SATU jalur sebagai "sumber kebenaran" utama untuk environment baru,
     atau dokumentasikan di runbook deploy: urutan .sql mana yang sudah termasuk di JS.

Tanggal catatan: 2026-05-14
