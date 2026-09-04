import AppKit
import Carbon
import SwiftUI

struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let openDefault = HotKeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let recordDefault = HotKeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))

    var display: String {
        var result = ""
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        return result + (keyName ?? "Key")
    }

    private var keyName: String? {
        switch keyCode {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        default: return nil
        }
    }

    static func from(_ event: NSEvent) -> HotKeyBinding? {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { return nil }
        return HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}

struct ShortcutSettingsView: View {
    @State private var openShortcut: HotKeyBinding
    @State private var recordingShortcut: HotKeyBinding
    @State private var message = ""
    let onSave: (HotKeyBinding, HotKeyBinding) -> Bool

    init(open: HotKeyBinding, recording: HotKeyBinding, onSave: @escaping (HotKeyBinding, HotKeyBinding) -> Bool) {
        _openShortcut = State(initialValue: open)
        _recordingShortcut = State(initialValue: recording)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title2.weight(.semibold))
            Text("Click a shortcut, then press your preferred key combination. Global shortcuts need at least one modifier key.")
                .font(.subheadline).foregroundStyle(.secondary)
            Divider()
            settingRow("Open Stash", binding: $openShortcut)
            settingRow("Toggle recording", binding: $recordingShortcut)
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Restore defaults") { openShortcut = .openDefault; recordingShortcut = .recordDefault }
                Spacer()
                Button("Save") {
                    if openShortcut == recordingShortcut { message = "Choose different shortcuts for these actions." }
                    else if onSave(openShortcut, recordingShortcut) { message = "Saved" }
                    else { message = "macOS could not register one of these shortcuts." }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func settingRow(_ title: String, binding: Binding<HotKeyBinding>) -> some View {
        HStack {
            Text(title).font(.body.weight(.medium))
            Spacer()
            HotKeyRecorder(binding: binding)
                .frame(width: 150, height: 30)
        }
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var binding: HotKeyBinding
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onCapture = { binding = $0 }
        button.title = binding.display
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onCapture = { binding = $0 }
        if !button.isRecording { button.title = binding.display }
    }
}

final class RecorderButton: NSButton {
    var onCapture: ((HotKeyBinding) -> Void)?
    var isRecording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { isRecording = false; return }
        guard let binding = HotKeyBinding.from(event) else { NSSound.beep(); return }
        isRecording = false
        onCapture?(binding)
    }
}
