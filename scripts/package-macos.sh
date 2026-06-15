#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Intent Capture"
BUNDLE_NAME="IntentCapture.app"
BUILD_DIR="$ROOT/build"
RELEASE_DIR="$ROOT/release"
APP_DIR="$BUILD_DIR/$BUNDLE_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$MACOS/IntentCapture"
DMG="$RELEASE_DIR/IntentCapture-mac-arm64.dmg"
ENTITLEMENTS="$ROOT/IntentCapture.entitlements"
APP_ICON="$ROOT/Assets/IntentCaptureAppIcon.icns"

command -v swiftc >/dev/null 2>&1 || {
  echo "swiftc not found. Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
}

command -v hdiutil >/dev/null 2>&1 || {
  echo "hdiutil not found. This script must run on macOS." >&2
  exit 1
}

mkdir -p "$MACOS" "$RESOURCES" "$RELEASE_DIR"
rm -rf "$APP_DIR" "$DMG"
mkdir -p "$MACOS" "$RESOURCES"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$APP_ICON" "$RESOURCES/IntentCaptureAppIcon.icns"

SOURCES=(
  "$ROOT/Sources/AppSettings.swift"
  "$ROOT/Sources/CaptureAction.swift"
  "$ROOT/Sources/HotkeyRecorder.swift"
  "$ROOT/Sources/GlobalHotkey.swift"
  "$ROOT/Sources/MouseEventMonitor.swift"
  "$ROOT/Sources/CaptureService.swift"
  "$ROOT/Sources/RegionSelectionWindow.swift"
  "$ROOT/Sources/ActionPanelWindow.swift"
  "$ROOT/Sources/SettingsWindow.swift"
  "$ROOT/Sources/AppDelegate.swift"
  "$ROOT/Sources/main.swift"
)

swiftc \
  -target arm64-apple-macos13.0 \
  -O \
  -framework AppKit \
  -framework Carbon \
  -framework Vision \
  -framework CoreGraphics \
  -framework ApplicationServices \
  -framework UniformTypeIdentifiers \
  -o "$EXECUTABLE" \
  "${SOURCES[@]}"

SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_DIR"

STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/$BUNDLE_NAME"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

echo "Created $DMG"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Signed with ad-hoc identity. For distribution without Gatekeeper prompts, rebuild with CODESIGN_IDENTITY='Developer ID Application: ...' and notarize the DMG."
fi
