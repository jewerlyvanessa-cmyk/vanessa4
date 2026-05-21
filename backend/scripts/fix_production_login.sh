#!/usr/bin/env bash
# Jalankan DI SERVER produksi (SSH), dari folder backend setelah git pull:
#   cd /path/to/vanessa3/backend
#   bash scripts/fix_production_login.sh
set -euo pipefail

cd "$(dirname "$0")/.."
echo "==> DB: ${DB_HOST:-$(grep '^DB_HOST=' .env 2>/dev/null | cut -d= -f2-)} / ${DB_NAME:-$(grep '^DB_NAME=' .env 2>/dev/null | cut -d= -f2-)}"

if [[ ! -f .env ]]; then
  echo "ERROR: backend/.env tidak ada. Salin dari .env.example dan isi DB_* + JWT_SECRET."
  exit 1
fi

# Reset akun utama (ganti password jika perlu)
for pair in "super:123456" "superadmin:123456"; do
  u="${pair%%:*}"
  p="${pair##*:}"
  echo "==> Reset password: $u"
  RESET_USERNAME="$u" RESET_PASSWORD="$p" node scripts/reset_user_password.js
done

echo "==> Restart API (PM2)"
if command -v pm2 >/dev/null 2>&1; then
  pm2 restart vanessa --update-env || pm2 start ecosystem.config.cjs
  pm2 save 2>/dev/null || true
else
  echo "PM2 tidak ada — restart node server.js manual."
fi

sleep 2
echo "==> Health check"
curl -sf "http://127.0.0.1:${PORT:-3000}/health/live" && echo "" || echo "WARN: /health/live gagal di localhost"

echo "==> Selesai. Tes dari luar:"
echo "  curl -s https://mobile.vanessa.id/health/live"
echo "  curl -s -X POST https://mobile.vanessa.id/login -H 'Content-Type: application/json' -d '{\"username\":\"super\",\"password\":\"123456\"}'"
