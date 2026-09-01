#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c debug --arch arm64
BIN="$(swift build -c debug --arch arm64 --show-bin-path)/GrokStatus"
APP=".build/GrokStatus.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/GrokStatus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

pkill -x GrokStatus 2>/dev/null || true
open "$APP"
