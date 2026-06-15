import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let captureService = CaptureService()
    private let hotkeys = GlobalHotkeyManager()
    private let mouseMonitor = MouseEventMonitor()
    private var statusItem: NSStatusItem?
    private var actionPanel: ActionPanelWindow?
    private var settingsWindow: SettingsWindow?
    private var middleClickStatus = "中键监听：未启动"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        setupStatusItem()
        registerHotkeys()
        startMouseMonitor()
        showHome()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseMonitor.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showActionPanel()
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem(title: "检查屏幕录制权限", action: #selector(checkScreenCapturePermission), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "开启中键权限...", action: #selector(requestAccessibilityPermission), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Intent Capture", action: #selector(quit), keyEquivalent: "q"))
        appMenu.items.forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let actionsItem = NSMenuItem()
        let actionsMenu = NSMenu(title: "操作")
        actionsMenu.addItem(NSMenuItem(title: "打开主页", action: #selector(showActionPanel), keyEquivalent: "w"))
        actionsMenu.addItem(NSMenuItem(title: "执行默认动作", action: #selector(executeRecent), keyEquivalent: "s"))
        actionsMenu.addItem(NSMenuItem.separator())
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(executeActionFromMenu(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.state = action == settings.recentAction ? .on : .off
            actionsMenu.addItem(item)
        }
        actionsMenu.items.forEach { $0.target = self }
        actionsItem.submenu = actionsMenu
        mainMenu.addItem(actionsItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        statusItem?.button?.title = ""
        statusItem?.button?.image = Self.statusBarImage()
        statusItem?.button?.toolTip = "Intent Capture"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开主页", action: #selector(showActionPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "执行默认动作：\(settings.recentAction.title)", action: #selector(executeRecent), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(executeActionFromMenu(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.state = action == settings.recentAction ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: middleClickStatus, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "检查屏幕录制权限", action: #selector(checkScreenCapturePermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "开启中键权限...", action: #selector(requestAccessibilityPermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    private func registerHotkeys() {
        let registered = hotkeys.register(
            action: settings.actionHotkey,
            panel: settings.panelHotkey,
            onAction: { [weak self] in self?.executeRecent() },
            onPanel: { [weak self] in self?.showActionPanel() }
        )
        if !registered {
            Toast.show("快捷键注册失败，可能被其他应用占用。请到设置里更换快捷键。")
        }
    }

    private func startMouseMonitor() {
        mouseMonitor.stop()
        guard settings.middleClickEnabled else {
            middleClickStatus = "中键监听：已关闭"
            setupStatusItem()
            return
        }

        let started = mouseMonitor.start(
            onShortPress: { [weak self] in self?.executeRecent() },
            onLongPress: { [weak self] in self?.showActionPanel() }
        )

        if started {
            middleClickStatus = "中键监听：运行中"
            setupStatusItem()
        } else {
            middleClickStatus = MouseEventMonitor.isAccessibilityTrusted()
                ? "中键监听：启动失败"
                : "中键监听：未授权"
            setupStatusItem()
            Toast.show("中键监听不可用。请移除系统设置里的旧 IntentCapture 条目，重新添加 /Applications/IntentCapture.app，并重启 App。")
        }
    }

    private func showHome() {
        showActionPanel()
    }

    @objc private func executeRecent() {
        captureService.perform(settings.recentAction)
    }

    @objc private func executeActionFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = CaptureAction(rawValue: rawValue) else {
            return
        }
        settings.recentAction = action
        setupStatusItem()
        captureService.perform(action)
    }

    @objc private func showActionPanel() {
        if actionPanel == nil {
            actionPanel = ActionPanelWindow { [weak self] action in
                guard let strongSelf = self else { return }
                strongSelf.settings.recentAction = action
                strongSelf.setupStatusItem()
                strongSelf.captureService.perform(action)
            } onSettings: { [weak self] in
                self?.showSettings()
            }
        }
        actionPanel?.showMainWindow()
    }

    @objc private func showSettings() {
        settingsWindow = SettingsWindow { [weak self] in
            self?.registerHotkeys()
            self?.startMouseMonitor()
            self?.setupStatusItem()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func requestAccessibilityPermission() {
        if MouseEventMonitor.requestAccessibilityPermission() {
            startMouseMonitor()
            Toast.show("中键权限已开启")
        } else {
            Toast.show("请在系统设置中允许 Intent Capture 的辅助功能权限。")
        }
    }

    @objc private func checkScreenCapturePermission() {
        if CGPreflightScreenCaptureAccess() {
            Toast.show("当前 App 的屏幕录制权限已生效")
        } else {
            CGRequestScreenCaptureAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            Toast.show("屏幕录制权限未生效；开启后请退出并重新打开 App。")
        }
    }

    private static func statusBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        let rect = NSRect(x: 3, y: 4, width: 12, height: 10)
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.move(to: NSPoint(x: rect.minX, y: rect.minY + 3))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + 3, y: rect.minY))
        path.move(to: NSPoint(x: rect.maxX - 3, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + 3))
        path.move(to: NSPoint(x: rect.maxX, y: rect.maxY - 3))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX - 3, y: rect.maxY))
        path.move(to: NSPoint(x: rect.minX + 3, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - 3))
        path.stroke()

        let dot = NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 2, height: 2))
        dot.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
