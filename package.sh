#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Grok Status"
STAGE="$(mktemp -d /tmp/grok-status-dmg.XXXXXX)"
RW="/tmp/GrokStatus-rw.dmg"
OUT="$PWD/dist/${APP_NAME}.dmg"
VOLUME="$APP_NAME"

cleanup() {
  hdiutil detach "$VOLUME_PATH" >/dev/null 2>&1 || true
  rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

mkdir -p dist
./scripts/bundle-app.sh release "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$RW" "$OUT"
hdiutil create -ov -volname "$VOLUME" -fs HFS+ -srcfolder "$STAGE" -format UDRW "$RW" >/dev/null
ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
VOLUME_PATH="$(echo "$ATTACH" | awk '/\/Volumes\//{print $3; exit}')"
# Paths with spaces: take everything after the device column.
VOLUME_PATH="$(echo "$ATTACH" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | tail -1)"

osascript <<APPLESCRIPT || true
with timeout of 8 seconds
  tell application "Finder"
    tell disk "$VOLUME"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {280, 140, 820, 520}
      set theView to icon view options of container window
      set arrangement of theView to not arranged
      set icon size of theView to 128
      set position of item "${APP_NAME}.app" of container window to {140, 180}
      set position of item "Applications" of container window to {400, 180}
      update without registering applications
    end tell
  end tell
end timeout
APPLESCRIPT

sync
hdiutil detach "$VOLUME_PATH" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT" >/dev/null
echo "Created $OUT"
echo "Double-click the disk image, then drag Grok Status onto Applications."
echo "Then extra → Start on login if you want it at boot."
