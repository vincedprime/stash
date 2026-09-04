import Carbon
import Foundation

@MainActor
final class ShortcutManager {
    var onActivate: (() -> Void)?
    var onToggleRecording: (() -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if id.id == 1 { manager.onActivate?() }
            if id.id == 2 { manager.onToggleRecording?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(open: HotKeyBinding, record: HotKeyBinding) -> Bool {
        unregister()
        let openID = EventHotKeyID(signature: OSType(0x53544153), id: 1) // STAS
        let recordID = EventHotKeyID(signature: OSType(0x53544153), id: 2)
        let openModifiers = open.modifiers
        let recordModifiers = record.modifiers
        var openKey: EventHotKeyRef?
        var recordKey: EventHotKeyRef?
        guard RegisterEventHotKey(open.keyCode, openModifiers, openID, GetApplicationEventTarget(), 0, &openKey) == noErr,
              RegisterEventHotKey(record.keyCode, recordModifiers, recordID, GetApplicationEventTarget(), 0, &recordKey) == noErr,
              let openKey, let recordKey else {
            if let openKey { UnregisterEventHotKey(openKey) }
            return false
        }
        hotKeys = [openKey, recordKey]
        return true
    }

    func unregister() { hotKeys.forEach { UnregisterEventHotKey($0) }; hotKeys = [] }
}
