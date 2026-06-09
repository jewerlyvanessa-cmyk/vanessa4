#!/usr/bin/env bash
# Restart backend production (jalankan di server setelah git pull / deploy).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "==> npm install (production deps)"
npm install --omit=dev

echo "==> Preflight env + modul + DB"
node backend/scripts/preflight.js --ping-db

echo "==> SQL migrations (idempotent)"
npm run migrate:sql

echo "==> PM2 restart"
if command -v pm2 >/dev/null 2>&1; then
  pm2 startOrRestart backend/ecosystem.config.cjs --update-env
  pm2 save
else
  echo "pm2 tidak ada — start manual: NODE_ENV=production node backend/scripts/start.js"
  exit 1
fi

sleep 2
echo "==> Health check lokal"
curl -sf "http://127.0.0.1:${PORT:-3000}/health/live" | head -c 200
echo ""
echo "==> Backend restart selesai. Cek: curl -sf https://mobile.vanessa.id/health/live"
