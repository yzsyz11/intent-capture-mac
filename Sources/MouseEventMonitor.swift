import AppKit
import ApplicationServices
import Foundation

final class MouseEventMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isMiddleDown = false
    private var menuOpen = false
    private var pressBeginWorkItem: DispatchWorkItem?
    private var menuOpenWorkItem: DispatchWorkItem?
    private var onShortPress: (() -> Void)?
    private var onPressBegin: ((CGPoint, TimeInterval) -> Void)?
    private var onMenuOpen: (() -> Void)?
    private var onMenuUpdate: ((CGPoint) -> Void)?
    private var onMenuCommit: (() -> Void)?
    private(set) var isRunning = false

    private let longPressThreshold: TimeInterval = 0.5
    private let ringDelay: TimeInterval = 0.12

    /// onPressBegin(anchor, duration) 在按住越过短暂延时后触发，用于展示长按进度环，
    ///   duration 为进度环需要转满的时长；anchor 为全局 AppKit 坐标（中键按下位置）；
    /// onMenuOpen 在长按阈值达到（仍按住）时触发，进度环绽放成轮盘；
    /// onMenuUpdate(location) 在轮盘展开后随鼠标移动实时触发；
    /// onMenuCommit 在轮盘展开状态下松开中键时触发；
    /// onShortPress 在未达阈值就松开时触发。
    func start(onShortPress: @escaping () -> Void,
               onPressBegin: @escaping (CGPoint, TimeInterval) -> Void,
               onMenuOpen: @escaping () -> Void,
               onMenuUpdate: @escaping (CGPoint) -> Void,
               onMenuCommit: @escaping () -> Void) -> Bool {
        stop()

        guard Self.isAccessibilityTrusted() else {
            return false
        }

        self.onShortPress = onShortPress
        self.onPressBegin = onPressBegin
        self.onMenuOpen = onMenuOpen
        self.onMenuUpdate = onMenuUpdate
        self.onMenuCommit = onMenuCommit
        startNSEventFallbackMonitors()

        let mask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    monitor.reenableTapIfNeeded()
                    return Unmanaged.passUnretained(event)
                }
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            isRunning = true
            return true
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = CGEvent.tapIsEnabled(tap: tap) || globalMouseMonitor != nil || localMouseMonitor != nil
        return isRunning
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }

        globalMouseMonitor = nil
        localMouseMonitor = nil
        runLoopSource = nil
        eventTap = nil
        pressBeginWorkItem?.cancel()
        menuOpenWorkItem?.cancel()
        pressBeginWorkItem = nil
        menuOpenWorkItem = nil
        isMiddleDown = false
        menuOpen = false
        isRunning = false
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNumber == 2 else { return }

        switch type {
        case .otherMouseDown:
            dispatchDown()
        case .otherMouseUp:
            dispatchUp()
        case .otherMouseDragged:
            dispatchDrag()
        default:
            break
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.buttonNumber == 2 else { return }

        switch event.type {
        case .otherMouseDown:
            dispatchDown()
        case .otherMouseUp:
            dispatchUp()
        case .otherMouseDragged:
            dispatchDrag()
        default:
            break
        }
    }

    private func startNSEventFallbackMonitors() {
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func dispatchDown() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 环形菜单/Dock 出现之前，先记住此刻的前台 App（用于剪贴板点击回填输入框）。
            if let front = NSWorkspace.shared.frontmostApplication,
               front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                ClipboardDockWindow.lastForegroundApp = front
            }
            self.isMiddleDown = true
            self.menuOpen = false
            let anchor = NSEvent.mouseLocation

            self.pressBeginWorkItem?.cancel()
            self.menuOpenWorkItem?.cancel()

            // 越过短暂延时仍按住 → 展示长按进度环（避免普通中键单击闪一下）
            let ringWork = DispatchWorkItem { [weak self] in
                guard let self = self, self.isMiddleDown, !self.menuOpen else { return }
                self.onPressBegin?(anchor, self.longPressThreshold - self.ringDelay)
            }
            self.pressBeginWorkItem = ringWork
            DispatchQueue.main.asyncAfter(deadline: .now() + self.ringDelay, execute: ringWork)

            // 达到长按阈值仍按住 → 绽放成轮盘
            let menuWork = DispatchWorkItem { [weak self] in
                guard let self = self, self.isMiddleDown, !self.menuOpen else { return }
                self.menuOpen = true
                self.onMenuOpen?()
            }
            self.menuOpenWorkItem = menuWork
            DispatchQueue.main.asyncAfter(deadline: .now() + self.longPressThreshold, execute: menuWork)
        }
    }

    private func dispatchDrag() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.menuOpen else { return }
            self.onMenuUpdate?(NSEvent.mouseLocation)
        }
    }

    private func dispatchUp() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pressBeginWorkItem?.cancel()
            self.menuOpenWorkItem?.cancel()
            self.pressBeginWorkItem = nil
            self.menuOpenWorkItem = nil
            let wasDown = self.isMiddleDown
            self.isMiddleDown = false
            guard wasDown else { return }
            if self.menuOpen {
                self.menuOpen = false
                self.onMenuUpdate?(NSEvent.mouseLocation)
                self.onMenuCommit?()
            } else {
                self.onShortPress?()
            }
        }
    }

    private func reenableTapIfNeeded() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = CGEvent.tapIsEnabled(tap: eventTap) || globalMouseMonitor != nil || localMouseMonitor != nil
    }
}
