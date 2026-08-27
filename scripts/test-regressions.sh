#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

INFO_PLIST="$ROOT/Info.plist"
MAIN_SWIFT="$ROOT/Sources/main.swift"
CAPTURE_SERVICE="$ROOT/Sources/CaptureService.swift"
REGION_WINDOW="$ROOT/Sources/RegionSelectionWindow.swift"
HOTKEY_RECORDER="$ROOT/Sources/HotkeyRecorder.swift"
GLOBAL_HOTKEY="$ROOT/Sources/GlobalHotkey.swift"
CLIPBOARD_STORE="$ROOT/Sources/ClipboardHistoryStore.swift"
CLIPBOARD_DOCK="$ROOT/Sources/ClipboardDockWindow.swift"
CLIPBOARD_EDITOR="$ROOT/Sources/ClipboardDockEditorPanel.swift"
APP_DELEGATE="$ROOT/Sources/AppDelegate.swift"
MOUSE_MONITOR="$ROOT/Sources/MouseEventMonitor.swift"

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

require_pattern "guard activeSelectionWindow == nil else \\{" "$CAPTURE_SERVICE" \
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

require_pattern "func flush\\(\\)" "$CLIPBOARD_STORE" \
  "clipboard history store must expose a synchronous flush so debounced writes are not lost"

require_pattern "clipboardStore\\.flush\\(\\)" "$APP_DELEGATE" \
  "app termination must flush pending clipboard writes so the last change survives quit"

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

require_pattern "<key>LSUIElement</key>" "$INFO_PLIST" \
  "Intent Capture must be a menu bar utility that stays out of the Dock"

require_pattern "app\\.setActivationPolicy\\(\\.accessory\\)" "$MAIN_SWIFT" \
  "Intent Capture must launch without adding a Dock icon"

reject_pattern "setActivationPolicy\\(\\.regular\\)" "$APP_DELEGATE" \
  "middle-click, hotkey, and status-bar actions must not add the app back to the Dock"

require_pattern "let firstLaunch = !settings\\.hasLaunchedBefore" "$APP_DELEGATE" \
  "launch must gate any auto-shown window on first run (or a new build with missing permissions), then stay silent in the menu bar"

require_pattern "addGlobalMonitorForEvents\\(matching: mask\\)" "$MOUSE_MONITOR" \
  "middle-click listening must have an NSEvent global fallback when the CGEvent tap is unreliable"

require_pattern "addLocalMonitorForEvents\\(matching: mask\\)" "$MOUSE_MONITOR" \
  "middle-click listening must also work while Intent Capture is active"

require_pattern "let wasDown = self\\.isMiddleDown" "$MOUSE_MONITOR" \
  "middle-click CGEvent and NSEvent paths must deduplicate the same mouse-up event"

reject_pattern "windowBackgroundColor\\.withAlphaComponent\\(0\\.42\\)" "$CLIPBOARD_DOCK" \
  "clipboard dock cards must not use opaque system window backgrounds over the glass shelf"

reject_pattern "material = \\.hudWindow" "$CLIPBOARD_DOCK" \
  "clipboard dock must not use the grey hudWindow material"

require_pattern "material = \\.underWindowBackground" "$CLIPBOARD_DOCK" \
  "clipboard dock should use a light translucent background-sampling material"

require_pattern "ClipboardPreviewButton" "$CLIPBOARD_DOCK" \
  "clipboard cards must expose a visible preview button"

require_pattern "SuccessAnimationView" "$CLIPBOARD_DOCK" \
  "clipboard copy must play the on-card spinner→checkmark success animation"

require_pattern "func updateTilt\\(" "$CLIPBOARD_DOCK" \
  "cards must tilt in 3D toward the cursor on hover for a floating feel"

require_pattern "CATransform3DMakeScale" "$CLIPBOARD_DOCK" \
  "dock icon buttons must give a hover scale/press response"

require_pattern "func performSwipeDelete\\(\\)" "$CLIPBOARD_DOCK" \
  "dragging a card up past the threshold must delete it"

require_pattern "CASpringAnimation" "$CLIPBOARD_DOCK" \
  "a drag released within range must spring the card back"

require_pattern "func performCopyAndClose\\(\\)" "$CLIPBOARD_DOCK" \
  "a single click on a card must copy the item and dismiss the dock"

require_pattern "setAccessibilityRole\\(\.button\\)" "$CLIPBOARD_DOCK" \
  "clipboard card bodies must be exposed as actionable accessibility buttons"

require_pattern "accessibilityPerformPress" "$CLIPBOARD_DOCK" \
  "an accessibility press must use the same copy or selection path as a mouse click"

reject_pattern "NSEvent\\.doubleClickInterval" "$CLIPBOARD_DOCK" \
  "card copying must not wait for the system double-click interval"

reject_pattern "pendingSingleClick|DispatchWorkItem" "$CLIPBOARD_DOCK" \
  "card copying must not be deferred through a pending work item"

require_pattern "ClipboardDockFeedback\\.show" "$CLIPBOARD_DOCK" \
  "clipboard actions must use feedback positioned near the dock"

require_pattern "hideDock\\(\\)" "$CLIPBOARD_DOCK" \
  "the copy-on-click path must be able to dismiss the dock"

reject_pattern "editField|beginEditingIfPossible|commitEdit" "$CLIPBOARD_DOCK" \
  "clipboard editing must not use a card-sized inline text field"

require_pattern "编辑内容" "$CLIPBOARD_DOCK" \
  "clipboard cards must expose an explicit full-content edit action"

