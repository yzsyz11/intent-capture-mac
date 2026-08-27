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
cp "$ROOT"/Assets/icon/*.png "$RESOURCES/"

SOURCES=(
  "$ROOT/Sources/AppSettings.swift"
  "$ROOT/Sources/Design.swift"
  "$ROOT/Sources/Components.swift"
  "$ROOT/Sources/CaptureAction.swift"
  "$ROOT/Sources/HotkeyRecorder.swift"
  "$ROOT/Sources/GlobalHotkey.swift"
  "$ROOT/Sources/MouseEventMonitor.swift"
  "$ROOT/Sources/ClipboardHistoryStore.swift"
  "$ROOT/Sources/ClipboardDockSelectionState.swift"
  "$ROOT/Sources/ClipboardDockFeedbackWindow.swift"
  "$ROOT/Sources/SuccessAnimationView.swift"
  "$ROOT/Sources/ClipboardDockEditorPanel.swift"
  "$ROOT/Sources/CaptureService.swift"
  "$ROOT/Sources/Translator.swift"
  "$ROOT/Sources/AppleTranslator.swift"
  "$ROOT/Sources/TranslationOverlayWindow.swift"
  "$ROOT/Sources/RegionSelectionWindow.swift"
  "$ROOT/Sources/RadialMenuWindow.swift"
  "$ROOT/Sources/HomeWindow.swift"
  "$ROOT/Sources/ClipboardDockWindow.swift"
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

# 签名身份优先级：显式 CODESIGN_IDENTITY > 稳定本机自签身份 > ad-hoc 回退。
# 稳定身份让 TCC（辅助功能 / 屏幕录制）授权跨版本保留，免去每装新版移除重加。
STABLE_IDENTITY="IntentCapture Local Signing"
STABLE_KEYCHAIN="$HOME/Library/Keychains/intentcapture-signing.keychain-db"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "$STABLE_IDENTITY"; then
    SIGN_IDENTITY="$STABLE_IDENTITY"
    # 构建前解锁专用 keychain，避免 codesign 拿不到私钥
    [[ -f "$STABLE_KEYCHAIN" ]] && security unlock-keychain -p "intentcapture-local" "$STABLE_KEYCHAIN" >/dev/null 2>&1 || true
  else
    SIGN_IDENTITY="-"
    echo "未找到稳定签名身份，回退 ad-hoc。建议先运行 scripts/create-signing-identity.sh 根治权限失效。" >&2
  fi
fi
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
