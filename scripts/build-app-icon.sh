#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/grok-status-icon.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

swiftc -parse-as-library -O \
  -o "$TMP/render" \
  "$ROOT/Sources/GrokStatusCore/GrokMark.swift" \
  "$ROOT/scripts/RenderAppIcon.swift" \
  -framework AppKit

"$TMP/render" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
