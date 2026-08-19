import AppKit
import Carbon

final class ClipboardDockWindow: NSPanel {
    private let store: ClipboardHistoryStore
    private let dockView: ClipboardDockView
    private var outsideMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var editorPanel: ClipboardDockEditorPanel?
    var onOpenSettings: (() -> Void)?

    init(store: ClipboardHistoryStore) {
        self.store = store
        self.dockView = ClipboardDockView(store: store)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(screen.width - 48, 1160)
        let size = CGSize(width: width, height: 182)
        let rect = CGRect(x: screen.midX - width / 2, y: screen.minY + 18, width: size.width, height: size.height)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        contentView = dockView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func toggle() {
        isVisible ? hideDock() : showDock()
    }

    func showDock() {
        positionAboveDock()
        dockView.resetKeyboardFocus()
        dockView.reload()
        makeKeyAndOrderFront(nil)
        startDismissMonitors()
    }

    func refresh() {
        dockView.reload()
    }

    func hideDock() {
        closeEditor()
        stopDismissMonitors()
        orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if dockView.handleEscape() { return }
            hideDock()
            return
        }
        if dockView.handleKeyNavigation(event) { return }
        super.keyDown(with: event)
    }

    private func positionAboveDock() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let width = min(visible.width - 48, 1160)
        let height: CGFloat = 182
        // Dock 上方：visibleFrame.minY 会避开底部 Dock 占用区域。
        let y = visible.minY + 18
        setFrame(CGRect(x: visible.midX - width / 2, y: y, width: width, height: height), display: true)
    }

    private func startDismissMonitors() {
        stopDismissMonitors()
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hideIfMouseIsOutsideDock()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.hideIfMouseIsOutsideDock()
            return event
        }
    }

    private func stopDismissMonitors() {
        if let outsideMouseMonitor { NSEvent.removeMonitor(outsideMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        outsideMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func hideIfMouseIsOutsideDock() {
        guard isVisible else { return }
        let point = NSEvent.mouseLocation
        let isInsideEditor = editorPanel?.frame.insetBy(dx: -2, dy: -2).contains(point) ?? false
        if !frame.insetBy(dx: -2, dy: -2).contains(point), !isInsideEditor {
            hideDock()
        }
    }

    fileprivate func showEditor(for item: ClipboardHistoryItem, anchor: CGPoint) {
        closeEditor()
        let panel = ClipboardDockEditorPanel(
            item: item,
            onSave: { [weak self] text in
                guard let self else { return }
                self.store.update(item, newText: text)
                let panelFrame = self.editorPanel?.frame ?? CGRect(x: anchor.x, y: self.frame.maxY, width: 0, height: 0)
                let feedbackPoint = CGPoint(x: panelFrame.midX, y: panelFrame.maxY)
                self.closeEditor()
                self.dockView.reload()
                ClipboardDockFeedback.show(message: "已保存 · \(item.kind.categoryTitle)", tone: .success, anchor: feedbackPoint)
            },
            onCancel: { [weak self] in self?.closeEditor() }
        )
        editorPanel = panel
        addChildWindow(panel, ordered: .above)
        panel.show(above: frame, centeredAt: anchor.x)
    }

    private func closeEditor() {
        guard let editorPanel else { return }
        removeChildWindow(editorPanel)
        editorPanel.close()
        self.editorPanel = nil
    }

    fileprivate func requestOpenSettings() {
        hideDock()
        onOpenSettings?()
    }
}

final class ClipboardDockView: NSView, NSSearchFieldDelegate {
    private let store: ClipboardHistoryStore
    private let effectView = NSVisualEffectView()
    private let scrollView = HorizontalWheelScrollView()
    private let stripView = ClipboardCardStripView()
    private let title = NSTextField(labelWithString: "剪贴板拓展坞")
    private let subtitle = NSTextField(labelWithString: ClipboardDockView.browseHint)
    private let emptyLabel = NSTextField(labelWithString: "复制文字、截图或色值后，会出现在这里")
    private let searchButton = DockSymbolButton(symbolName: "magnifyingglass", tooltip: "搜索")
    private let settingsButton = DockSymbolButton(symbolName: "gearshape", tooltip: "设置")
    private let closeButton = DockSymbolButton(symbolName: "xmark", tooltip: "关闭")
    private let clearButton = DockSymbolButton(symbolName: "trash", tooltip: "选择删除")
    private let indicatorView = ScrollIndicatorView(frame: .zero)
    private let selectAllButton = DockTextButton(title: "全选", target: nil, action: nil)
    private let cancelDeleteButton = DockTextButton(title: "取消", target: nil, action: nil)
    private let confirmDeleteButton = DockTextButton(title: "删除（0）", target: nil, action: nil)
    private let cancelSearchButton = DockTextButton(title: "取消", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl(
        labels: ["全部", "文字", "图片", "链接", "颜色"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private var selectionState = ClipboardDockSelectionState()
    private var isSearching = false
    private var searchQuery = ""
    private var activeKindFilter: ClipboardHistoryKind?
    private var displayedItems: [ClipboardHistoryItem] = []
    private var focusedIndex: Int?
    private static let browseHint = "⌘D 呼出 · ↑↓ 选择 · ↵ 复制 · 1-9 直选"
    private var dockWindow: ClipboardDockWindow? { window as? ClipboardDockWindow }

    init(store: ClipboardHistoryStore) {
        self.store = store
        super.init(frame: CGRect(x: 0, y: 0, width: 1160, height: 182))
        wantsLayer = true
        build()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let items = filteredItems()
        displayedItems = items
        if let idx = focusedIndex {
            focusedIndex = items.isEmpty ? nil : min(idx, items.count - 1)
        }
        stripView.configure(
            items: items,
            store: store,
            onToggleDeletion: { [weak self] id in self?.toggleDeletionSelection(id: id) },
            onEdit: { [weak self] item, anchor in self?.requestEdit(item: item, anchor: anchor) }
        )
        stripView.setDeletionState(isActive: selectionState.isActive, selectedIDs: selectionState.selectedIDs)
        stripView.setKeyboardFocus(focusedIndex)
        if store.items.isEmpty {
            emptyLabel.stringValue = "复制文字、截图或色值后，会出现在这里"
            emptyLabel.isHidden = false
        } else if items.isEmpty {
            emptyLabel.stringValue = "没有匹配的剪贴内容"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
        needsDisplay = true
        indicatorView.refresh()
        updateDeletionControls()
    }

    func resetKeyboardFocus() {
        focusedIndex = nil
    }

    // 浏览态下的键盘导航；搜索框聚焦时不拦截（交给输入框）。返回是否已处理。
    func handleKeyNavigation(_ event: NSEvent) -> Bool {
        if window?.firstResponder is NSText { return false }
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_UpArrow:
            moveKeyboardFocus(by: -1)
            return true
        case kVK_RightArrow, kVK_DownArrow:
            moveKeyboardFocus(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateKeyboardFocus()
            return true
        default:
            if let chars = event.charactersIgnoringModifiers,
               let n = Int(chars), n >= 1, n <= 9 {
                selectByNumber(n)
                return true
            }
            return false
        }
    }

    private func moveKeyboardFocus(by delta: Int) {
        guard !displayedItems.isEmpty else { return }
        let next: Int
        if let current = focusedIndex {
            next = max(0, min(displayedItems.count - 1, current + delta))
        } else {
            next = delta > 0 ? 0 : displayedItems.count - 1
        }
        focusedIndex = next
        if let rect = stripView.setKeyboardFocus(next) {
            scrollCardIntoView(rect)
        }
    }

    private func activateKeyboardFocus() {
        guard let idx = focusedIndex else { return }
        stripView.activateCard(at: idx)
    }

    private func selectByNumber(_ n: Int) {
        let idx = n - 1
        guard idx >= 0, idx < displayedItems.count else { return }
        focusedIndex = idx
        stripView.setKeyboardFocus(idx)
        stripView.activateCard(at: idx)
    }

    private func scrollCardIntoView(_ rect: CGRect) {
        let clip = scrollView.contentView
        let visible = clip.bounds
        var targetX = visible.origin.x
        if rect.minX < visible.minX {
            targetX = rect.minX - 8
        } else if rect.maxX > visible.maxX {
            targetX = rect.maxX - visible.width + 8
        }
        let maxX = max((scrollView.documentView?.bounds.width ?? 0) - visible.width, 0)
        targetX = min(max(targetX, 0), maxX)
        clip.scroll(to: CGPoint(x: targetX, y: 0))
        scrollView.reflectScrolledClipView(clip)
        indicatorView.refresh()
    }

    // 按搜索词（匹配 preview / detail）与类型联合过滤；空条件返回全部。
    private func filteredItems() -> [ClipboardHistoryItem] {
        var items = store.items
        if let kind = activeKindFilter {
            items = items.filter { $0.kind == kind }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter {
                $0.preview.lowercased().contains(query) || $0.detail.lowercased().contains(query)
            }
        }
        return items
    }

    func handleEscape() -> Bool {
        if selectionState.isActive {
            cancelDeletionMode()
            return true
        }
        if isSearching {
            exitSearch()
            return true
        }
        return false
    }

    @objc private func toggleSearch() {
        if isSearching {
            exitSearch()
        } else {
            isSearching = true
            needsLayout = true
            refreshHeaderChrome()
            window?.makeFirstResponder(searchField)
        }
    }

    @objc private func cancelSearch() {
        exitSearch()
    }

    private func exitSearch() {
        isSearching = false
        searchQuery = ""
        searchField.stringValue = ""
        activeKindFilter = nil
        filterControl.selectedSegment = 0
        window?.makeFirstResponder(nil)
        needsLayout = true
        refreshHeaderChrome()
        reload()
    }

    @objc private func filterChanged() {
        switch filterControl.selectedSegment {
        case 1: activeKindFilter = .text
        case 2: activeKindFilter = .image
        case 3: activeKindFilter = .link
        case 4: activeKindFilter = .color
        default: activeKindFilter = nil
        }
        reload()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchQuery = searchField.stringValue
        reload()
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        title.frame = CGRect(x: 24, y: bounds.height - 38, width: 150, height: 22)
        closeButton.frame = CGRect(x: bounds.width - 44, y: bounds.height - 39, width: 24, height: 24)
        settingsButton.frame = CGRect(x: bounds.width - 76, y: bounds.height - 39, width: 24, height: 24)
        searchButton.frame = CGRect(x: bounds.width - 108, y: bounds.height - 39, width: 24, height: 24)
        clearButton.frame = CGRect(x: bounds.width - 140, y: bounds.height - 39, width: 24, height: 24)
        confirmDeleteButton.frame = CGRect(x: bounds.width - 112, y: bounds.height - 41, width: 92, height: 26)
        cancelDeleteButton.frame = CGRect(x: bounds.width - 174, y: bounds.height - 41, width: 54, height: 26)
        selectAllButton.frame = CGRect(x: bounds.width - 236, y: bounds.height - 41, width: 54, height: 26)
        // 搜索簇右对齐：… [搜索框] [类型筛选] [取消]
        cancelSearchButton.frame = CGRect(x: bounds.width - 20 - 52, y: bounds.height - 41, width: 52, height: 26)
        filterControl.frame = CGRect(x: cancelSearchButton.frame.minX - 8 - 230, y: bounds.height - 40, width: 230, height: 26)
        searchField.frame = CGRect(x: filterControl.frame.minX - 8 - 190, y: bounds.height - 40, width: 190, height: 26)
        // 搜索时把副标题宽度压到搜索框左侧，避免与搜索簇重叠；平时用全宽。
        let subtitleWidth = isSearching ? max(120, searchField.frame.minX - 8 - 158) : 360
        subtitle.frame = CGRect(x: 158, y: bounds.height - 35, width: subtitleWidth, height: 17)
        scrollView.frame = CGRect(x: 20, y: 25, width: bounds.width - 40, height: 108)
        emptyLabel.frame = CGRect(x: 24, y: 70, width: bounds.width - 48, height: 24)
        indicatorView.frame = CGRect(x: bounds.midX - 90, y: 16, width: 180, height: 4)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        NSColor.white.withAlphaComponent(0.045).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawContentBand()
    }

    private func build() {
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.alphaValue = 0.58
        effectView.layer?.cornerRadius = 20
        effectView.layer?.masksToBounds = true
        addSubview(effectView)
        indicatorView.metricsProvider = { [weak self] in
            self?.scrollMetrics() ?? (progress: 0, visibleRatio: 1, canScroll: false)
        }
        addSubview(indicatorView)
        scrollView.onScroll = { [weak self] in
            // Only the small indicator layer needs to move every frame — invalidating
            // the whole 1160x182 panel here was the actual cause of scroll jank.
            self?.indicatorView.refresh()
            // 清掉滚动中卡住的 hover 高亮（mouseExited 在惯性滚动下不保证送达）。
            self?.stripView.clearHover()
        }

        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        addSubview(title)

        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        addSubview(subtitle)

        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(closeButton)

        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(settingsButton)

        searchButton.target = self
        searchButton.action = #selector(toggleSearch)
        searchButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(searchButton)

        searchField.isHidden = true
        searchField.placeholderString = "搜索剪贴内容"
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.focusRingType = .none
        addSubview(searchField)

        filterControl.isHidden = true
        filterControl.selectedSegment = 0
        filterControl.segmentDistribution = .fillEqually
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        addSubview(filterControl)

        cancelSearchButton.isHidden = true
        cancelSearchButton.target = self
        cancelSearchButton.action = #selector(cancelSearch)
        addSubview(cancelSearchButton)

        clearButton.target = self
        clearButton.action = #selector(enterDeletionMode)
        clearButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(clearButton)

        selectAllButton.target = self
        selectAllButton.action = #selector(selectAllForDeletion)
        selectAllButton.isHidden = true
        addSubview(selectAllButton)

        cancelDeleteButton.target = self
        cancelDeleteButton.action = #selector(cancelDeletionMode)
        cancelDeleteButton.isHidden = true
        addSubview(cancelDeleteButton)

        confirmDeleteButton.target = self
        confirmDeleteButton.action = #selector(confirmDeletion)
        confirmDeleteButton.contentTintColor = .systemRed
        confirmDeleteButton.isHidden = true
        addSubview(confirmDeleteButton)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = stripView
        addSubview(scrollView)

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        addSubview(emptyLabel)
    }

    @objc private func closePanel() {
        dockWindow?.hideDock()
    }

    @objc private func openSettings() {
        dockWindow?.requestOpenSettings()
    }

    @objc private func enterDeletionMode() {
        selectionState.enter()
        updateDeletionControls()
    }

    @objc private func selectAllForDeletion() {
        // 若正在筛选，只全选当前可见（已过滤）的卡片。
        selectionState.selectAll(ids: filteredItems().map(\.id))
        updateDeletionControls()
    }

    @objc private func cancelDeletionMode() {
        selectionState.cancel()
        updateDeletionControls()
    }

    @objc private func confirmDeletion() {
        let ids = selectionState.selectedIDs
        guard !ids.isEmpty else { return }
        let count = ids.count
        let mouse = NSEvent.mouseLocation
        let anchor = CGPoint(x: window?.frame.midX ?? mouse.x, y: window?.frame.maxY ?? mouse.y)
        selectionState.cancel()
        updateDeletionControls()
        store.delete(ids: ids)
        ClipboardDockFeedback.show(message: "已删除 · \(count) 项", tone: .destructive, anchor: anchor)
    }

    private func toggleDeletionSelection(id: String) {
        selectionState.toggle(id: id)
        updateDeletionControls()
    }

    private func requestEdit(item: ClipboardHistoryItem, anchor: CGPoint) {
        guard !selectionState.isActive else { return }
        dockWindow?.showEditor(for: item, anchor: anchor)
    }

    private func updateDeletionControls() {
        let isDeleting = selectionState.isActive
        refreshHeaderChrome()
        confirmDeleteButton.title = "删除（\(selectionState.selectedIDs.count)）"
        confirmDeleteButton.isEnabled = !selectionState.selectedIDs.isEmpty
        subtitle.stringValue = isDeleting ? "选择要删除的卡片，确认后才会删除" : Self.browseHint
        stripView.setDeletionState(isActive: isDeleting, selectedIDs: selectionState.selectedIDs)
    }

    // 统一管理头部控件可见性：删除模式与搜索模式互斥，删除时优先。
    // 搜索时保留标题与提示（右侧空间足够），仅用搜索簇替换右侧图标簇。
    private func refreshHeaderChrome() {
        let isDeleting = selectionState.isActive
        let searching = isSearching && !isDeleting
        title.isHidden = false
        subtitle.isHidden = false
        // 右侧图标簇：删除模式或搜索模式下让位。
        searchButton.isHidden = isDeleting || searching
        settingsButton.isHidden = isDeleting || searching
        closeButton.isHidden = isDeleting || searching
        clearButton.isHidden = isDeleting || searching
        // 搜索簇。
        searchField.isHidden = !searching
        filterControl.isHidden = !searching
        cancelSearchButton.isHidden = !searching
        // 删除簇。
        selectAllButton.isHidden = !isDeleting
        cancelDeleteButton.isHidden = !isDeleting
        confirmDeleteButton.isHidden = !isDeleting
    }

    private func drawContentBand() {
        let band = CGRect(x: 16, y: 10, width: bounds.width - 32, height: 128)
        let path = NSBezierPath(roundedRect: band, xRadius: 14, yRadius: 14)
        NSColor.dockAccent.withAlphaComponent(0.07).setFill()
        path.fill()
        NSColor.dockAccent.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func scrollMetrics() -> (progress: CGFloat, visibleRatio: CGFloat, canScroll: Bool) {
        guard let documentView = scrollView.documentView else {
            return (0, 1, false)
        }
        let contentWidth = documentView.bounds.width
        let visibleWidth = scrollView.contentView.bounds.width
        guard contentWidth > visibleWidth, visibleWidth > 0 else {
            return (0, 1, false)
        }
        let maxOffset = contentWidth - visibleWidth
        let offset = min(max(scrollView.contentView.bounds.minX, 0), maxOffset)
        return (offset / maxOffset, visibleWidth / contentWidth, true)
    }
}

// Backed by CALayers instead of Core Graphics draw(_:) so a scroll-driven position
// update is a cheap GPU-composited layer move, not a full redraw of this view.
final class ScrollIndicatorView: NSView {
    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()
    var metricsProvider: (() -> (progress: CGFloat, visibleRatio: CGFloat, canScroll: Bool))?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        trackLayer.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        layer?.addSublayer(trackLayer)
        thumbLayer.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        layer?.addSublayer(thumbLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        thumbLayer.cornerRadius = bounds.height / 2
        refresh()
    }

    func refresh() {
        let metrics = metricsProvider?() ?? (progress: 0, visibleRatio: 1, canScroll: false)
        let thumbWidth = max(36, bounds.width * metrics.visibleRatio)
        let thumbX = (bounds.width - thumbWidth) * metrics.progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbLayer.frame = CGRect(x: thumbX, y: 0, width: thumbWidth, height: bounds.height)
        // 可滚动时用主题色，不可滚动时淡出为中性白。
        thumbLayer.backgroundColor = metrics.canScroll
            ? NSColor.dockAccent.withAlphaComponent(0.95).cgColor
            : NSColor.white.withAlphaComponent(0.32).cgColor
        CATransaction.commit()
    }
}

final class HorizontalWheelScrollView: NSScrollView {
    var onScroll: (() -> Void)?
    private var momentumTimer: Timer?
    private var velocity: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let horizontalIntent = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
        let rawDelta = horizontalIntent ? event.scrollingDeltaX : event.scrollingDeltaY
        // scrollingDeltaY is positive when the user scrolls up/left with natural
        // scrolling on; our content offset needs the opposite sign to track the gesture.
        let signedDelta = -rawDelta

        if event.hasPreciseScrollingDeltas {
            // Trackpad already streams smooth per-frame deltas, including its own
            // momentum phase after the finger lifts — just follow it directly.
            stopMomentum()
            scrollHorizontally(by: signedDelta * 1.8)
        } else {
            // A mechanical mouse wheel reports large discrete notches; snapping the
            // content by the full notch each time feels stuttery. Feed the notch into
            // a velocity that a decay timer glides smoothly instead.
            velocity += signedDelta * 15
            startMomentumIfNeeded()
        }
    }

    private func startMomentumIfNeeded() {
        guard momentumTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard abs(self.velocity) > 0.5 else {
                timer.invalidate()
                self.momentumTimer = nil
                self.velocity = 0
                return
            }
            self.scrollHorizontally(by: self.velocity)
            self.velocity *= 0.85
        }
        momentumTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        velocity = 0
    }

    func scrollHorizontally(by delta: CGFloat) {
        guard let documentView else { return }
        let clip = contentView
        let maxX = max(documentView.bounds.width - clip.bounds.width, 0)
        let nextX = min(max(clip.bounds.origin.x + delta, 0), maxX)
        clip.scroll(to: CGPoint(x: nextX, y: 0))
        reflectScrolledClipView(clip)
        onScroll?()
    }
}

final class ClipboardCardStripView: NSView {
    private var cardViews: [ClipboardCardView] = []

    func configure(
        items: [ClipboardHistoryItem],
        store: ClipboardHistoryStore,
        onToggleDeletion: @escaping (String) -> Void,
        onEdit: @escaping (ClipboardHistoryItem, CGPoint) -> Void
    ) {
        cardViews.forEach { $0.removeFromSuperview() }
        cardViews = items.map { item in
            let card = ClipboardCardView(item: item, store: store)
            card.onToggleDeletion = { onToggleDeletion(item.id) }
            card.onEdit = onEdit
            return card
        }
        cardViews.forEach(addSubview)
        needsLayout = true
    }

    func setDeletionState(isActive: Bool, selectedIDs: Set<String>) {
        cardViews.forEach { card in
            card.setDeletionState(isActive: isActive, isSelected: selectedIDs.contains(card.itemID))
        }
    }

    /// 设置键盘聚焦卡片，返回其在条内的 frame 供滚动到可见区。
    @discardableResult
    func setKeyboardFocus(_ index: Int?) -> CGRect? {
        for (i, card) in cardViews.enumerated() {
            card.isKeyboardFocused = (i == index)
        }
        guard let index, index >= 0, index < cardViews.count else { return nil }
        return cardViews[index].frame
    }

    func activateCard(at index: Int) {
        guard index >= 0, index < cardViews.count else { return }
        cardViews[index].activateFromKeyboard()
    }

    func clearHover() {
        cardViews.forEach { $0.clearHover() }
    }

    override func layout() {
        super.layout()
        let cardWidth: CGFloat = 180
        let gap: CGFloat = 12
        var x: CGFloat = 4
        for card in cardViews {
            card.frame = CGRect(x: x, y: 2, width: cardWidth, height: 98)
            x += cardWidth + gap
        }
        frame.size = CGSize(width: max(x + 8, superview?.bounds.width ?? x), height: 104)
    }

    override var isFlipped: Bool { true }
}

final class ClipboardCardView: NSView {
    private let item: ClipboardHistoryItem
    private let store: ClipboardHistoryStore
    private let previewButton = ClipboardPreviewButton()
    private let pinButton: DockSymbolButton
    private let editButton = DockSymbolButton(symbolName: "pencil", tooltip: "编辑完整内容")
    private var isHovering = false
    private var isCopied = false
    private var isDeletionMode = false
    private var isSelectedForDeletion = false
    private var successView: SuccessAnimationView?
    var isKeyboardFocused = false {
        didSet { if oldValue != isKeyboardFocused { needsDisplay = true } }
    }
    var onToggleDeletion: (() -> Void)?
    var onEdit: ((ClipboardHistoryItem, CGPoint) -> Void)?
    var itemID: String { item.id }
    private var dockWindow: ClipboardDockWindow? { window as? ClipboardDockWindow }

    init(item: ClipboardHistoryItem, store: ClipboardHistoryStore) {
        self.item = item
        self.store = store
        self.pinButton = DockSymbolButton(symbolName: item.isPinned ? "pin.fill" : "pin", tooltip: item.isPinned ? "取消固定" : "固定到前面")
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = "单击立即复制并收起，编辑请使用按钮或右键菜单"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("复制\(item.kind.categoryTitle)：\(item.cardPreviewText(maxCharacters: 48))")
        setAccessibilityHelp("单击立即复制；删除模式下切换选择")
        setAccessibilityIdentifier("clipboard-card-\(item.id)")
        pinButton.target = self
        pinButton.action = #selector(togglePinned)
        pinButton.contentTintColor = item.isPinned ? .systemOrange : .secondaryLabelColor
        addSubview(pinButton)
        previewButton.target = self
        previewButton.action = #selector(previewItem)
        addSubview(previewButton)
        if item.kind != .image {
            editButton.target = self
            editButton.action = #selector(requestEdit)
            addSubview(editButton)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self))
    }

    override func layout() {
        super.layout()
        previewButton.frame = CGRect(x: bounds.width - 56, y: 8, width: 44, height: 22)
        pinButton.frame = CGRect(x: bounds.width - 86, y: 8, width: 22, height: 22)
        editButton.frame = CGRect(x: bounds.width - 116, y: 8, width: 22, height: 22)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
        guard !isDeletionMode, successView == nil else { return }
        raiseShadow(true)
        updateTilt(at: convert(event.locationInWindow, from: nil), animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isHovering, !isDeletionMode, successView == nil else { return }
        updateTilt(at: convert(event.locationInWindow, from: nil), animated: false)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
        raiseShadow(false)
        resetTilt()
    }

    // 滚动时卡片从光标下滑过，AppKit 在惯性/程序化滚动下不保证发 mouseExited，
    // 会留下一片卡住的 hover 高亮。滚动时统一清一遍，仅重绘真的在 hover 的卡。
    func clearHover() {
        guard isHovering else { return }
        isHovering = false
        needsDisplay = true
        raiseShadow(false)
        resetTilt()
    }

    // 整卡跟随鼠标做轻微 3D 倾斜 + 微抬 + 阴影，营造漂浮感（不拆卡片结构）。
    private let maxTilt: CGFloat = 7 * .pi / 180
    private let hoverScale: CGFloat = 1.04

    private func updateTilt(at point: CGPoint, animated: Bool) {
        guard let layer, bounds.width > 0, bounds.height > 0 else { return }
        let nx = (point.x / bounds.width) * 2 - 1         // -1(左) … 1(右)
        let ny = (point.y / bounds.height) * 2 - 1        // -1(下) … 1(上)
        var t = CATransform3DIdentity
        t.m34 = -1 / 600                                  // 透视
        t = CATransform3DRotate(t, -maxTilt * ny, 1, 0, 0) // 光标上下 → 绕 X（朝光标翘）
        t = CATransform3DRotate(t, maxTilt * nx, 0, 1, 0)  // 光标左右 → 绕 Y
        t = CATransform3DScale(t, hoverScale, hoverScale, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(0.12) }
        layer.transform = t
        CATransaction.commit()
    }

    private func resetTilt() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func raiseShadow(_ up: Bool) {
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 10, cornerHeight: 10, transform: nil)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        layer.shadowOpacity = up ? 0.35 : 0
        layer.shadowRadius = up ? 9 : 0
        layer.shadowOffset = up ? CGSize(width: 0, height: -3) : .zero
        CATransaction.commit()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        if isDeletionMode {
            onToggleDeletion?()
            return
        }
        performCopyAndClose()
    }

    override func accessibilityPerformPress() -> Bool {
        if isDeletionMode {
            onToggleDeletion?()
        } else {
            performCopyAndClose()
        }
        return true
    }

    // 键盘（Enter / 数字键直选）走与单击相同的路径。
    func activateFromKeyboard() {
        if isDeletionMode {
            onToggleDeletion?()
        } else {
            performCopyAndClose()
        }
    }

    func setDeletionState(isActive: Bool, isSelected: Bool) {
        isDeletionMode = isActive
        isSelectedForDeletion = isSelected
        previewButton.isHidden = isActive
        pinButton.isHidden = isActive
        editButton.isHidden = isActive
        needsDisplay = true
    }

    private func performCopyAndClose() {
        // 防重入：动画播放期间忽略再次触发（也避免重复复制）。
        guard successView == nil else { return }
        isCopied = true
        needsDisplay = true
        displayIfNeeded()
        store.restore(item)   // 复制是瞬时的；下面的转圈→对号仅作反馈动效。
        playCopySuccess()
    }

    // 点击后在卡片正中播放「转圈→绿色对号」，动画自然结束再收起 Dock。
    private func playCopySuccess() {
        let diameter: CGFloat = 46
        let view = SuccessAnimationView(diameter: diameter, accent: .dockAccent)
        view.frame = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                            width: diameter, height: diameter)
        addSubview(view)
        successView = view
        view.play { [weak self] in
            self?.dockWindow?.hideDock()
        }
    }

    private var feedbackAnchor: CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        let rectInWindow = convert(bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        return CGPoint(x: rectOnScreen.midX, y: rectOnScreen.maxY)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isDeletionMode else { return nil }
        let menu = NSMenu()
        if item.kind != .image {
            let editItem = NSMenuItem(title: "编辑内容", action: #selector(requestEdit), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)
            menu.addItem(.separator())
        }
        let deleteItem = NSMenuItem(title: "删除这条历史", action: #selector(deleteItem), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        let fillColor: NSColor
        let strokeColor: NSColor
        if isSelectedForDeletion {
            fillColor = NSColor.systemRed.withAlphaComponent(0.30)
            strokeColor = NSColor.systemRed.withAlphaComponent(0.95)
        } else if isCopied {
            fillColor = NSColor.systemGreen.withAlphaComponent(0.34)
            strokeColor = NSColor.systemGreen.withAlphaComponent(0.95)
        } else if isHovering {
            fillColor = NSColor.dockAccent.withAlphaComponent(0.24)
            strokeColor = NSColor.dockAccent.withAlphaComponent(0.85)
        } else if isKeyboardFocused {
            fillColor = NSColor.dockAccent.withAlphaComponent(0.34)
            strokeColor = NSColor.dockAccent.withAlphaComponent(1.0)
        } else {
            fillColor = NSColor.white.withAlphaComponent(0.28)
            strokeColor = NSColor.white.withAlphaComponent(0.38)
        }
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        // 键盘聚焦用更粗的环，与鼠标 hover（同为主题色）区分开。
        path.lineWidth = isKeyboardFocused ? 2 : 1
        path.stroke()

        if isDeletionMode {
            drawDeletionSelectionIndicator()
        }

        drawKindPill()
        switch item.kind {
        case .image:
            drawImageCard()
        case .color:
            drawColorCard()
        case .link:
            drawTextCard(accent: NSColor.systemBlue)
        case .text:
            drawTextCard(accent: NSColor.labelColor)
        }
    }

    private func drawDeletionSelectionIndicator() {
        let circleRect = CGRect(x: bounds.width - 30, y: 10, width: 18, height: 18)
        let circle = NSBezierPath(ovalIn: circleRect)
        let color = isSelectedForDeletion ? NSColor.systemRed : NSColor.secondaryLabelColor
        color.setStroke()
        circle.lineWidth = 1.8
        circle.stroke()
        guard isSelectedForDeletion else { return }
        NSColor.systemRed.setFill()
        circle.fill()
        NSColor.white.setStroke()
        let check = NSBezierPath()
        check.lineWidth = 1.8
        check.lineCapStyle = .round
        check.move(to: CGPoint(x: circleRect.minX + 4, y: circleRect.midY))
        check.line(to: CGPoint(x: circleRect.minX + 8, y: circleRect.minY + 5))
        check.line(to: CGPoint(x: circleRect.maxX - 3, y: circleRect.maxY - 5))
        check.stroke()
    }

    private func drawKindPill() {
        let label = "\(item.kind.categoryTitle) · \(item.relativeTimeText)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSString(string: label).draw(in: CGRect(x: 12, y: 11, width: bounds.width - 134, height: 14), withAttributes: attrs)
    }

    private func drawTextCard(accent: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.maximumLineHeight = 18
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: accent,
            .paragraphStyle: paragraph
        ]
        NSString(string: item.cardPreviewText()).draw(in: CGRect(x: 12, y: 33, width: bounds.width - 24, height: 52), withAttributes: attrs)
    }

    private func drawImageCard() {
        let imageRect = CGRect(x: 12, y: 31, width: bounds.width - 24, height: 56)
        guard let image = store.image(for: item) else {
            drawTextCard(accent: .secondaryLabelColor)
            return
        }
        let clip = NSBezierPath(roundedRect: imageRect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        // Fill (crop-to-cover) instead of fit: fitting left visible letterbox padding
        // around the thumbnail, which read as broken/undersized inside the card.
        let fillRect = image.aspectFillRect(in: imageRect, pixelSize: item.pixelSizeValue)
        image.draw(in: fillRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.16).setStroke()
        clip.stroke()
    }

    private func drawColorCard() {
        let swatch = CGRect(x: 12, y: 34, width: bounds.width - 24, height: 38)
        let color = NSColor.fromClipboardString(item.preview) ?? NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.78, alpha: 1)
        let path = NSBezierPath(roundedRect: swatch, xRadius: 8, yRadius: 8)
        color.setFill()
        path.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: item.preview).draw(in: CGRect(x: 12, y: 78, width: bounds.width - 24, height: 18), withAttributes: attrs)
    }

    @objc private func previewItem() {
        ClipboardPreviewWindow.show(item: item, image: store.image(for: item))
    }

    @objc private func requestEdit() {
        guard item.kind != .image else { return }
        onEdit?(item, feedbackAnchor)
    }

    @objc private func togglePinned() {
        store.togglePinned(item)
        ClipboardDockFeedback.show(
            message: item.isPinned ? "已取消固定" : "已固定到前面",
            tone: .info,
            anchor: feedbackAnchor
        )
    }

    @objc private func deleteItem() {
        store.delete(item)
        ClipboardDockFeedback.show(message: "已删除 · 1 项", tone: .destructive, anchor: feedbackAnchor)
    }
}

final class ClipboardPreviewWindow: NSPanel {
    private static var current: ClipboardPreviewWindow?

    static func show(item: ClipboardHistoryItem, image: NSImage?) {
        current?.close()
        let panel = ClipboardPreviewWindow(item: item, image: image)
        current = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(item: ClipboardHistoryItem, image: NSImage?) {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "剪贴板预览"
        isReleasedWhenClosed = false
        contentView = ClipboardPreviewView(item: item, image: image)
    }
}

final class ClipboardPreviewView: NSView {
    private let item: ClipboardHistoryItem
    private let image: NSImage?

    init(item: ClipboardHistoryItem, image: NSImage?) {
        self.item = item
        self.image = image
        super.init(frame: CGRect(x: 0, y: 0, width: 620, height: 420))
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        if let image {
            let imageView = NSImageView(frame: bounds.insetBy(dx: 24, dy: 24))
            imageView.autoresizingMask = [.width, .height]
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(imageView)
            return
        }

        let scroll = NSScrollView(frame: bounds.insetBy(dx: 18, dy: 18))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.string = item.preview
        text.font = .systemFont(ofSize: 15)
        text.textColor = .labelColor
        text.backgroundColor = .clear
        scroll.documentView = text
        addSubview(scroll)
    }
}

final class DockIconButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        font = .systemFont(ofSize: 17, weight: .medium)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class DockTextButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class DockSymbolButton: NSButton {
    private var isHovered = false

    init(symbolName: String, tooltip: String) {
        super.init(frame: .zero)
        title = ""
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        imagePosition = .imageOnly
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
        contentTintColor = .secondaryLabelColor
        toolTip = tooltip
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        contentTintColor = .labelColor
        animateScale(1.12)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        contentTintColor = .secondaryLabelColor
        animateScale(1.0)
        needsDisplay = true
    }

    private func animateScale(_ scale: CGFloat) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        let fillAlpha: CGFloat = isHighlighted ? 0.30 : (isHovered ? 0.22 : 0.10)
        NSColor.white.withAlphaComponent(fillAlpha).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(isHovered ? 0.30 : 0.22).setStroke()
        path.lineWidth = 1
        path.stroke()
        super.draw(dirtyRect)
    }
}

final class ClipboardPreviewButton: NSButton {
    init() {
        super.init(frame: .zero)
        title = "预览"
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        controlSize = .small
        font = .systemFont(ofSize: 11, weight: .semibold)
        toolTip = "查看完整内容"
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(isHighlighted ? 0.28 : 0.16).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSString(string: title)
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension NSColor {
    /// 拓展坞内所有主题相关色的单一来源；hover / 聚焦 / 内容带 / 滚动条统一从这里派生。
    static var dockAccent: NSColor { AppSettings.shared.accentColor }

    static func fromClipboardString(_ value: String) -> NSColor? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            guard hex.count == 6, let int = Int(hex, radix: 16) else { return nil }
            return NSColor(
                calibratedRed: CGFloat((int >> 16) & 0xff) / 255,
                green: CGFloat((int >> 8) & 0xff) / 255,
                blue: CGFloat(int & 0xff) / 255,
                alpha: 1
            )
        }
        return nil
    }
}

private extension ClipboardHistoryKind {
    var categoryTitle: String {
        switch self {
        case .text: return "文字"
        case .image: return "图片"
        case .color: return "颜色"
        case .link: return "链接"
        }
    }
}

private extension ClipboardHistoryItem {
    var pixelSizeValue: CGSize? {
        guard let width = imageWidth, let height = imageHeight, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    var relativeTimeText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(createdAt)))
        if seconds < 60 { return seconds < 8 ? "刚刚" : "\(seconds)秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)小时前" }
        let days = hours / 24
        return "\(days)天前"
    }
}

private extension NSImage {
    // `size` can disagree with the source's actual pixel aspect ratio once an
    // NSImage round-trips through disk (DPI metadata, HiDPI reps, etc.), which is
    // what was squashing thumbnails. The stored pixel dimensions are ground truth.
    // Fill (not fit): scale to cover the target and crop the overflow so the
    // thumbnail has no letterbox padding around it.
    func aspectFillRect(in target: CGRect, pixelSize: CGSize? = nil) -> CGRect {
        let sourceSize = pixelSize ?? size
        guard sourceSize.width > 0, sourceSize.height > 0, target.width > 0, target.height > 0 else {
            return target
        }
        let scale = max(target.width / sourceSize.width, target.height / sourceSize.height)
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        return CGRect(x: target.midX - width / 2, y: target.midY - height / 2, width: width, height: height)
    }
}
