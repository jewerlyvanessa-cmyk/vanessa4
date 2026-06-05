#!/usr/bin/env bash
# Jalankan Flutter web di Brave (Chromium) — pengganti `flutter run -d chrome`.
# Dari root repo: bash unesential/scripts/flutter_run_brave.sh [args flutter run...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BRAVE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
if [[ ! -x "$BRAVE" ]]; then
  echo "Brave tidak ditemukan: $BRAVE" >&2
  echo "Install Brave atau set CHROME_EXECUTABLE ke binary Chromium lain." >&2
  exit 1
fi

export CHROME_EXECUTABLE="$BRAVE"
exec flutter run -d chrome "$@"
