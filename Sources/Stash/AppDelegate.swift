import AppKit
import SwiftUI

final class HistoryPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override func resignKey() { super.resignKey(); onResignKey?() }
    override func resignMain() { super.resignMain(); onResignKey?() }
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
            model.onDismiss = { [weak self] in self?.hidePanel() }
            model.onShowSettings = { [weak self] in self?.showSettings() }
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
            makeApplicationMenu()
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
        let limit = ByteCountFormatter.string(fromByteCount: Int64(model?.storageLimit ?? ClipboardStore.defaultMaximumBytes), countStyle: .binary)
        let memory = menu.addItem(withTitle: "Storage  \(used) / \(limit)", action: nil, keyEquivalent: "")
        memory.isEnabled = false

        let recording = menu.addItem(withTitle: model?.paused == true ? "Resume recording" : "Pause recording", action: #selector(toggleRecording), keyEquivalent: "")
        recording.target = self
        recording.state = model?.paused == true ? .off : .on
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    func menuWillOpen(_ menu: NSMenu) { hidePanel() }

    @objc private func showSettings() {
        guard let model else { return }
        hidePanel()
        if let settingsPanel, settingsPanel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            settingsPanel.makeKeyAndOrderFront(nil)
            return
        }
        let panelBindings = Dictionary(uniqueKeysWithValues: PanelShortcut.configurable.map { ($0, ShortcutStorage.binding(for: $0)) })
        let view = ShortcutSettingsView(model: model, open: openBinding, recording: recordingBinding, panel: panelBindings) { [weak self] open, record, panel in
            guard let self, self.shortcut?.register(open: open, record: record) == true else { return false }
            self.save(open, forKey: "openShortcut")
            self.save(record, forKey: "recordShortcut")
            panel.forEach { ShortcutStorage.save($0.value, for: $0.key) }
            model.refreshShortcutBindings()
            return true
        }
        if settingsPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Stash Settings"
            panel.titlebarAppearsTransparent = true
            panel.titlebarSeparatorStyle = .none
            panel.isFloatingPanel = false
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
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
    func makeApplicationMenu() {
        let mainMenu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu(title: "Stash")
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(withTitle: "Quit Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        mainMenu.addItem(app)
        // AppKit routes these through the responder chain to search, tags, or the editor.
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
    }
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
        model.applyRetention()
        model.query = ""
        model.selectedID = nil
        model.isPresented = true
        model.reload()
        if panel == nil {
            let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 540), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Stash"
            panel.animationBehavior = .none
            panel.titlebarAppearsTransparent = true
            panel.titlebarSeparatorStyle = .none
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.transient]
            panel.delegate = self
            panel.onResignKey = { [weak self] in self?.hidePanel() }
            self.panel = panel
            model.historyWindow = panel
        }
        panel?.contentView = NSHostingView(rootView: HistoryView(model: model))
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel?.center(); panel?.makeKeyAndOrderFront(nil)
    }
    private func hidePanel() {
        guard model?.isPresented == true else { return }
        // The confirmation takes keyboard focus; keep its parent panel alive.
        guard model?.isConfirmingClear != true else { return }
        model?.dismiss()
        panel?.orderOut(nil)
        // Release SwiftUI's retained row images, text layout, and editor undo state.
        panel?.contentView = nil
    }
    func windowDidResignKey(_ notification: Notification) { hidePanel() }
    private func showError(_ error: Error) { let alert = NSAlert(error: error); alert.runModal(); NSApplication.shared.terminate(nil) }
}
