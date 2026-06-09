#!/usr/bin/env bash
# P0 keamanan production — jalankan di SERVER setelah git pull (bukan di laptop dev).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export NODE_ENV=production

echo "==> P0: preflight production (env + modul + DB)"
node backend/scripts/preflight.js --ping-db

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
