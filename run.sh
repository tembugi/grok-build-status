#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP=".build/Grok Status.app"
./scripts/bundle-app.sh debug "$APP"
pkill -x GrokStatus 2>/dev/null || true
open "$APP"
