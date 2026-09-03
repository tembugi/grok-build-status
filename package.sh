#!/bin/zsh
# Build dist/GrokBuildStatus.dmg (drag the app onto Applications).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Grok Build Status"
STAGE="$(mktemp -d /tmp/grok-build-status-dmg.XXXXXX)"
RW="$(mktemp /tmp/grok-build-status-dmg.XXXXXX)"
mv "$RW" "$RW.dmg"
RW="$RW.dmg"
OUT="$PWD/dist/GrokBuildStatus.dmg"
VOLUME_PATH=""

cleanup() {
  if [[ -n "$VOLUME_PATH" ]]; then
    hdiutil detach "$VOLUME_PATH" >/dev/null 2>&1 || true
  fi
  hdiutil detach "/Volumes/${APP_NAME}" >/dev/null 2>&1 || true
  rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

mkdir -p dist
swift test
./scripts/bundle-app.sh release "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

hdiutil detach "/Volumes/${APP_NAME}" >/dev/null 2>&1 || true
hdiutil detach "/Volumes/${APP_NAME} 1" >/dev/null 2>&1 || true

rm -f "$OUT"
hdiutil create -ov -volname "$APP_NAME" -fs HFS+ -srcfolder "$STAGE" \
  -format UDRW "$RW" >/dev/null
ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
VOLUME_PATH="$(echo "$ATTACH" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | tail -1)"
if [[ -z "$VOLUME_PATH" || ! -d "$VOLUME_PATH" ]]; then
  echo "error: could not mount disk image" >&2
  exit 1
fi

# Finder must write .DS_Store while the volume is mounted, then the window
# has to close so that file is flushed. Otherwise the disk image opens as a
# plain folder listing instead of the drag-to-Applications layout.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$APP_NAME"
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
echo "Double-click the disk image, then drag ${APP_NAME} onto Applications."
