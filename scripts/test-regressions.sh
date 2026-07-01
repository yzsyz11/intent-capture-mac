#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CAPTURE_SERVICE="$ROOT/Sources/CaptureService.swift"
REGION_WINDOW="$ROOT/Sources/RegionSelectionWindow.swift"
HOTKEY_RECORDER="$ROOT/Sources/HotkeyRecorder.swift"
GLOBAL_HOTKEY="$ROOT/Sources/GlobalHotkey.swift"
CLIPBOARD_STORE="$ROOT/Sources/ClipboardHistoryStore.swift"
CLIPBOARD_DOCK="$ROOT/Sources/ClipboardDockWindow.swift"

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"

  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"

  if grep -Eq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require_pattern "guard activeSelectionWindow == nil else \\{ return \\}" "$CAPTURE_SERVICE" \
  "capture actions must ignore duplicate triggers while a selection window is active"

require_pattern "RegionSelectionWindow\\(screen:" "$CAPTURE_SERVICE" \
  "region selection must create screen-scoped overlay windows so fullscreen Spaces receive mouse events"

require_pattern "collectionBehavior = \\[[^]]*fullScreenAuxiliary" "$REGION_WINDOW" \
  "region selection windows must remain fullscreen auxiliary windows"

reject_pattern "NSScreen\\.screens\\.reduce\\(CGRect\\.null\\)" "$REGION_WINDOW" \
  "region selection window must not use one union-frame window across all screens"

require_pattern "defaultClipboardDock = HotkeyDefinition\\(keyCode: UInt32\\(kVK_ANSI_D\\), modifiers: commandModifier, rawValue: \"command\\+d\"\\)" "$HOTKEY_RECORDER" \
  "clipboard dock hotkey must default to Command-D"

require_pattern "clipboardRef: EventHotKeyRef\\?" "$GLOBAL_HOTKEY" \
  "global hotkey manager must register a third hotkey for the clipboard dock"

require_pattern "maxItems = 50" "$CLIPBOARD_STORE" \
  "clipboard history must be capped at 50 items"

require_pattern "NSPasteboard\\.general\\.changeCount" "$CLIPBOARD_STORE" \
  "clipboard history store must track pasteboard changeCount"

require_pattern "NSScrollView" "$CLIPBOARD_DOCK" \
  "clipboard dock must use a horizontal scroll view"

require_pattern "nonactivatingPanel" "$CLIPBOARD_DOCK" \
  "clipboard dock must be a non-activating panel"

require_pattern "Dock 上方" "$CLIPBOARD_DOCK" \
  "clipboard dock positioning should explicitly target the area above the Dock"

require_pattern "override var canBecomeKey: Bool \\{ true \\}" "$CLIPBOARD_DOCK" \
  "clipboard dock must be able to become key so Escape can close it"

require_pattern "event\\.keyCode == UInt16\\(kVK_Escape\\)" "$CLIPBOARD_DOCK" \
  "clipboard dock must close on Escape"

require_pattern "addGlobalMonitorForEvents\\(matching: \\[\\.leftMouseDown, \\.rightMouseDown, \\.otherMouseDown\\]" "$CLIPBOARD_DOCK" \
  "clipboard dock must monitor outside mouse clicks"

require_pattern "removeMonitor" "$CLIPBOARD_DOCK" \
  "clipboard dock must remove event monitors when hidden"

require_pattern "NSEvent\\.addLocalMonitorForEvents\\(matching: \\.keyDown" "$GLOBAL_HOTKEY" \
  "Command-D must have a local keyboard fallback when the app is active"

reject_pattern "windowBackgroundColor\\.withAlphaComponent\\(0\\.42\\)" "$CLIPBOARD_DOCK" \
  "clipboard dock cards must not use opaque system window backgrounds over the glass shelf"

reject_pattern "material = \\.hudWindow" "$CLIPBOARD_DOCK" \
  "clipboard dock must not use the grey hudWindow material"

require_pattern "material = \\.underWindowBackground" "$CLIPBOARD_DOCK" \
  "clipboard dock should use a light translucent background-sampling material"

require_pattern "ClipboardPreviewButton" "$CLIPBOARD_DOCK" \
  "clipboard cards must expose a visible preview button"

require_pattern "复制成功，已放回系统剪贴板" "$CLIPBOARD_DOCK" \
  "copy success feedback must be explicit"

