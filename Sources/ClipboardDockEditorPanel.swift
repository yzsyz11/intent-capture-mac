import AppKit

final class ClipboardDockEditorPanel: NSPanel {
    private let editorView: ClipboardDockEditorView

    init(item: ClipboardHistoryItem, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        editorView = ClipboardDockEditorView(text: item.preview, onSave: onSave, onCancel: onCancel)
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 274),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = editorView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(above dockFrame: CGRect, centeredAt anchorX: CGFloat) {
        let targetScreen = NSScreen.screens.first { $0.frame.intersects(dockFrame) } ?? NSScreen.main
        let visible = targetScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let x = min(max(anchorX - frame.width / 2, visible.minX + 12), visible.maxX - frame.width - 12)
        let y = min(dockFrame.maxY + 10, visible.maxY - frame.height - 12)
        setFrameOrigin(CGPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        editorView.focusEditor()
    }
}

final class ClipboardDockEditorView: NSView {
    private let effectView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "编辑剪贴板内容")
    private let hintLabel = NSTextField(labelWithString: "⌘↩ 保存 · Esc 取消")
    private let scrollView = NSScrollView()
    private let textView = ClipboardEditorTextView()
    private let cancelButton = DockTextButton(title: "取消", target: nil, action: nil)
    private let saveButton = DockTextButton(title: "保存", target: nil, action: nil)
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    init(text: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(frame: CGRect(x: 0, y: 0, width: 420, height: 274))
        wantsLayer = true
        build(text: text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        titleLabel.frame = CGRect(x: 18, y: bounds.height - 37, width: 190, height: 22)
        hintLabel.frame = CGRect(x: bounds.width - 170, y: bounds.height - 34, width: 152, height: 18)
        scrollView.frame = CGRect(x: 16, y: 52, width: bounds.width - 32, height: bounds.height - 98)
        let editorSize = scrollView.contentSize
        textView.minSize = CGSize(width: 0, height: editorSize.height)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame.size.width = editorSize.width
        textView.frame.size.height = max(textView.frame.height, editorSize.height)
        textView.textContainer?.containerSize = CGSize(width: editorSize.width, height: CGFloat.greatestFiniteMagnitude)
        cancelButton.frame = CGRect(x: bounds.width - 132, y: 14, width: 52, height: 28)
        saveButton.frame = CGRect(x: bounds.width - 70, y: 14, width: 54, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSColor.white.withAlphaComponent(0.10).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.56).setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    private func build(text: String) {
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        addSubview(titleLabel)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .right
        addSubview(hintLabel)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.78)

        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = CGSize(width: 8, height: 8)
        textView.onCommandReturn = { [weak self] in
            DispatchQueue.main.async { self?.saveEditing() }
        }
        textView.onEscape = { [weak self] in
            DispatchQueue.main.async { self?.cancelEditing() }
        }
        scrollView.documentView = textView
        addSubview(scrollView)

        cancelButton.target = self
        cancelButton.action = #selector(cancelEditing)
        addSubview(cancelButton)
        saveButton.target = self
        saveButton.action = #selector(saveEditing)
        saveButton.contentTintColor = .systemBlue
        addSubview(saveButton)
    }

    @objc private func saveEditing() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }
        onSave(text)
    }

    @objc private func cancelEditing() {
        onCancel()
    }
}

final class ClipboardEditorTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommandReturn?()
            return
        }
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
