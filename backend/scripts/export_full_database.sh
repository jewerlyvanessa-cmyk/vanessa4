#!/usr/bin/env bash
# Export seluruh database PostgreSQL Vanessa (skema + data) ke satu file .sql
# Jalankan dari folder backend: ./scripts/export_full_database.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BACKEND_DIR"

# Muat variabel dari .env jika ada
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-vanessa_store}"
DB_USER="${DB_USER:-postgres}"
export PGPASSWORD="${DB_PASSWORD:-}"

OUT_DIR="${OUT_DIR:-$BACKEND_DIR/sql/exports}"
mkdir -p "$OUT_DIR"

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="$OUT_DIR/vanessa_store_full_${STAMP}.sql"

echo "Export database: $DB_NAME @ $DB_HOST:$DB_PORT (user: $DB_USER)"
echo "Output: $OUT_FILE"

pg_dump \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --dbname="$DB_NAME" \
  --format=plain \
  --encoding=UTF8 \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  --create \
  --verbose \
  --file="$OUT_FILE"

# Buat symlink ke file terbaru (opsional)
ln -sf "$(basename "$OUT_FILE")" "$OUT_DIR/vanessa_store_full_latest.sql"

echo ""
echo "Selesai. Ukuran file:"
ls -lh "$OUT_FILE"
echo ""
echo "Untuk import di server baru:"
echo "  ./scripts/import_full_database.sh \"$OUT_FILE\""
