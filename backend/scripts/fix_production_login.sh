#!/usr/bin/env bash
# Pulihkan API produksi setelah deploy (502 / login Failed to fetch).
# Jalankan DI SERVER (SSH), setelah git pull:
#   cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp/backend
#   bash scripts/fix_production_login.sh
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"

cd "$BACKEND_DIR"
echo "==> Backend: $BACKEND_DIR"
echo "==> Root:    $ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: backend/.env tidak ada. Salin dari .env.example dan isi DB_* + JWT_SECRET."
  exit 1
fi

echo "==> npm install (root project, termasuk googleapis)"
cd "$ROOT_DIR"
if [[ ! -f package.json ]]; then
  echo "ERROR: package.json tidak ada di $ROOT_DIR"
  exit 1
fi
npm install --omit=dev

echo "==> Verifikasi modul API"
bash "$BACKEND_DIR/scripts/verify_api_start.sh"

cd "$BACKEND_DIR"
echo "==> DB: ${DB_HOST:-$(grep '^DB_HOST=' .env 2>/dev/null | cut -d= -f2-)} / ${DB_NAME:-$(grep '^DB_NAME=' .env 2>/dev/null | cut -d= -f2-)}"

# Opsional: reset password super / superadmin
if [[ "${RESET_SUPER_PASSWORDS:-1}" == "1" ]]; then
  for pair in "super:123456" "superadmin:123456"; do
    u="${pair%%:*}"
    p="${pair##*:}"
    echo "==> Reset password: $u"
    RESET_USERNAME="$u" RESET_PASSWORD="$p" node scripts/reset_user_password.js
  done
else
  echo "==> Lewati reset password (RESET_SUPER_PASSWORDS=0)"
fi

echo "==> Restart API (PM2, cwd=root project)"
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete vanessa 2>/dev/null || true
  pm2 start ecosystem.config.cjs
  pm2 save 2>/dev/null || true
  sleep 2
  pm2 logs vanessa --lines 20 --nostream || true
else
  echo "PM2 tidak ada — jalankan manual: cd $ROOT_DIR && node backend/server.js"
  exit 1
fi

PORT="$(grep '^PORT=' "$BACKEND_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d ' ')"
PORT="${PORT:-3000}"
echo "==> Health check lokal"
curl -sf "http://127.0.0.1:${PORT}/health/live" && echo "" || {
  echo "ERROR: /health/live gagal — cek: pm2 logs vanessa"
  exit 1
}

echo ""
echo "==> Selesai. Tes dari luar:"
echo "  curl -s https://mobile.vanessa.id/health/live"
echo "  curl -s -X POST https://mobile.vanessa.id/login -H 'Content-Type: application/json' -d '{\"username\":\"super\",\"password\":\"123456\"}'"
