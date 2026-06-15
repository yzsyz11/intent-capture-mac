#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v swiftc >/dev/null 2>&1 || {
  echo "swiftc not found. Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
}

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

test -f "$ROOT/Info.plist" || {
  echo "Missing Info.plist" >&2
  exit 1
}

test -f "$ROOT/IntentCapture.entitlements" || {
  echo "Missing IntentCapture.entitlements" >&2
  exit 1
}

test -f "$ROOT/Assets/IntentCaptureAppIcon.icns" || {
  echo "Missing app icon: $ROOT/Assets/IntentCaptureAppIcon.icns" >&2
  exit 1
}

for source in "${SOURCES[@]}"; do
  test -f "$source" || {
    echo "Missing source: $source" >&2
    exit 1
  }
done

swiftc \
  -target arm64-apple-macos13.0 \
  -typecheck \
  -framework AppKit \
  -framework Carbon \
  -framework Vision \
  -framework CoreGraphics \
  -framework ApplicationServices \
  "${SOURCES[@]}"

echo "macOS Swift typecheck passed."
