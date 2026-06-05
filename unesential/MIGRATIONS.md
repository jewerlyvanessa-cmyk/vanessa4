# Migrasi database

## Jalur utama (production): SQL + tracking otomatis

```bash
npm run migrate:sql
```

- Membaca file `.sql` berurutan di `backend/migrations/`
- Mencatat yang sudah jalan di tabel `sql_migrations`
- Aman dijalankan ulang (idempotent per file — skip jika sudah tercatat)

**Deploy:** setelah pull backend, jalankan `npm run migrate:sql` lalu restart PM2.

## Jalur alternatif: node-pg-migrate (`migrations_js/`)

Untuk migrasi baru yang ditulis sebagai JS:

```bash
npm run migrate:create -- nama_migrasi
npm run migrate:up
npm run migrate:down
```

Konfigurasi: `backend/migrate.config.cjs`, folder `backend/migrations_js/`.

## Rekomendasi tim

| Jenis perubahan | Gunakan |
|-----------------|---------|
| Schema existing (56 file SQL) | `npm run migrate:sql` |
| Fitur baru (prefer JS rollback) | `node-pg-migrate` di `migrations_js/` |

Jangan jalankan file SQL manual di server tanpa mencatat — gunakan `migrate:sql` agar urutan konsisten.
