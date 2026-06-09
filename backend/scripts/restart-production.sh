#!/usr/bin/env bash
# Restart API production — jalankan DI SERVER dari folder app (flat nodeapp).
#   cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
#   bash scripts/restart-production.sh
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_ROOT"

echo "==> App root: $APP_ROOT"

if [[ ! -f "$APP_ROOT/ecosystem.config.cjs" ]]; then
  echo "ERROR: ecosystem.config.cjs tidak ada di $APP_ROOT"
  echo "Salin backend/ecosystem.flat.config.cjs → ecosystem.config.cjs"
  exit 1
fi

if [[ -f "$APP_ROOT/../package.json" ]] && [[ ! -f "$APP_ROOT/package.json" ]]; then
  echo "==> npm install (root repo)"
  npm install --omit=dev --prefix "$APP_ROOT/.."
elif [[ -f "$APP_ROOT/package.json" ]]; then
  echo "==> npm install"
  npm install --omit=dev
fi

export NODE_ENV=production
echo "==> Preflight"
node "$APP_ROOT/scripts/preflight.js" --ping-db

echo "==> SQL migrations"
node "$APP_ROOT/scripts/migrate-sql.js"

echo "==> PM2"
pm2 startOrRestart "$APP_ROOT/ecosystem.config.cjs" --update-env
pm2 save

PORT="$(grep '^PORT=' "$APP_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d ' ' || true)"
PORT="${PORT:-3000}"
sleep 2
curl -sf "http://127.0.0.1:${PORT}/health/live" && echo ""
echo "==> Selesai"
