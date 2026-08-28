import Carbon
import AppKit
import Foundation

final class GlobalHotkeyManager {
    private var actionRef: EventHotKeyRef?
    private var panelRef: EventHotKeyRef?
    private var clipboardRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var globalClipboardFallbackMonitor: Any?
    private var onAction: (() -> Void)?
    private var onPanel: (() -> Void)?
    private var onClipboard: (() -> Void)?
    private var currentAction: HotkeyDefinition?
    private var currentPanel: HotkeyDefinition?
    private var currentClipboard: HotkeyDefinition?
    /// 录制新快捷键期间挂起全局热键：Carbon 热键会物理吞掉按键，必须真正注销才能让录制框收到组合键。
    private(set) var isSuppressed = false

    @discardableResult
    func register(action: HotkeyDefinition, panel: HotkeyDefinition, clipboard: HotkeyDefinition, onAction: @escaping () -> Void, onPanel: @escaping () -> Void, onClipboard: @escaping () -> Void) -> Bool {
        unregister()
        self.onAction = onAction
        self.onPanel = onPanel
        self.onClipboard = onClipboard
        self.currentAction = action
        self.currentPanel = panel
        self.currentClipboard = clipboard
        isSuppressed = false

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            guard !manager.isSuppressed else { return noErr }
            if hotkeyID.id == 1 { manager.onAction?() }
            if hotkeyID.id == 2 { manager.onPanel?() }
            if hotkeyID.id == 3 { manager.onClipboard?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        guard handlerStatus == noErr else {
            return false
        }

        let actionID = EventHotKeyID(signature: fourCharCode("ICAP"), id: 1)
        let panelID = EventHotKeyID(signature: fourCharCode("ICAP"), id: 2)
        let clipboardID = EventHotKeyID(signature: fourCharCode("ICAP"), id: 3)
        let actionStatus = RegisterEventHotKey(action.keyCode, action.modifiers, actionID, GetApplicationEventTarget(), 0, &actionRef)
        let panelStatus = RegisterEventHotKey(panel.keyCode, panel.modifiers, panelID, GetApplicationEventTarget(), 0, &panelRef)
        let clipboardStatus = RegisterEventHotKey(clipboard.keyCode, clipboard.modifiers, clipboardID, GetApplicationEventTarget(), 0, &clipboardRef)
        installLocalMonitor(action: action, panel: panel, clipboard: clipboard)
        if clipboardStatus != noErr {
            installGlobalClipboardFallback(clipboard: clipboard)
        }
        return actionStatus == noErr && panelStatus == noErr && clipboardStatus == noErr
    }

    /// 录制期挂起：注销 Carbon 热键并让本地监听放行，使录制框能收到任意组合键；结束后恢复。
    func setSuppressed(_ flag: Bool) {
        guard flag != isSuppressed else { return }
        isSuppressed = flag
        if flag {
            if let actionRef { UnregisterEventHotKey(actionRef); self.actionRef = nil }
            if let panelRef { UnregisterEventHotKey(panelRef); self.panelRef = nil }
            if let clipboardRef { UnregisterEventHotKey(clipboardRef); self.clipboardRef = nil }
        } else {
            reRegisterCarbonHotkeys()
        }
    }

    private func reRegisterCarbonHotkeys() {
        guard let action = currentAction, let panel = currentPanel, let clipboard = currentClipboard else { return }
        let signature = fourCharCode("ICAP")
        RegisterEventHotKey(action.keyCode, action.modifiers, EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &actionRef)
        RegisterEventHotKey(panel.keyCode, panel.modifiers, EventHotKeyID(signature: signature, id: 2), GetApplicationEventTarget(), 0, &panelRef)
        RegisterEventHotKey(clipboard.keyCode, clipboard.modifiers, EventHotKeyID(signature: signature, id: 3), GetApplicationEventTarget(), 0, &clipboardRef)
    }

    func unregister() {
        if let actionRef { UnregisterEventHotKey(actionRef) }
        if let panelRef { UnregisterEventHotKey(panelRef) }
        if let clipboardRef { UnregisterEventHotKey(clipboardRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalClipboardFallbackMonitor { NSEvent.removeMonitor(globalClipboardFallbackMonitor) }
        actionRef = nil
        panelRef = nil
        clipboardRef = nil
        handlerRef = nil
        localKeyMonitor = nil
        globalClipboardFallbackMonitor = nil
    }

    private func installLocalMonitor(action: HotkeyDefinition, panel: HotkeyDefinition, clipboard: HotkeyDefinition) {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isSuppressed { return event }
            if self.matches(event, hotkey: action) {
                self.onAction?()
                return nil
            }
            if self.matches(event, hotkey: panel) {
                self.onPanel?()
                return nil
            }
            if self.matches(event, hotkey: clipboard) {
                self.onClipboard?()
                return nil
            }
            return event
        }
    }

    private func installGlobalClipboardFallback(clipboard: HotkeyDefinition) {
        globalClipboardFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.isSuppressed, self.matches(event, hotkey: clipboard) else { return }
            self.onClipboard?()
        }
    }

    private func matches(_ event: NSEvent, hotkey: HotkeyDefinition) -> Bool {
        UInt32(event.keyCode) == hotkey.keyCode && carbonModifiers(from: event.modifierFlags) == hotkey.modifiers
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
