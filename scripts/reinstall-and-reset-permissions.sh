#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ID="local.intentcapture.mac"
INSTALLED_APP="/Applications/IntentCapture.app"

pkill -x IntentCapture >/dev/null 2>&1 || true

bash "$ROOT/scripts/package-macos.sh"

rm -rf "$INSTALLED_APP"
ditto "$ROOT/build/IntentCapture.app" "$INSTALLED_APP"

tccutil reset ScreenCapture "$APP_ID" >/dev/null 2>&1 || true
tccutil reset Accessibility "$APP_ID" >/dev/null 2>&1 || true

echo "Installed $INSTALLED_APP"
echo "Reset Screen Recording and Accessibility permissions for $APP_ID"
echo "Open Intent Capture, grant Screen Recording permission, then quit and reopen it once."
