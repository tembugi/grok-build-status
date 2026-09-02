#!/bin/zsh
# Build dist/Grok Status.dmg for a normal Mac install (drag onto Applications).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Grok Status"
STAGE="$(mktemp -d /tmp/grok-status-dmg.XXXXXX)"
RW="/tmp/GrokStatus-rw.dmg"
OUT="$PWD/dist/${APP_NAME}.dmg"
VOLUME="$APP_NAME"
VOLUME_PATH=""

cleanup() {
  if [[ -n "$VOLUME_PATH" ]]; then
    hdiutil detach "$VOLUME_PATH" >/dev/null 2>&1 || true
  fi
  hdiutil detach "/Volumes/${VOLUME}" >/dev/null 2>&1 || true
  rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

mkdir -p dist
hdiutil detach "/Volumes/${VOLUME}" >/dev/null 2>&1 || true

./scripts/bundle-app.sh release "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$RW" "$OUT"
hdiutil create -ov -volname "$VOLUME" -fs HFS+ -srcfolder "$STAGE" -format UDRW "$RW" >/dev/null
ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
VOLUME_PATH="$(echo "$ATTACH" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | tail -1)"
if [[ -z "$VOLUME_PATH" || ! -d "$VOLUME_PATH" ]]; then
  echo "Failed to mount $RW" >&2
  exit 1
fi

# Finder must write .DS_Store while the volume is mounted, then the window
# has to close so that file is flushed. Otherwise the disk image opens as a
# plain folder listing instead of the drag-to-Applications layout.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set sidebar width of container window to 0
    end try
    set bounds of container window to {360, 160, 900, 520}
    set theView to icon view options of container window
    set arrangement of theView to not arranged
    set icon size of theView to 128
    set background color of theView to {58000, 58000, 58000}
    delay 0.4
    set position of item "${APP_NAME}.app" of container window to {150, 180}
    set position of item "Applications" of container window to {390, 180}
    delay 0.8
    close
    open
    delay 1.5
    close
  end tell
  delay 0.5
end tell
APPLESCRIPT

sync
sleep 1
hdiutil detach "$VOLUME_PATH" >/dev/null
VOLUME_PATH=""
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT" >/dev/null
echo "Created $OUT"
echo "Double-click the disk image, then drag Grok Status onto Applications."
echo "Open the menu extra and turn on Start on login if you want it at boot."
