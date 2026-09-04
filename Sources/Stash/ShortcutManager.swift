import Carbon
import Foundation

@MainActor
final class ShortcutManager {
    var onActivate: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onActivate?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(optionShift: Bool) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x53544153), id: 1) // STAS
        let modifiers = optionKey | (optionShift ? shiftKey : 0)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    func unregister() { if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil } }
}
