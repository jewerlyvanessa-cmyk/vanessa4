#!/usr/bin/env bash
# Import file SQL hasil pg_dump ke PostgreSQL (server baru)
# Usage: ./scripts/import_full_database.sh [path/to/vanessa3_full_YYYYMMDD.sql]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BACKEND_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SQL_FILE="${1:-$BACKEND_DIR/sql/exports/vanessa_store_full_latest.sql}"

if [[ ! -f "$SQL_FILE" ]]; then
  echo "File tidak ditemukan: $SQL_FILE"
  echo "Usage: $0 path/to/vanessa_store_full_YYYYMMDD.sql"
  exit 1
fi

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
export PGPASSWORD="${DB_PASSWORD:-}"

# Nama DB target (bisa override; default dari .env)
TARGET_DB="${DB_NAME:-vanessa_store}"

echo "Import ke: $TARGET_DB @ $DB_HOST:$DB_PORT"
echo "File: $SQL_FILE"
echo ""
read -r -p "Lanjutkan? File SQL dengan --create akan DROP/CREATE database. [y/N] " confirm
if [[ "${confirm,,}" != "y" ]]; then
  echo "Dibatalkan."
  exit 0
fi

# Koneksi ke postgres untuk perintah CREATE DATABASE (jika ada di dump)
psql \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --dbname=postgres \
  --set=ON_ERROR_STOP=1 \
  --file="$SQL_FILE"

echo ""
echo "Import selesai. Verifikasi:"
psql \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --dbname="$TARGET_DB" \
  --command="\dt" \
  --command="SELECT COUNT(*) AS branches FROM branches; SELECT COUNT(*) AS users FROM users; SELECT COUNT(*) AS orders FROM orders;"
