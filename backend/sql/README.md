# SQL database Vanessa3

## Database baru (hanya struktur)

```bash
createdb -U postgres vanessa_store
psql -U postgres -d vanessa_store -f backend/sql/vanessa3_schema_new_database.sql
psql -U postgres -d vanessa_store -f backend/sql/seed_minimal.sql   # opsional
```

## Database sudah ada (skema lama) — error `branch_type does not exist`

Jalankan patch dulu, lalu seed:

```sql
ROLLBACK;   -- jika transaksi sebelumnya gagal
```

```bash
psql -U postgres -d vanessa_store -f backend/sql/patch_missing_columns.sql
psql -U postgres -d vanessa_store -f backend/sql/seed_minimal.sql
```

File `vanessa3_schema_new_database.sql` berisi:

- Fungsi: `round_to_nearest_5000`, `terbilang`, `update_item_conditions_updated_at`
- Tabel: `branches`, `users`, `user_branch_roles`, `customers`, `items`, `orders`, `order_items`, `order_cost_breakdowns`, `payments`, `item_conditions`, `transfers`, `stock_mutations`, `stock_history`, `uploads`, `store_operational_entries`
- Index & constraint sesuai migrasi terbaru (Mei 2026)

## Pindah dari server lama (struktur + data)

Dari server **lama**:

```bash
pg_dump -h HOST_LAMA -U postgres -d vanessa_store \
  --format=plain --no-owner --no-acl --clean --if-exists --create \
  -f vanessa3_full.sql
```

Di server **baru**:

```bash
psql -U postgres -f vanessa3_full.sql
```

## Migrasi bertahap (jika DB sudah ada skema lama)

```bash
cd backend
chmod +x scripts/run_all_migrations.sh
./scripts/run_all_migrations.sh
```

Hati-hati: migrasi bisa gagal jika kolom/tabel sudah ada.
