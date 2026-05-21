#!/usr/bin/env bash
# Verifikasi skema minimal sebelum production (tanpa mengubah data).
# Usage: DB_NAME=vanessa_store ./backend/scripts/check_db_schema.sh

set -euo pipefail
DB_NAME="${DB_NAME:-vanessa_store}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"

psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
\echo '=== generate_nota_order ==='
SELECT proname FROM pg_proc WHERE proname = 'generate_nota_order';

\echo '=== items columns ==='
SELECT column_name FROM information_schema.columns
WHERE table_name = 'items'
  AND column_name IN ('ownership', 'stock_type', 'photo_produk', 'quantity')
ORDER BY 1;

\echo '=== orders status check (sample) ==='
SELECT pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conrelid = 'orders'::regclass AND conname = 'orders_status_check';

\echo '=== user_branch_roles roles ==='
SELECT DISTINCT role FROM user_branch_roles ORDER BY 1;

\echo '=== login user superadmin ==='
SELECT u.username, ubr.role, ubr.branch_id, ubr.is_primary
FROM users u
LEFT JOIN user_branch_roles ubr ON ubr.user_id = u.user_id
WHERE u.username = 'superadmin';
SQL

echo "OK: schema checks finished for database $DB_NAME"
