import AppKit
import SwiftUI

final class HistoryPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override func resignKey() { super.resignKey(); onResignKey?() }
    override func resignMain() { super.resignMain(); onResignKey?() }
}

final class TransientPanel: NSPanel {
    override func resignKey() { super.resignKey(); orderOut(nil) }
    override func resignMain() { super.resignMain(); orderOut(nil) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var monitor: ClipboardMonitor?
    private var model: HistoryModel?
    private var shortcut: ShortcutManager?
    private var settingsPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try ClipboardStore()
            let model = HistoryModel(store: store)
            model.onRestore = { [weak self] _ in self?.hidePanel() }
            self.model = model
            let monitor = ClipboardMonitor(store: store)
            model.onPauseChanged = { [weak monitor] paused in
                monitor?.isPaused = paused
            }
            monitor.onSave = { [weak model] result in
                switch result { case .saved: model?.noteHistoryChanged(); case .full: model?.message = "History is full. Delete or unpin items to resume recording."; default: break }
            }
            self.monitor = monitor
            monitor.start()
            makeStatusItem()
            let shortcut = ShortcutManager()
            shortcut.onActivate = { [weak self] in self?.togglePanel() }
            shortcut.onToggleRecording = { [weak self] in self?.toggleRecording() }
            _ = shortcut.register(open: openBinding, record: recordingBinding)
            self.shortcut = shortcut
        } catch { showError(error) }
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Stash clipboard history")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let showItem = menu.addItem(withTitle: "Show Stash", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self

        let used = model.map { ByteCountFormatter.string(fromByteCount: Int64($0.usage), countStyle: .file) } ?? "0 bytes"
        let memory = menu.addItem(withTitle: "Memory  \(used) / 50 MB", action: nil, keyEquivalent: "")
        memory.isEnabled = false

        let recording = menu.addItem(withTitle: model?.paused == true ? "Resume recording" : "Pause recording", action: #selector(toggleRecording), keyEquivalent: "")
        recording.target = self
        recording.state = model?.paused == true ? .off : .on
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    func menuWillOpen(_ menu: NSMenu) { hidePanel(); settingsPanel?.orderOut(nil) }

    @objc private func showSettings() {
        let panelBindings = Dictionary(uniqueKeysWithValues: PanelShortcut.allCases.map { ($0, ShortcutStorage.binding(for: $0)) })
        let view = ShortcutSettingsView(open: openBinding, recording: recordingBinding, panel: panelBindings) { [weak self] open, record, panel in
            guard let self, self.shortcut?.register(open: open, record: record) == true else { return false }
            self.save(open, forKey: "openShortcut")
            self.save(record, forKey: "recordShortcut")
            panel.forEach { ShortcutStorage.save($0.value, for: $0.key) }
            return true
        }
        if settingsPanel == nil {
            let panel = TransientPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 250), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Stash Settings"
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.transient]
            panel.contentView = NSHostingView(rootView: view)
            settingsPanel = panel
        } else {
            settingsPanel?.contentView = NSHostingView(rootView: view)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel?.center()
        settingsPanel?.makeKeyAndOrderFront(nil)
    }

    private var openBinding: HotKeyBinding { binding(forKey: "openShortcut", fallback: .openDefault) }
    private var recordingBinding: HotKeyBinding { binding(forKey: "recordShortcut", fallback: .recordDefault) }
    private func binding(forKey key: String, fallback: HotKeyBinding) -> HotKeyBinding {
        guard let data = UserDefaults.standard.data(forKey: key), let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data) else { return fallback }
        return binding
    }
    private func save(_ binding: HotKeyBinding, forKey key: String) { UserDefaults.standard.set(try? JSONEncoder().encode(binding), forKey: key) }

    @objc private func toggleRecording() { guard let model else { return }; model.setPaused(!model.paused) }

    @objc private func togglePanel() { panel?.isVisible == true ? hidePanel() : showPanelWindow() }
    private func showPanelWindow() {
        guard let model else { return }
        model.query = ""
        model.selectedID = nil
        model.reload()
        model.isPresented = true
        if panel == nil {
            let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 540), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Stash"
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.transient]
            panel.delegate = self
            panel.onResignKey = { [weak self] in self?.hidePanel() }
            panel.contentView = NSHostingView(rootView: HistoryView(model: model))
            self.panel = panel
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel?.center(); panel?.makeKeyAndOrderFront(nil)
    }
    private func hidePanel() { model?.isPresented = false; panel?.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { hidePanel() }
    private func showError(_ error: Error) { let alert = NSAlert(error: error); alert.runModal(); NSApplication.shared.terminate(nil) }
}
