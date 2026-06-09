#!/usr/bin/env bash
# Restart backend production (jalankan di server setelah git pull / deploy).
# Mendukung layout repo (backend/) dan flat (isi backend → nodeapp/).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Flat: isi nodeapp/ langsung (tanpa subfolder backend) — override dari caller
if [[ -f "$(pwd)/ecosystem.config.cjs" && -f "$(pwd)/scripts/preflight.js" && ! -f "$(pwd)/backend/ecosystem.config.cjs" ]]; then
  DEPLOY_LAYOUT=flat
  DEPLOY_APP_ROOT="$(pwd)"
  DEPLOY_ECOSYSTEM="$(pwd)/ecosystem.config.cjs"
  DEPLOY_PREFLIGHT="node $(pwd)/scripts/preflight.js"
  DEPLOY_MIGRATE="node $(pwd)/scripts/migrate-sql.js"
elif [[ -f "$ROOT/backend/ecosystem.config.cjs" ]]; then
  DEPLOY_LAYOUT=repo
  DEPLOY_APP_ROOT="$ROOT/backend"
  DEPLOY_ECOSYSTEM="$ROOT/backend/ecosystem.config.cjs"
  DEPLOY_PREFLIGHT="node $ROOT/backend/scripts/preflight.js"
  DEPLOY_MIGRATE="node $ROOT/backend/scripts/migrate-sql.js"
else
  echo "ERROR: ecosystem.config.cjs tidak ditemukan."
  echo "  Flat:  cd .../nodeapp && pastikan ecosystem.config.cjs + scripts/preflight.js"
  echo "  Repo:  .../nodeapp/backend/ecosystem.config.cjs"
  exit 1
fi

echo "==> Layout deploy: $DEPLOY_LAYOUT"
echo "==> npm install (production deps)"
if [[ -f "$ROOT/package.json" ]]; then
  npm install --omit=dev
elif [[ -f "$(pwd)/package.json" ]]; then
  npm install --omit=dev
else
  echo "WARN: package.json tidak ada — lewati npm install"
fi

echo "==> Preflight env + modul + DB"
export NODE_ENV=production
$DEPLOY_PREFLIGHT --ping-db

echo "==> SQL migrations (idempotent)"
$DEPLOY_MIGRATE

echo "==> PM2 restart"
if command -v pm2 >/dev/null 2>&1; then
  pm2 startOrRestart "$DEPLOY_ECOSYSTEM" --update-env
  pm2 save
else
  echo "pm2 tidak ada — start manual: NODE_ENV=production $DEPLOY_START"
  exit 1
fi

sleep 2
PORT="$(grep '^PORT=' "$DEPLOY_APP_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d ' ' || true)"
PORT="${PORT:-3000}"
echo "==> Health check lokal (port $PORT)"
curl -sf "http://127.0.0.1:${PORT}/health/live" | head -c 200
echo ""
echo "==> Backend restart selesai. Cek: curl -sf https://mobile.vanessa.id/health/live"
