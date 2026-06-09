#!/usr/bin/env bash
# Pre-release smoke: backend CI + Flutter analyze + deploy reminder.
# Jalankan dari root repo: bash unesential/scripts/release_smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "==> Backend CI"
bash unesential/scripts/ci.sh

if command -v flutter >/dev/null 2>&1; then
  echo "==> Flutter analyze (lib)"
  flutter analyze lib
else
  echo "==> SKIP flutter analyze (flutter not in PATH)"
fi

cat <<'EOF'

==> Release checklist (manual)
  1. npm run migrate:sql          # audit_log, idempotency, schema baru
  2. bash unesential/scripts/restart-backend-production.sh
     # atau: npm run preflight:backend && pm2 restart backend/ecosystem.config.cjs --update-env
  3. REQUEST_LOG=true             # optional structured logging
  4. Flutter APK release:
       flutter build apk --release \
         --dart-define=SENTRY_DSN=<dsn> \
         --dart-define=SENTRY_ENV=production
  5. Pastikan android/key.properties & signing config ada di mesin build
  6. Smoke login + 1 transaksi per role kritis (CS jual, kasir bayar, opname)

EOF

echo "==> release_smoke selesai"
