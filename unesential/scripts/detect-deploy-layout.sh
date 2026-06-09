#!/usr/bin/env bash
# Deteksi layout deploy: repo (backend/) vs flat (nodeapp tanpa subfolder backend).
# Source file ini, lalu pakai variabel DEPLOY_*.
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")/../.." 2>/dev/null && pwd)" || DEPLOY_ROOT="$(pwd)"

# Jika dipanggil dari nodeapp flat, caller bisa: DEPLOY_ROOT=/path source detect-deploy-layout.sh
if [[ -n "${DEPLOY_ROOT_OVERRIDE:-}" ]]; then
  DEPLOY_ROOT="$DEPLOY_ROOT_OVERRIDE"
fi

if [[ -f "$DEPLOY_ROOT/backend/ecosystem.config.cjs" ]]; then
  DEPLOY_LAYOUT=repo
  DEPLOY_APP_ROOT="$DEPLOY_ROOT/backend"
  DEPLOY_ECOSYSTEM="$DEPLOY_ROOT/backend/ecosystem.config.cjs"
  DEPLOY_PREFLIGHT="node $DEPLOY_ROOT/backend/scripts/preflight.js"
  DEPLOY_MIGRATE="node $DEPLOY_ROOT/backend/scripts/migrate-sql.js"
  DEPLOY_START="node $DEPLOY_ROOT/backend/scripts/start.js"
elif [[ -f "$DEPLOY_ROOT/ecosystem.config.cjs" && -f "$DEPLOY_ROOT/scripts/preflight.js" ]]; then
  DEPLOY_LAYOUT=flat
  DEPLOY_APP_ROOT="$DEPLOY_ROOT"
  DEPLOY_ECOSYSTEM="$DEPLOY_ROOT/ecosystem.config.cjs"
  DEPLOY_PREFLIGHT="node $DEPLOY_ROOT/scripts/preflight.js"
  DEPLOY_MIGRATE="node $DEPLOY_ROOT/scripts/migrate-sql.js"
  DEPLOY_START="node $DEPLOY_ROOT/scripts/start.js"
else
  echo "ERROR: Tidak mengenali layout deploy di $DEPLOY_ROOT"
  echo "  Repo:  .../nodeapp/backend/ecosystem.config.cjs"
  echo "  Flat:  .../nodeapp/ecosystem.config.cjs + scripts/preflight.js"
  exit 1
fi

export DEPLOY_LAYOUT DEPLOY_ROOT DEPLOY_APP_ROOT DEPLOY_ECOSYSTEM
export DEPLOY_PREFLIGHT DEPLOY_MIGRATE DEPLOY_START
