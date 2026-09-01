#!/bin/zsh
# Optional scripted removal. Dragging the app to the Trash also clears
# Start on login while the extra is running, or on the next launch.
set -euo pipefail

DEST="/Applications/Grok Status.app"
if [[ -x "$DEST/Contents/MacOS/GrokStatus" ]]; then
  "$DEST/Contents/MacOS/GrokStatus" --uninstall 2>/dev/null || true
fi
pkill -x GrokStatus 2>/dev/null || true
rm -rf "$DEST"
echo "Removed $DEST"
