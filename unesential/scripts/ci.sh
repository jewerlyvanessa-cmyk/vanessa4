#!/usr/bin/env bash
# Jalankan dari root repo (contoh: bash unesential/scripts/ci.sh).
# Dipakai GitHub Actions — dependensi Node tetap di package.json root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "==> npm ci (root)"
npm ci

echo "==> npm test"
npm test

echo "==> ESLint (backend)"
npm run lint

echo "==> OpenAPI"
test -f unesential/docs/openapi.yaml

echo "==> node --check (backend JS)"
for f in \
  backend/server.js \
  backend/routes/workshop.js \
  backend/routes/workshop_core.js \
  backend/routes/workshop_orders.js \
  backend/routes/transfers.js \
  backend/routes/payments_core.js \
  backend/routes/orders_core.js \
  backend/routes/orders_pickup.js \
  backend/routes/orders_store_operational.js \
  backend/routes/orders_read.js \
  backend/routes/orders_create.js \
  backend/routes/items.js \
  backend/lib/audit_log.js \
  backend/lib/idempotency_helpers.js \
  backend/middleware/request_logger.js \
  backend/lib/orders_workshop_helpers.js \
  backend/lib/payments_schema_helpers.js \
  backend/lib/transfer_helpers.js \
  backend/app.js \
  backend/middleware/auth.js \
  backend/middleware/uploads_auth.js \
  backend/lib/query_limits.js \
  backend/lib/sql_migrations.js \
  backend/websocket/emit.js \
  backend/websocket/presence_registry.js \
  backend/websocket/attach.js \
  backend/storage/local.storage.js \
  backend/storage/storage.service.js
do
  node --check "$f"
done

if command -v flutter >/dev/null 2>&1; then
  echo "==> Flutter analyze (lib)"
  flutter analyze lib
else
  echo "==> SKIP flutter analyze (flutter not in PATH)"
fi

echo "==> backend CI selesai"
