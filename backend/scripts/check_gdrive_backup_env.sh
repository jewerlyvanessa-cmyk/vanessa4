#!/usr/bin/env bash
# Diagnosa backup Google Drive — jalankan di server (SSH).
#   cd /path/to/nodeapp && bash backend/scripts/check_gdrive_backup_env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"

echo "==> Root project: $ROOT_DIR"
echo "==> Backend:      $BACKEND_DIR"

# .env seperti PM2/dotenv di deploy Anda (nodeapp/.env atau backend/.env)
for ENV_FILE in "$ROOT_DIR/.env" "$BACKEND_DIR/.env"; do
  if [[ -f "$ENV_FILE" ]]; then
    echo ""
    echo "==> Memuat: $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source <(grep -E '^GOOGLE_DRIVE_|^PORT=' "$ENV_FILE" | sed 's/^/export /')
    set +a
    break
  fi
done

FOLDER_ID="${GOOGLE_DRIVE_FOLDER_ID:-}"
SA_PATH="${GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH:-}"

echo ""
echo "--- GOOGLE_DRIVE_FOLDER_ID ---"
if [[ -n "$FOLDER_ID" ]]; then
  echo "  set: ya (${#FOLDER_ID} karakter)"
  if [[ "$FOLDER_ID" == *'?'* ]] || [[ "$FOLDER_ID" == *'drive.google.com'* ]]; then
    echo "  PERINGATAN: hapus ?usp=sharing atau URL — hanya ID folder saja"
  fi
else
  echo "  set: TIDAK"
fi

echo ""
echo "--- GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH ---"
if [[ -n "$SA_PATH" ]]; then
  echo "  path: $SA_PATH"
  if [[ -f "$SA_PATH" ]]; then
    echo "  file: ADA ($(wc -c <"$SA_PATH") bytes)"
    if command -v jq >/dev/null 2>&1; then
      echo "  client_email: $(jq -r .client_email "$SA_PATH")"
    else
      echo "  client_email: $(grep -o '"client_email"[[:space:]]*:[[:space:]]*"[^"]*"' "$SA_PATH" | head -1)"
    fi
  else
    echo "  file: TIDAK ADA — upload JSON key ke path ini atau perbaiki path"
    echo "  Coba cari file:"
    find /home/vanessa /home/web -name 'gdrive-sa.json' 2>/dev/null | head -5 || true
  fi
else
  echo "  set: TIDAK"
fi

echo ""
echo "--- googleapis (node_modules) ---"
cd "$ROOT_DIR"
if [[ ! -d node_modules ]]; then
  echo "  node_modules: TIDAK ADA di $ROOT_DIR"
  echo "  Jalankan: cd $ROOT_DIR && npm install --omit=dev"
else
  if node -e "require.resolve('googleapis'); console.log('  OK:', require.resolve('googleapis'))" 2>/dev/null; then
    :
  else
    echo "  googleapis: TIDAK TERPASANG"
    echo "  Jalankan: cd $ROOT_DIR && npm install --omit=dev"
  fi
fi

echo ""
echo "--- Status API (sama seperti app) ---"
cd "$BACKEND_DIR"
node -e "
require('dotenv').config({ path: require('path').join('$ROOT_DIR', '.env') });
require('dotenv').config({ path: require('path').join('$BACKEND_DIR', '.env') });
const s = require('./lib/google_drive_backup').getGoogleDriveBackupStatus();
console.log(JSON.stringify(s, null, 2));
"
