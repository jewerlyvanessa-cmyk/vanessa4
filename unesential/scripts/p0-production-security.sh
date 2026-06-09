#!/usr/bin/env bash
# P0 keamanan production — jalankan di SERVER setelah git pull (bukan di laptop dev).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Production path umum (lihat backend/scripts/fix_production_login.sh)
NODEAPP_HINT="${NODEAPP_HINT:-/home/vanessa/web/mobile.vanessa.id/private/nodeapp}"

export NODE_ENV=production

if [[ -f backend/scripts/preflight.js ]]; then
  PREFLIGHT="node backend/scripts/preflight.js"
elif [[ -f scripts/preflight.js ]]; then
  PREFLIGHT="node scripts/preflight.js"
else
  echo "ERROR: preflight.js tidak ditemukan. cd ke root repo (mis. $NODEAPP_HINT)"
  exit 1
fi

echo "==> P0: preflight production (env + modul + DB)"
$PREFLIGHT --ping-db

echo ""
echo "==> Rotasi JWT (jika secret pernah bocor di git):"
echo "    1. node backend/scripts/generate-jwt-secret.js"
echo "    2. Ganti JWT_SECRET di backend/.env (atau .env flat di nodeapp)"
echo "    3. pm2 restart vanessa --update-env"
echo "    4. Semua user harus login ulang"
echo ""
echo "==> Rotasi password DB: ubah di Postgres + DB_PASSWORD di .env"
echo ""
read -r -p "Lanjut deploy backend (npm install + migrate + pm2)? [y/N] " ans
if [[ "${ans,,}" != "y" ]]; then
  echo "Dibatalkan. Preflight sudah OK."
  exit 0
fi

exec bash unesential/scripts/restart-backend-production.sh
