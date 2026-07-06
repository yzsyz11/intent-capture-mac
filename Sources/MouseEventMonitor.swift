import AppKit
import ApplicationServices
import Foundation

final class MouseEventMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var middleDownAt: Date?
    private var onShortPress: (() -> Void)?
    private var onLongPress: (() -> Void)?
    private(set) var isRunning = false

    private let longPressThreshold: TimeInterval = 0.5

    func start(onShortPress: @escaping () -> Void, onLongPress: @escaping () -> Void) -> Bool {
        stop()

        guard Self.isAccessibilityTrusted() else {
            return false
        }

        self.onShortPress = onShortPress
        self.onLongPress = onLongPress
        startNSEventFallbackMonitors()

        let mask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
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
        middleDownAt = nil
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
            middleDownAt = Date()

        case .otherMouseUp:
            guard let downAt = middleDownAt else { return }
            let elapsed = Date().timeIntervalSince(downAt)
            middleDownAt = nil
            dispatchPress(elapsed: elapsed)

        default:
            break
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.buttonNumber == 2 else { return }

        switch event.type {
        case .otherMouseDown:
            middleDownAt = Date()

        case .otherMouseUp:
            guard let downAt = middleDownAt else { return }
            let elapsed = Date().timeIntervalSince(downAt)
            middleDownAt = nil
            dispatchPress(elapsed: elapsed)

        default:
            break
        }
    }

    private func startNSEventFallbackMonitors() {
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func dispatchPress(elapsed: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if elapsed >= self.longPressThreshold {
                self.onLongPress?()
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
