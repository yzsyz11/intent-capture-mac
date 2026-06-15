#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$ROOT/release/IntentCapture-mac-arm64.dmg"

command -v xcrun >/dev/null 2>&1 || {
  echo "xcrun not found. Install Xcode first." >&2
  exit 1
}

test -f "$DMG" || {
  echo "Missing DMG: $DMG" >&2
  echo "Run scripts/package-macos.sh first." >&2
  exit 1
}

: "${APPLE_ID:?Set APPLE_ID to your Apple Developer account email.}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer Team ID.}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD to an app-specific password.}"

xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "Notarized and stapled: $DMG"
