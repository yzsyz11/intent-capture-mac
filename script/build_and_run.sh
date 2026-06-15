#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/IntentCapture.app"
INSTALLED_APP="/Applications/IntentCapture.app"
BINARY="$APP/Contents/MacOS/IntentCapture"
PROCESS="IntentCapture"
MODE="${1:-run}"
BUNDLE_ID="local.intentcapture.mac"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS." >&2
  exit 1
fi

pkill -x "$PROCESS" >/dev/null 2>&1 || true

bash "$ROOT/scripts/package-macos.sh"
rm -rf "$INSTALLED_APP"
ditto "$APP" "$INSTALLED_APP"

open_app() {
  /usr/bin/open -n "$INSTALLED_APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 5
    pgrep -x "$PROCESS" >/dev/null || {
      echo "Intent Capture did not start." >&2
      exit 1
    }
    echo "Intent Capture is running after startup checks."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
