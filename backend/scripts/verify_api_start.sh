#!/usr/bin/env bash
# Cek modul backend bisa di-load (tanpa menjalankan server penuh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$BACKEND_DIR/.." && pwd)"

cd "$ROOT_DIR"

if [[ ! -d node_modules ]]; then
  echo "ERROR: node_modules tidak ada di $ROOT_DIR — jalankan: npm install"
  exit 1
fi

node -e "
const path = require('path');
require('dotenv').config({ path: path.join('$BACKEND_DIR', '.env') });
require(path.join('$BACKEND_DIR', 'routes', 'admin_api'));
require(path.join('$BACKEND_DIR', 'routes', 'login'));
require(path.join('$BACKEND_DIR', 'lib', 'google_drive_backup'));
console.log('OK: modul API (login + admin + backup) dapat di-load');
"

echo "Deploy aman untuk restart PM2."
