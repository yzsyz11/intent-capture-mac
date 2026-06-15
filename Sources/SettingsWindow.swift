import AppKit
import ApplicationServices

final class SettingsWindow: NSWindow {
    private let settings = AppSettings.shared
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Intent Capture 设置"
        isReleasedWhenClosed = false
        center()
        contentView = SettingsView(settings: settings, onSave: { [weak self] in
            onSave()
            self?.refreshPermissionStatus()
        })
    }

    func refreshPermissionStatus() {
        (contentView as? SettingsView)?.refreshPermissionStatus()
    }
}

final class SettingsView: NSView {
    private let settings: AppSettings
    private let onSave: () -> Void

    private let actionHotkey: HotkeyRecorderButton
    private let panelHotkey: HotkeyRecorderButton
    private let directory = NSTextField()
    private let defaultAction = NSPopUpButton()
    private let colorFormat = NSPopUpButton()
    private let middleClickEnabled = NSButton(checkboxWithTitle: "启用鼠标中键触发", target: nil, action: nil)
    private let accessibilityStatus = NSTextField(labelWithString: "")

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.actionHotkey = HotkeyRecorderButton(hotkey: settings.actionHotkey)
        self.panelHotkey = HotkeyRecorderButton(hotkey: settings.panelHotkey)
        super.init(frame: CGRect(x: 0, y: 0, width: 620, height: 470))
        build()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        addSectionTitle("键盘快捷键", y: 418)
        addRow("执行默认动作", actionHotkey, y: 374)
        addRow("打开主页", panelHotkey, y: 326)

        actionHotkey.onChange = { [weak self] hotkey in
            self?.settings.actionHotkey = hotkey
            self?.onSave()
            Toast.show("动作快捷键已更新：\(hotkey.displayText)")
        }
        panelHotkey.onChange = { [weak self] hotkey in
            self?.settings.panelHotkey = hotkey
            self?.onSave()
            Toast.show("主页快捷键已更新：\(hotkey.displayText)")
        }

        addSectionTitle("鼠标中键", y: 282)
        middleClickEnabled.target = self
        middleClickEnabled.action = #selector(toggleMiddleClick)
        middleClickEnabled.frame = CGRect(x: 172, y: 242, width: 220, height: 24)
        addSubview(middleClickEnabled)

        accessibilityStatus.frame = CGRect(x: 172, y: 214, width: 306, height: 20)
        accessibilityStatus.textColor = .secondaryLabelColor
        addSubview(accessibilityStatus)

        let request = NSButton(title: "开启辅助功能权限", target: self, action: #selector(requestAccessibility))
        request.bezelStyle = .rounded
        request.frame = CGRect(x: 420, y: 238, width: 150, height: 30)
        addSubview(request)

        addSectionTitle("默认与保存", y: 176)
        addRow("保存目录", directory, y: 132)
        addRow("默认动作", defaultAction, y: 84)
        addRow("色值格式", colorFormat, y: 36)

        defaultAction.addItems(withTitles: CaptureAction.allCases.map(\.title))
        defaultAction.target = self
        defaultAction.action = #selector(saveClick)

        colorFormat.addItems(withTitles: ["HEX", "RGB"])
        colorFormat.target = self
        colorFormat.action = #selector(saveClick)

        directory.target = self
        directory.action = #selector(saveClick)
    }

    private func loadValues() {
        actionHotkey.hotkey = settings.actionHotkey
        panelHotkey.hotkey = settings.panelHotkey
        directory.stringValue = settings.saveDirectory.path
        defaultAction.selectItem(withTitle: settings.recentAction.title)
        colorFormat.selectItem(withTitle: settings.colorFormat)
        middleClickEnabled.state = settings.middleClickEnabled ? .on : .off
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        if AXIsProcessTrusted() {
            accessibilityStatus.stringValue = "辅助功能权限已生效；保存后会重启中键监听"
        } else {
            accessibilityStatus.stringValue = "辅助功能权限未对当前 App 生效；可能是旧条目或需重启"
        }
    }

    private func addSectionTitle(_ title: String, y: CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.frame = CGRect(x: 34, y: y, width: 180, height: 22)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        addSubview(label)
    }

    private func addRow(_ title: String, _ control: NSView, y: CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.frame = CGRect(x: 34, y: y + 5, width: 130, height: 20)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        control.frame = CGRect(x: 172, y: y, width: 306, height: 28)
        addSubview(control)
    }

    @objc private func toggleMiddleClick() {
        settings.middleClickEnabled = middleClickEnabled.state == .on
        onSave()
        Toast.show(settings.middleClickEnabled ? "已启用鼠标中键触发" : "已关闭鼠标中键触发")
    }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
        Toast.show("授权后请退出并重新打开 Intent Capture。")
    }

    @objc private func saveClick() {
        if !directory.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.saveDirectory = URL(fileURLWithPath: directory.stringValue, isDirectory: true)
        }
        if let selected = defaultAction.titleOfSelectedItem,
           let action = CaptureAction.allCases.first(where: { $0.title == selected }) {
            settings.recentAction = action
        }
        settings.colorFormat = colorFormat.titleOfSelectedItem ?? "HEX"
        onSave()
        Toast.show("设置已保存")
    }
}