require_pattern "NSTextView" "$CLIPBOARD_EDITOR" \
  "clipboard editing must use a multi-line text view"

require_pattern "NSScrollView" "$CLIPBOARD_EDITOR" \
  "long clipboard text must remain scrollable while editing"

require_pattern "saveEditing|cancelEditing" "$CLIPBOARD_EDITOR" \
  "the full editor must provide explicit save and cancel actions"

require_pattern "modifierFlags.*command" "$CLIPBOARD_EDITOR" \
  "Command-Return must save clipboard edits"

require_pattern "DispatchQueue\.main\.async" "$CLIPBOARD_EDITOR" \
  "closing the editor must wait until the key event ends so Escape does not also close the dock"

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

require_pattern "let isPinned: Bool" "$CLIPBOARD_STORE" \
  "clipboard history items must persist whether a card is pinned"

require_pattern "let pinnedAt: Date\\?" "$CLIPBOARD_STORE" \
  "clipboard history items must persist pin order metadata"

require_pattern "func togglePinned\\(_ item: ClipboardHistoryItem\\)" "$CLIPBOARD_STORE" \
  "clipboard history store must support toggling a single pinned item"

require_pattern 'items\.removeAll \{ !\$0\.isPinned \}' "$CLIPBOARD_STORE" \
  "the store-level clear operation must preserve pinned items"

require_pattern "enterDeletionMode" "$CLIPBOARD_DOCK" \
  "the dock trash button must enter selection mode instead of clearing immediately"

require_pattern "confirmDeletion" "$CLIPBOARD_DOCK" \
  "selected clipboard cards must require an explicit delete confirmation"

require_pattern "store\.delete\(ids:" "$CLIPBOARD_DOCK" \
  "delete confirmation must use one batch store mutation"

require_pattern "sortedPinnedFirst" "$CLIPBOARD_STORE" \
  "clipboard history must keep pinned items before normal history"

require_pattern "trimNormalItemsToCapacity" "$CLIPBOARD_STORE" \
  "clipboard history capacity trimming must not evict pinned items"

require_pattern "pinButton\\.target = self" "$CLIPBOARD_DOCK" \
  "each clipboard card must expose its own pin toggle button"

require_pattern "store\\.togglePinned\\(item\\)" "$CLIPBOARD_DOCK" \
  "the card pin button must toggle the selected clipboard item"

require_pattern "item\\.isPinned \\? \"pin\\.fill\" : \"pin\"" "$CLIPBOARD_DOCK" \
  "pinned cards must use a filled pin glyph"

require_pattern "height: CGFloat = 182" "$CLIPBOARD_DOCK" \
  "clipboard dock should stay close to the compact shelf height from the UI reference"

require_pattern "DockSymbolButton\\(symbolName: \"magnifyingglass\"" "$CLIPBOARD_DOCK" \
  "clipboard dock should use right-aligned icon controls like the UI reference"

require_pattern "private func filteredItems\\(\\)" "$CLIPBOARD_DOCK" \
  "clipboard dock must filter history by search query and kind before rendering cards"

require_pattern "NSSegmentedControl\\(" "$CLIPBOARD_DOCK" \
  "clipboard dock must expose a content-kind filter control"

require_pattern "func handleKeyNavigation\\(" "$CLIPBOARD_DOCK" \
  "clipboard dock must support keyboard navigation (arrows / Enter / number keys)"

require_pattern "func activateFromKeyboard\\(\\)" "$CLIPBOARD_DOCK" \
  "keyboard activation must reuse the same copy-and-close path as a mouse click"

require_pattern "settingsButton\\.action = #selector\\(openSettings\\)" "$CLIPBOARD_DOCK" \
  "clipboard dock settings button must be wired to open the app home"

require_pattern "dock\\.onOpenSettings =" "$APP_DELEGATE" \
  "app delegate must connect the dock settings button to opening the home window"

require_pattern "static var dockAccent" "$CLIPBOARD_DOCK" \
  "clipboard dock theme colours must derive from a single accent source"

reject_pattern "NSColor\\.systemBlue\\.withAlphaComponent\\(0\\.30\\)" "$CLIPBOARD_DOCK" \
  "card hover must follow the theme accent, not a hard-coded system blue"

require_pattern "beginScrollSuppression\\(\\)" "$CLIPBOARD_DOCK" \
  "scrolling must suppress card hover so cards sliding under the cursor don't flicker"

require_pattern "endScrollSuppression" "$CLIPBOARD_DOCK" \
  "hover must be re-evaluated for the card under the cursor once scrolling stops"

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

require_pattern "indicatorView\\.refresh\\(\\)" "$CLIPBOARD_DOCK" \
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

TEST_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
xcrun swiftc \
  "$CLIPBOARD_STORE" \
  "$ROOT/Tests/ToastStub.swift" \
  "$ROOT/Tests/ClipboardCardPreviewTests.swift" \
  -o "$TEST_BUILD_DIR/ClipboardCardPreviewTests"
"$TEST_BUILD_DIR/ClipboardCardPreviewTests"

xcrun swiftc \
  "$CLIPBOARD_STORE" \
  "$ROOT/Sources/ClipboardDockSelectionState.swift" \
  "$ROOT/Tests/ToastStub.swift" \
  "$ROOT/Tests/ClipboardDockSelectionTests.swift" \
  -o "$TEST_BUILD_DIR/ClipboardDockSelectionTests"
"$TEST_BUILD_DIR/ClipboardDockSelectionTests"

echo "regression checks passed."