require_pattern "func performCopyAndClose\\(\\)" "$CLIPBOARD_DOCK" \
  "a single click on a card must copy the item and dismiss the dock"

require_pattern "hideDock\\(\\)" "$CLIPBOARD_DOCK" \
  "the copy-on-click path must be able to dismiss the dock"

require_pattern "func beginEditingIfPossible\\(\\)" "$CLIPBOARD_DOCK" \
  "a double click on a card must enter inline edit mode"

require_pattern "func commitEdit\\(_ sender: NSTextField\\?\\)" "$CLIPBOARD_DOCK" \
  "editing a card must auto-save on commit"

require_pattern "store\\.update\\(item, newText: text\\)" "$CLIPBOARD_DOCK" \
  "editing a card must persist the change back into the history store"

require_pattern "func update\\(_ item: ClipboardHistoryItem, newText: String\\)" "$CLIPBOARD_STORE" \
  "clipboard history store must support editing an item's text"

require_pattern "menu\\(for event:" "$CLIPBOARD_DOCK" \
  "clipboard cards must provide a right-click context menu"

require_pattern "删除这条历史" "$CLIPBOARD_DOCK" \
  "clipboard cards must support deleting one item from the right-click menu"

require_pattern "func delete\\(_ item: ClipboardHistoryItem\\)" "$CLIPBOARD_STORE" \
  "clipboard history store must support deleting one item"

require_pattern "height: CGFloat = 182" "$CLIPBOARD_DOCK" \
  "clipboard dock should stay close to the compact shelf height from the UI reference"

require_pattern "DockSymbolButton\\(symbolName: \"magnifyingglass\"" "$CLIPBOARD_DOCK" \
  "clipboard dock should use right-aligned icon controls like the UI reference"

require_pattern "final class ScrollIndicatorView: NSView" "$CLIPBOARD_DOCK" \
  "clipboard dock should draw a bottom horizontal scroll indicator"

require_pattern "scrollView\\.hasHorizontalScroller = false" "$CLIPBOARD_DOCK" \
  "clipboard dock must hide the thick native horizontal scroller"

require_pattern "HorizontalWheelScrollView" "$CLIPBOARD_DOCK" \
  "clipboard dock must convert ordinary mouse wheel events into horizontal scrolling"

require_pattern "scrollHorizontally\\(by" "$CLIPBOARD_DOCK" \
  "clipboard dock horizontal scrolling must be testable as a core method"

require_pattern "height: 4" "$CLIPBOARD_DOCK" \
  "clipboard dock scroll indicator must be thick enough to read at a glance"

require_pattern "CATransaction\\.setDisableActions\\(true\\)" "$CLIPBOARD_DOCK" \
  "scroll indicator layer moves must not use implicit animation, or the thumb visibly lags behind the scroll"

require_pattern "self\\?\\.indicatorView\\.refresh\\(\\)" "$CLIPBOARD_DOCK" \
  "the per-frame scroll callback must only refresh the small indicator layer, not the whole dock panel"

require_pattern "let signedDelta = -rawDelta" "$CLIPBOARD_DOCK" \
  "clipboard dock horizontal scroll direction must follow the scroll gesture, not invert it"

require_pattern "startMomentumIfNeeded" "$CLIPBOARD_DOCK" \
  "clipboard dock horizontal scroll must glide with momentum instead of snapping per wheel notch"

require_pattern "func aspectFillRect\\(in target: CGRect, pixelSize: CGSize\\? = nil\\)" "$CLIPBOARD_DOCK" \
  "clipboard image previews must fill using true pixel dimensions, not NSImage.size"

require_pattern "let cardWidth: CGFloat = 180" "$CLIPBOARD_DOCK" \
  "clipboard cards should match the narrower carousel-card proportions from the UI reference"

require_pattern "drawContentBand" "$CLIPBOARD_DOCK" \
  "clipboard dock should visually separate the content carousel from the glass shelf background"

require_pattern "aspectFillRect" "$CLIPBOARD_DOCK" \
  "clipboard image previews must crop-to-fill instead of leaving letterbox padding"

require_pattern "relativeTimeText" "$CLIPBOARD_DOCK" \
  "clipboard cards must show copy time"

require_pattern "categoryTitle" "$CLIPBOARD_DOCK" \
  "clipboard cards must show content category"

reject_pattern "DockTextButton\\(title: \"清空\"" "$CLIPBOARD_DOCK" \
  "clipboard dock should not use a prominent text clear button in the top-right icon group"

echo "regression checks passed."
