import AppKit
import Carbon
import SwiftUI

nonisolated enum PanelShortcut: String, CaseIterable, Identifiable {
    case up, down, copy, pin, delete, filter
    var id: String { rawValue }
    static let configurable: [Self] = [.pin, .delete, .filter]
    var isConfigurable: Bool { Self.configurable.contains(self) }
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
    var keyLabel: String? = nil
    static let openDefault = HotKeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let recordDefault = HotKeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))
    var display: String {
        var result = ""
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }; if modifiers & UInt32(optionKey) != 0 { result += "⌥" }; if modifiers & UInt32(controlKey) != 0 { result += "⌃" }; if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        return result + keyName
    }
    private var keyName: String {
        let names: [UInt32: String] = [UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_Delete): "Delete", UInt32(kVK_ForwardDelete): "Forward Delete", UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Escape", UInt32(kVK_Home): "Home", UInt32(kVK_End): "End", UInt32(kVK_PageUp): "Page Up", UInt32(kVK_PageDown): "Page Down", UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R", UInt32(kVK_ANSI_X): "X"]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        if let index = functionKeys.firstIndex(of: Int(keyCode)) { return "F\(index + 1)" }
        return names[keyCode] ?? keyLabel ?? "Key \(keyCode)"
    }
    static func from(_ event: NSEvent, requiresModifier: Bool) -> HotKeyBinding? {
        let flags = event.modifierFlags; var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }; if flags.contains(.option) { modifiers |= UInt32(optionKey) }; if flags.contains(.control) { modifiers |= UInt32(controlKey) }; if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard !requiresModifier || modifiers != 0 else { return nil }
        let label = event.charactersIgnoringModifiers?.uppercased()
        let printable = label.flatMap { value in
            value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } && !value.isEmpty ? value : nil
        }
        return HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: printable)
    }
}

nonisolated enum ShortcutStorage {
    nonisolated static func binding(for action: PanelShortcut, defaults: UserDefaults = .standard) -> HotKeyBinding {
        guard action.isConfigurable,
              let data = defaults.data(forKey: "panelShortcut.\(action.rawValue)"), let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data) else { return action.defaultBinding }
        // Older configurations may have assigned an action to a now-fixed key.
        let reserved = [PanelShortcut.up, .down, .copy].map(\.defaultBinding)
        guard !reserved.contains(where: { $0.keyCode == binding.keyCode && $0.modifiers == binding.modifiers }) else { return action.defaultBinding }
        return binding
    }
    nonisolated static func save(_ binding: HotKeyBinding, for action: PanelShortcut) {
        guard action.isConfigurable else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(binding), forKey: "panelShortcut.\(action.rawValue)")
    }
}

