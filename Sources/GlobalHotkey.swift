import Carbon
import Foundation

final class GlobalHotkeyManager {
    private var actionRef: EventHotKeyRef?
    private var panelRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onAction: (() -> Void)?
    private var onPanel: (() -> Void)?

    @discardableResult
    func register(action: HotkeyDefinition, panel: HotkeyDefinition, onAction: @escaping () -> Void, onPanel: @escaping () -> Void) -> Bool {
        unregister()
        self.onAction = onAction
        self.onPanel = onPanel

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
            if hotkeyID.id == 1 { manager.onAction?() }
            if hotkeyID.id == 2 { manager.onPanel?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        guard handlerStatus == noErr else {
            return false
        }

        let actionID = EventHotKeyID(signature: fourCharCode("ICAP"), id: 1)
        let panelID = EventHotKeyID(signature: fourCharCode("ICAP"), id: 2)
        let actionStatus = RegisterEventHotKey(action.keyCode, action.modifiers, actionID, GetApplicationEventTarget(), 0, &actionRef)
        let panelStatus = RegisterEventHotKey(panel.keyCode, panel.modifiers, panelID, GetApplicationEventTarget(), 0, &panelRef)
        return actionStatus == noErr && panelStatus == noErr
    }

    func unregister() {
        if let actionRef { UnregisterEventHotKey(actionRef) }
        if let panelRef { UnregisterEventHotKey(panelRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        actionRef = nil
        panelRef = nil
        handlerRef = nil
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
