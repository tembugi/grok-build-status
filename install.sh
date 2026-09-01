#!/bin/zsh
# Developer shortcut: copy the app straight into Applications.
# For the usual Mac install, run ./package.sh and drag from the disk image.
set -euo pipefail
cd "$(dirname "$0")"

DEST="/Applications/Grok Status.app"
pkill -x GrokStatus 2>/dev/null || true
./scripts/bundle-app.sh release "$DEST"
open "$DEST"
echo "Installed to $DEST"
echo "Extra → Start on login to open at boot."
