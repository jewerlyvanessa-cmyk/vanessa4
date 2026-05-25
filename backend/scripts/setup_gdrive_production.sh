#!/usr/bin/env bash
# Setup backup Google Drive di server produksi (layout nodeapp).
# Jalankan di server setelah file JSON ada:
#   bash /home/vanessa/web/mobile.vanessa.id/private/nodeapp/scripts/setup_gdrive_production.sh
set -euo pipefail

NODEAPP="${NODEAPP_DIR:-/home/vanessa/web/mobile.vanessa.id/private/nodeapp}"
SECRETS="${SECRETS_DIR:-/home/vanessa/web/mobile.vanessa.id/private/secrets}"
SA_FILE="${SECRETS}/gdrive-sa.json"
ENV_FILE="${NODEAPP}/.env"

echo "==> nodeapp: $NODEAPP"
echo "==> secrets: $SECRETS"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env tidak ada: $ENV_FILE"
  exit 1
fi

mkdir -p "$SECRETS"

if [[ ! -f "$SA_FILE" ]]; then
  echo ""
  echo "ERROR: File service account belum ada:"
  echo "  $SA_FILE"
  echo ""
  echo "Buat dulu (tempel JSON key dari Google Cloud):"
  echo "  nano $SA_FILE"
  echo "  chmod 600 $SA_FILE"
  exit 1
fi

if [[ -d "$SA_FILE" ]]; then
  echo "ERROR: $SA_FILE adalah FOLDER. Hapus lalu buat ulang sebagai file JSON."
  exit 1
fi

# Pastikan .env punya path benar
if ! grep -q '^GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH=' "$ENV_FILE"; then
  echo "GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH=$SA_FILE" >> "$ENV_FILE"
  echo "Ditambahkan GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH ke .env"
else
  sed -i "s|^GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH=.*|GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH=$SA_FILE|" "$ENV_FILE"
  echo "Path service account di .env diselaraskan."
fi

echo ""
echo "==> npm install googleapis (di nodeapp)"
cd "$NODEAPP"
if [[ -f package.json ]]; then
  npm install googleapis --save --omit=dev
else
  npm init -y
  npm install googleapis --save --omit=dev
fi

echo ""
echo "==> Verifikasi"
node -e "
require('dotenv').config();
const fs = require('fs');
const p = process.env.GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH;
console.log('SA path:', p);
console.log('SA file exists:', fs.existsSync(p));
try { console.log('googleapis:', require.resolve('googleapis')); } catch (e) { console.log('googleapis: MISSING'); process.exit(1); }
const s = require('./lib/google_drive_backup').getGoogleDriveBackupStatus();
console.log(JSON.stringify(s, null, 2));
if (!s.configured) process.exit(2);
"

echo ""
echo "==> Restart PM2"
if command -v pm2 >/dev/null 2>&1; then
  pm2 restart vanessa --update-env
  echo "Selesai. Refresh menu BACKUP DRIVE di app."
else
  echo "PM2 tidak ditemukan — restart API manual."
fi
