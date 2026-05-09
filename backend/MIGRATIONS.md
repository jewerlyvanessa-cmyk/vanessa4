# Migrasi database

Di repo ini ada **dua mekanisme**; tim deploy harus tahu mana yang dipakai di lingkungan masing-masing.

## 1. File SQL di `migrations/`

- File `.sql` berurutan (nama berisi tanggal).
- Cocok untuk dijalankan manual dengan `psql`, GUI, atau skrip internal Anda.
- **Tidak** otomatis dijalankan oleh `npm run migrate:up`.

## 2. `node-pg-migrate` (`migrations_js/`)

- Perintah npm di root: `npm run migrate:create`, `npm run migrate:up`, `npm run migrate:down`.
- Konfigurasi: `backend/migrate.config.cjs`, folder `backend/migrations_js/`.

## Rekomendasi

- Untuk fitur baru: pilih **satu** jalur (SQL terpusat *atau* `node-pg-migrate`) dan catat di runbook deploy.
- Setelah menyatukan ke satu tool, pertimbangkan mengarsipkan atau menggabungkan yang lain agar urutan migrasi tidak dobel.