struct ShortcutSettingsView: View {
    let model: HistoryModel
    @State private var storageLimit: Int
    @State private var retentionMinutes: Int
    @State private var openShortcut: HotKeyBinding
    @State private var recordingShortcut: HotKeyBinding
    @State private var panelBindings: [PanelShortcut: HotKeyBinding]
    @State private var error = ""
    @State private var saved = false
    let onSave: (HotKeyBinding, HotKeyBinding, [PanelShortcut: HotKeyBinding]) -> Bool
    init(model: HistoryModel, open: HotKeyBinding, recording: HotKeyBinding, panel: [PanelShortcut: HotKeyBinding], onSave: @escaping (HotKeyBinding, HotKeyBinding, [PanelShortcut: HotKeyBinding]) -> Bool) {
        self.model = model
        _storageLimit = State(initialValue: model.storageLimit)
        _retentionMinutes = State(initialValue: model.retentionMinutes)
        _openShortcut = State(initialValue: open); _recordingShortcut = State(initialValue: recording); _panelBindings = State(initialValue: panel.filter { $0.key.isConfigurable }); self.onSave = onSave
    }
    var body: some View {
        VStack(spacing: 0) {
         Form {
          Section("History") {
            Picker("Storage limit", selection: $storageLimit) {
                ForEach([25, 50, 100, 250], id: \.self) { size in Text("\(size) MB").tag(size * 1024 * 1024) }
            }
            Picker("Auto-delete", selection: $retentionMinutes) {
                Text("Never").tag(0)
                Text("After 1 hour").tag(60)
                Text("After 1 day").tag(1440)
                Text("After 1 week").tag(10080)
            }
            Text("Checks at launch and every minute. Age starts from the most recent copy. Pinned items are kept. Saving a shorter duration or lower storage limit may remove unpinned history immediately.")
                .font(.caption).foregroundStyle(.secondary)
          }
          Section {
            row("Open Stash", binding: $openShortcut, requiresModifier: true)
            row("Toggle recording", binding: $recordingShortcut, requiresModifier: true)
          } header: {
            Text("Global shortcuts")
          } footer: {
            Text("Click a shortcut, then press your preferred key combination.")
          }
          Section("History shortcuts") {
            ForEach(PanelShortcut.configurable) { action in row(action.title, binding: binding(for: action), requiresModifier: false) }
          }
         }
         .formStyle(.grouped)
         Divider()
         VStack(alignment: .leading, spacing: 8) {
            if !error.isEmpty {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Reset shortcuts") { openShortcut = .openDefault; recordingShortcut = .recordDefault; panelBindings = Dictionary(uniqueKeysWithValues: PanelShortcut.configurable.map { ($0, $0.defaultBinding) }) }
                    .modifier(StashActionStyle())
                Spacer()
                Text(saved ? "Saved" : "")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 40)
                    .accessibilityHidden(!saved)
                Button("Save changes") { save() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(saved)
            }
         }.padding(16)
        }.frame(width: 460, height: 620)
         .background(StashPanelBackground())
         .onChange(of: storageLimit) { _, _ in clearFeedback() }
         .onChange(of: retentionMinutes) { _, _ in clearFeedback() }
         .onChange(of: allBindings) { _, _ in clearFeedback() }
    }
    private var allBindings: [HotKeyBinding] { [openShortcut, recordingShortcut] + PanelShortcut.allCases.map { $0.isConfigurable ? (panelBindings[$0] ?? $0.defaultBinding) : $0.defaultBinding } }
    private func clearFeedback() { saved = false; error = "" }
    private func row(_ title: String, binding: Binding<HotKeyBinding>, requiresModifier: Bool) -> some View {
        HStack {
            Text(title).font(.body.weight(.medium))
            Spacer()
            HotKeyRecorder(binding: binding, requiresModifier: requiresModifier)
                .frame(width: 150, height: 30)
                .accessibilityLabel("\(title) shortcut")
                .accessibilityValue(binding.wrappedValue.display)
        }
    }
    private func binding(for action: PanelShortcut) -> Binding<HotKeyBinding> { Binding(get: { panelBindings[action] ?? action.defaultBinding }, set: { panelBindings[action] = $0 }) }
    private func save() {
        let all = allBindings
        guard Set(all.map { "\($0.keyCode):\($0.modifiers)" }).count == all.count else { error = "Each action needs a different shortcut."; return }
        guard onSave(openShortcut, recordingShortcut, panelBindings) else { error = "macOS could not register one of the global shortcuts."; return }
        if storageLimit != model.storageLimit { model.setStorageLimit(storageLimit) }
        if retentionMinutes != model.retentionMinutes { model.setRetentionMinutes(retentionMinutes) }
        error = ""; saved = true
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var binding: HotKeyBinding
    let requiresModifier: Bool
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onCapture = { binding = $0 }
        button.onCancel = { [weak button] in button?.title = binding.display }
        button.requiresModifier = requiresModifier
        button.toolTip = "Activate to record a shortcut. Press Escape to cancel."
        if !button.isRecording { button.title = binding.display }
    }
}
final class RecorderButton: NSButton {
    var onCapture: ((HotKeyBinding) -> Void)?; var onCancel: (() -> Void)?; var requiresModifier = false; var isRecording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { isRecording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { isRecording = false; onCancel?(); return }
        guard let binding = HotKeyBinding.from(event, requiresModifier: requiresModifier) else {
            title = "Add a modifier…"
            return
        }
        isRecording = false
        title = binding.display
        onCapture?(binding)
    }
    override func resignFirstResponder() -> Bool { let shouldRestore = isRecording; isRecording = false; if shouldRestore { onCancel?() }; return super.resignFirstResponder() }
}
