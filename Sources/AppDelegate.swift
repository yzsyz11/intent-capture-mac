import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let captureService = CaptureService()
    private let clipboardStore = ClipboardHistoryStore.shared
    private let hotkeys = GlobalHotkeyManager()
    private let mouseMonitor = MouseEventMonitor()
    private var statusItem: NSStatusItem?
    private var homeWindow: HomeWindow?
    private var clipboardDock: ClipboardDockWindow?
    private var radialMenu: RadialMenuWindow?
    private var middleClickStatus = "中键监听：未启动"
    private var permissionWatcher: PermissionWatcher?
    private var onboardingWindow: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        registerHotkeys()
        startClipboardHistory()
        startMouseMonitor()
        // 使用截图/取色/OCR 若发现屏幕录制没授权，统一弹权限向导（而非直接甩到系统设置）。
        captureService.onNeedScreenRecording = { [weak self] in self?.showOnboarding() }
        // 评估两项权限，把当前已生效状态记入历史（供三态判定与升级引导使用）。
        recordPermissionBaseline()
        maybeShowOnboarding()
    }

    /// 有权限未生效，且（首次启动 或 装了新版）→ 弹权限引导向导；否则静默常驻。
    /// 权限都齐时首启仍弹一次主页做基本引导，保持原有行为。
    private func maybeShowOnboarding() {
        let anyMissing = PermissionKind.allCases.contains { PermissionEvaluator.state(of: $0) != .granted }
        let isNewBuild = settings.onboardingLastSeenBuild != AppBuildSignature.current
        let firstLaunch = !settings.hasLaunchedBefore

        if anyMissing && (firstLaunch || isNewBuild) {
            showOnboarding()
        } else if firstLaunch {
            showHome()
        }
        settings.hasLaunchedBefore = true
        settings.onboardingLastSeenBuild = AppBuildSignature.current
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindow(onGranted: { [weak self] kind in self?.onPermissionGranted(kind) })
        }
        onboardingWindow?.present()
    }

    /// 手动打开权限向导（菜单入口）：不依赖"缺权限才弹"，随时可查看 / 重新走一遍。
    /// 权限都齐时显示两行绿灯 + 完成可点，作为"已就绪"状态查看。
    @objc private func openOnboardingGuide() {
        showOnboarding()
    }

    /// 启动时评估两项权限：判为已生效者顺手写入历史标记与构建签名，
    /// 使后续能区分「从没授过」与「曾授过现失效（僵尸）」。仅记录，不弹窗。
    private func recordPermissionBaseline() {
        for kind in PermissionKind.allCases {
            _ = PermissionEvaluator.state(of: kind, settings: settings)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardStore.stop()
        clipboardStore.flush()
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
        appMenu.addItem(NSMenuItem(title: "权限设置向导...", action: #selector(openOnboardingGuide), keyEquivalent: ""))
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
        actionsMenu.addItem(NSMenuItem(title: "打开剪贴板拓展坞", action: #selector(toggleClipboardDock), keyEquivalent: "d"))
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
        menu.addItem(NSMenuItem(title: "打开剪贴板拓展坞", action: #selector(toggleClipboardDock), keyEquivalent: ""))
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
        menu.addItem(NSMenuItem(title: "权限设置向导...", action: #selector(openOnboardingGuide), keyEquivalent: ""))
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
            clipboard: settings.clipboardDockHotkey,
            onAction: { [weak self] in self?.executeRecent() },
            onPanel: { [weak self] in self?.showActionPanel() },
            onClipboard: { [weak self] in self?.toggleClipboardDock() }
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
            onShortPress: { [weak self] in self?.cancelRadialMenu(); self?.executeRecent() },
            onPressBegin: { [weak self] anchor, duration in self?.openRadialMenu(at: anchor, ringDuration: duration) },
            onMenuOpen: { [weak self] in self?.radialMenu?.bloomIntoWheel() },
            onMenuUpdate: { [weak self] location in self?.radialMenu?.updateCursor(location) },
            onMenuCommit: { [weak self] in self?.commitRadialMenu() }
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

    private func startClipboardHistory() {
        clipboardStore.onChange = { [weak self] _ in
            self?.clipboardDock?.refresh()
        }
        if settings.clipboardHistoryEnabled {
            clipboardStore.start()
        } else {
            clipboardStore.stop()
            clipboardDock?.hideDock()   // 关闭时收起已开的拓展坞
        }
    }

    private func showHome() {
        showActionPanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func executeRecent() {
        captureService.perform(settings.recentAction)
    }

    private func openRadialMenu(at anchor: CGPoint, ringDuration: TimeInterval) {
        radialMenu?.close()
        let menu = RadialMenuWindow(anchor: anchor, actions: CaptureAction.allCases)
        radialMenu = menu
        menu.presentProgress(duration: ringDuration)
    }

    private func cancelRadialMenu() {
        guard let menu = radialMenu else { return }
        radialMenu = nil
        menu.dismiss {}
    }

    private func commitRadialMenu() {
        guard let menu = radialMenu else { return }
        let action = menu.selectedAction()
        radialMenu = nil
        // 先收起玻璃圆盘，再执行动作，避免覆盖层被截进图（尤其取色是整屏抓取）。
        menu.dismiss { [weak self] in
            guard let self = self, let action = action else { return }
            self.captureService.perform(action)
        }
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
        openHome(section: .action)
    }

    @objc private func toggleClipboardDock() {
        guard settings.clipboardHistoryEnabled else {
            Toast.show("剪贴板拓展坞已关闭，请在功能里开启")
            return
        }
        if clipboardDock == nil {
            let dock = ClipboardDockWindow(store: clipboardStore)
            dock.onOpenSettings = { [weak self] in self?.showActionPanel() }
            clipboardDock = dock
        }
        clipboardDock?.toggle()
    }

    @objc private func showSettings() {
        openHome(section: .trigger)
    }

    private func openHome(section: HomeSection) {
        if homeWindow == nil {
            let window = HomeWindow(onSelectAction: { [weak self] action in
                guard let strongSelf = self else { return }
                strongSelf.settings.recentAction = action
                strongSelf.setupStatusItem()
                strongSelf.homeWindow?.close()
                strongSelf.captureService.perform(action)
            }, onSettingsSaved: { [weak self] in
                self?.registerHotkeys()
                self?.startClipboardHistory()
                self?.startMouseMonitor()
                self?.setupStatusItem()
            }, onHeal: { [weak self] kind in
                self?.healPermission(kind)
            })
            homeWindow = window
        }
        homeWindow?.showMainWindow(section: section)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func requestAccessibilityPermission() {
        healPermission(.accessibility)
    }

    @objc private func checkScreenCapturePermission() {
        healPermission(.screenRecording)
    }

    /// 三态自愈入口：僵尸先清后授、未授权直接授，已生效则收尾；随后轮询直到生效自动前进。
    private func healPermission(_ kind: PermissionKind) {
        let state = PermissionEvaluator.state(of: kind)
        if state == .granted {
            onPermissionGranted(kind)
            return
        }
        Toast.show(state == .stale
            ? "检测到旧授权失效，正在清理并重新申请\(kind.displayName)…"
            : "正在申请\(kind.displayName)权限，请在系统设置中允许…")
        PermissionHealer.heal(kind, state: state)
        watchUntilGranted(kind)
    }

    /// 轮询该权限，一旦生效即停表并收尾。
    private func watchUntilGranted(_ kind: PermissionKind) {
        permissionWatcher?.stop()
        let watcher = PermissionWatcher { [weak self] states in
            guard let self, states[kind] == .granted else { return }
            self.permissionWatcher?.stop()
            self.permissionWatcher = nil
            self.onPermissionGranted(kind)
        }
        permissionWatcher = watcher
        watcher.start()
    }

    /// 授权生效后的收尾：中键尝试即时启用，起不来则可靠重启；屏幕录制必须重启一次。
    private func onPermissionGranted(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            settings.middleClickEnabled = true
            startMouseMonitor()
            if middleClickStatus == "中键监听：运行中" {
                Toast.show("中键权限已开启")
            } else {
                promptRestart(message: "中键权限已授权", info: "重启 Intent Capture 后中键监听即生效。")
            }
        case .screenRecording:
            promptRestart(message: "屏幕录制已授权", info: "系统要求重启 App 后此权限才生效。")
        }
    }

    /// 可靠重启确认框：确认后走脱离进程的 relaunch，解决"自动重启失败"。
    private func promptRestart(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            AppRelauncher.relaunch()
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
