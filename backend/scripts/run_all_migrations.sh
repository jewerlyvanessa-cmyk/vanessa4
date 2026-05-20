#!/usr/bin/env bash
# Jalankan semua file .sql di backend/migrations (urut nama file = urut tanggal)
# Gunakan HANYA jika database sudah punya skema dasar (mis. dari pg_dump lama) dan perlu patch migrasi.
# Untuk server baru lengkap, pakai export_full_database.sh + import_full_database.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATIONS_DIR="$BACKEND_DIR/migrations"
cd "$BACKEND_DIR"

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

echo "Menjalankan migrasi ke $DB_NAME @ $DB_HOST:$DB_PORT"

shopt -s nullglob
files=("$MIGRATIONS_DIR"/*.sql)
IFS=$'\n' files=($(sort <<<"${files[*]}"))
unset IFS

for f in "${files[@]}"; do
  echo "==> $(basename "$f")"
  psql \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --username="$DB_USER" \
    --dbname="$DB_NAME" \
    --set=ON_ERROR_STOP=1 \
    --file="$f"
done

echo "Semua migrasi selesai."
