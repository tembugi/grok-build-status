#!/bin/zsh
# Build dist/GrokStatus.dmg (drag the app onto Applications).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="GrokStatus"
STAGE="$(mktemp -d /tmp/grok-status-dmg.XXXXXX)"
OUT="$PWD/dist/GrokStatus.dmg"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p dist
./scripts/bundle-app.sh release "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
cp "$PWD/Resources/dmg/DS_Store" "$STAGE/.DS_Store"

rm -f "$OUT"
hdiutil create -ov -volname "$APP_NAME" -fs HFS+ -srcfolder "$STAGE" \
  -format UDZO -imagekey zlib-level=9 "$OUT" >/dev/null
echo "Created $OUT"
echo "Double-click the disk image, then drag GrokStatus onto Applications."
