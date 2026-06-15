#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/IntentCapture.app"
DMG="$ROOT/release/IntentCapture-mac-arm64.dmg"

test -d "$APP" || {
  echo "Missing app bundle: $APP" >&2
  exit 1
}

test -x "$APP/Contents/MacOS/IntentCapture" || {
  echo "Missing executable: $APP/Contents/MacOS/IntentCapture" >&2
  exit 1
}

test -f "$APP/Contents/Info.plist" || {
  echo "Missing Info.plist in app bundle" >&2
  exit 1
}

test -f "$DMG" || {
  echo "Missing DMG: $DMG" >&2
  exit 1
}

/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" || true
hdiutil verify "$DMG"

echo "Package checks completed."
