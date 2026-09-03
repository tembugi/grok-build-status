#!/bin/zsh
# Usage: bundle-app.sh <config> <dest.app>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
DEST="$2"

cd "$ROOT"
swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/GrokBuildStatus"

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/GrokBuildStatus"
chmod +x "$DEST/Contents/MacOS/GrokBuildStatus"
cp "$ROOT/Resources/Info.plist" "$DEST/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$DEST/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$DEST/Contents/PkgInfo"
if ! codesign --force --sign - "$DEST" >/dev/null 2>&1; then
  echo "warning: ad-hoc codesign failed; Gatekeeper will block the app" >&2
fi
