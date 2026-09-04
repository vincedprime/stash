import AppKit
import Carbon
import SwiftUI

nonisolated enum PanelShortcut: String, CaseIterable, Identifiable {
    case up, down, copy, pin, delete, filter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .up: "Move up"; case .down: "Move down"; case .copy: "Copy selected"; case .pin: "Pin selected"; case .delete: "Delete selected"; case .filter: "Cycle filter"
        }
    }
    var defaultBinding: HotKeyBinding {
        switch self {
        case .up: HotKeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: 0)
        case .down: HotKeyBinding(keyCode: UInt32(kVK_DownArrow), modifiers: 0)
        case .copy: HotKeyBinding(keyCode: UInt32(kVK_Return), modifiers: 0)
        case .pin: HotKeyBinding(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey))
        case .delete: HotKeyBinding(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(optionKey))
        case .filter: HotKeyBinding(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(optionKey))
        }
    }
}

nonisolated struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let openDefault = HotKeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let recordDefault = HotKeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))
    var display: String {
        var result = ""
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }; if modifiers & UInt32(optionKey) != 0 { result += "⌥" }; if modifiers & UInt32(controlKey) != 0 { result += "⌃" }; if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        return result + keyName
    }
    private var keyName: String {
        let names: [UInt32: String] = [UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓", UInt32(kVK_Delete): "Delete", UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_X): "X"]
        return names[keyCode] ?? "Key"
    }
    static func from(_ event: NSEvent, requiresModifier: Bool) -> HotKeyBinding? {
        let flags = event.modifierFlags; var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }; if flags.contains(.option) { modifiers |= UInt32(optionKey) }; if flags.contains(.control) { modifiers |= UInt32(controlKey) }; if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard !requiresModifier || modifiers != 0 else { return nil }
        return HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }
}

nonisolated enum ShortcutStorage {
    nonisolated static func binding(for action: PanelShortcut) -> HotKeyBinding {
        guard let data = UserDefaults.standard.data(forKey: "panelShortcut.\(action.rawValue)"), let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data) else { return action.defaultBinding }
        return binding
    }
    nonisolated static func save(_ binding: HotKeyBinding, for action: PanelShortcut) { UserDefaults.standard.set(try? JSONEncoder().encode(binding), forKey: "panelShortcut.\(action.rawValue)") }
}

struct ShortcutSettingsView: View {
    @State private var openShortcut: HotKeyBinding
    @State private var recordingShortcut: HotKeyBinding
    @State private var panelBindings: [PanelShortcut: HotKeyBinding]
    @State private var error = ""
    @State private var saved = false
    let onSave: (HotKeyBinding, HotKeyBinding, [PanelShortcut: HotKeyBinding]) -> Bool
    init(open: HotKeyBinding, recording: HotKeyBinding, panel: [PanelShortcut: HotKeyBinding], onSave: @escaping (HotKeyBinding, HotKeyBinding, [PanelShortcut: HotKeyBinding]) -> Bool) {
        _openShortcut = State(initialValue: open); _recordingShortcut = State(initialValue: recording); _panelBindings = State(initialValue: panel); self.onSave = onSave
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title2.weight(.semibold))
            Text("Click a shortcut, then press your preferred key combination.").font(.subheadline).foregroundStyle(.secondary)
            Divider()
            Text("Global shortcuts").font(.headline)
            row("Open Stash", binding: $openShortcut, requiresModifier: true)
            row("Toggle recording", binding: $recordingShortcut, requiresModifier: true)
            Divider()
            Text("History shortcuts").font(.headline)
            ForEach(PanelShortcut.allCases) { action in row(action.title, binding: binding(for: action), requiresModifier: false) }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("Restore defaults") { openShortcut = .openDefault; recordingShortcut = .recordDefault; panelBindings = Dictionary(uniqueKeysWithValues: PanelShortcut.allCases.map { ($0, $0.defaultBinding) }) }; Spacer(); Button(saved ? "Saved" : "Save changes") { save() }.keyboardShortcut(.defaultAction) }
        }.padding(22).frame(width: 440)
    }
    private func row(_ title: String, binding: Binding<HotKeyBinding>, requiresModifier: Bool) -> some View { HStack { Text(title).font(.body.weight(.medium)); Spacer(); HotKeyRecorder(binding: binding, requiresModifier: requiresModifier).frame(width: 150, height: 30) } }
    private func binding(for action: PanelShortcut) -> Binding<HotKeyBinding> { Binding(get: { panelBindings[action] ?? action.defaultBinding }, set: { panelBindings[action] = $0 }) }
    private func save() {
        let all = [openShortcut, recordingShortcut] + PanelShortcut.allCases.map { panelBindings[$0] ?? $0.defaultBinding }
        guard Set(all.map { "\($0.keyCode):\($0.modifiers)" }).count == all.count else { error = "Each action needs a different shortcut."; return }
        guard onSave(openShortcut, recordingShortcut, panelBindings) else { error = "macOS could not register one of the global shortcuts."; return }
        error = ""; saved = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { saved = false }
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var binding: HotKeyBinding
    let requiresModifier: Bool
    func makeNSView(context: Context) -> RecorderButton { let button = RecorderButton(); button.onCapture = { binding = $0 }; button.onCancel = { button.title = binding.display }; button.requiresModifier = requiresModifier; button.title = binding.display; return button }
    func updateNSView(_ button: RecorderButton, context: Context) { button.onCapture = { binding = $0 }; button.onCancel = { button.title = binding.display }; button.requiresModifier = requiresModifier; if !button.isRecording { button.title = binding.display } }
}
final class RecorderButton: NSButton {
    var onCapture: ((HotKeyBinding) -> Void)?; var onCancel: (() -> Void)?; var requiresModifier = false; var isRecording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { isRecording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { if event.keyCode == UInt16(kVK_Escape) { isRecording = false; return }; guard let binding = HotKeyBinding.from(event, requiresModifier: requiresModifier) else { NSSound.beep(); return }; isRecording = false; onCapture?(binding) }
    override func resignFirstResponder() -> Bool { let shouldRestore = isRecording; isRecording = false; if shouldRestore { onCancel?() }; return super.resignFirstResponder() }
}
