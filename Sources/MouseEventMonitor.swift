import ApplicationServices
import Foundation

final class MouseEventMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var middleDownAt: Date?
    private var onShortPress: (() -> Void)?
    private var onLongPress: (() -> Void)?

    private let longPressThreshold: TimeInterval = 0.5

    func start(onShortPress: @escaping () -> Void, onLongPress: @escaping () -> Void) -> Bool {
        stop()

        self.onShortPress = onShortPress
        self.onLongPress = onLongPress

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
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        middleDownAt = nil
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
            let elapsed = Date().timeIntervalSince(middleDownAt ?? Date())
            middleDownAt = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if elapsed >= self.longPressThreshold {
                    self.onLongPress?()
                } else {
                    self.onShortPress?()
                }
            }

        default:
            break
        }
    }
}
