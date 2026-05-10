#!/usr/bin/env bash
# Jalankan dari root repo (contoh: bash backend/scripts/ci.sh).
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
test -f backend/docs/openapi.yaml

echo "==> node --check (backend JS)"
for f in \
  backend/server.js \
  backend/routes/workshop.js \
  backend/routes/transfers.js \
  backend/routes/payments_core.js \
  backend/lib/orders_workshop_helpers.js \
  backend/lib/payments_schema_helpers.js \
  backend/lib/transfer_helpers.js \
  backend/app.js \
  backend/middleware/auth.js \
  backend/websocket/emit.js \
  backend/websocket/presence_registry.js \
  backend/websocket/attach.js \
  backend/storage/local.storage.js \
  backend/storage/storage.service.js
do
  node --check "$f"
done

echo "==> backend CI selesai"
