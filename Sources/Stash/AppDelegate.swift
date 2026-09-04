import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var monitor: ClipboardMonitor?
    private var model: HistoryModel?
    private var shortcut: ShortcutManager?

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
                switch result { case .saved: model?.reload(); case .full: model?.message = "History is full. Delete or unpin items to resume recording."; default: break }
            }
            self.monitor = monitor
            monitor.start()
            makeStatusItem()
            let shortcut = ShortcutManager()
            shortcut.onActivate = { [weak self] in self?.togglePanel() }
            shortcut.onToggleRecording = { [weak self] in self?.toggleRecording() }
            _ = shortcut.register(
                openOptionShift: UserDefaults.standard.bool(forKey: "optionShiftShortcut"),
                recordOptionShift: UserDefaults.standard.bool(forKey: "optionShiftRecordShortcut")
            )
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

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        let openShortcut = NSMenuItem(title: "Open Stash shortcut", action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        let optionSpace = shortcutMenu.addItem(withTitle: "Option-Space", action: #selector(setOpenShortcut(_:)), keyEquivalent: "")
        optionSpace.target = self
        optionSpace.representedObject = false
        let optionShiftSpace = shortcutMenu.addItem(withTitle: "Option-Shift-Space", action: #selector(setOpenShortcut(_:)), keyEquivalent: "")
        optionShiftSpace.target = self
        optionShiftSpace.representedObject = true
        let usesShift = UserDefaults.standard.bool(forKey: "optionShiftShortcut")
        optionSpace.state = usesShift ? .off : .on
        optionShiftSpace.state = usesShift ? .on : .off
        openShortcut.submenu = shortcutMenu
        settingsMenu.addItem(openShortcut)

        let recordShortcut = NSMenuItem(title: "Toggle recording shortcut", action: nil, keyEquivalent: "")
        let recordMenu = NSMenu()
        let optionR = recordMenu.addItem(withTitle: "Option-R", action: #selector(setRecordShortcut(_:)), keyEquivalent: "")
        optionR.target = self
        optionR.representedObject = false
        let optionShiftR = recordMenu.addItem(withTitle: "Option-Shift-R", action: #selector(setRecordShortcut(_:)), keyEquivalent: "")
        optionShiftR.target = self
        optionShiftR.representedObject = true
        let recordUsesShift = UserDefaults.standard.bool(forKey: "optionShiftRecordShortcut")
        optionR.state = recordUsesShift ? .off : .on
        optionShiftR.state = recordUsesShift ? .on : .off
        recordShortcut.submenu = recordMenu
        settingsMenu.addItem(recordShortcut)
        settings.submenu = settingsMenu
        menu.addItem(settings)

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

    @objc private func setOpenShortcut(_ sender: NSMenuItem) {
        let optionShift = sender.representedObject as? Bool ?? false
        guard shortcut?.register(openOptionShift: optionShift, recordOptionShift: UserDefaults.standard.bool(forKey: "optionShiftRecordShortcut")) == true else {
            model?.message = "macOS could not register that shortcut. Choose a different one."
            return
        }
        UserDefaults.standard.set(optionShift, forKey: "optionShiftShortcut")
    }

    @objc private func setRecordShortcut(_ sender: NSMenuItem) {
        let optionShift = sender.representedObject as? Bool ?? false
        guard shortcut?.register(openOptionShift: UserDefaults.standard.bool(forKey: "optionShiftShortcut"), recordOptionShift: optionShift) == true else {
            model?.message = "macOS could not register that shortcut. Choose a different one."
            return
        }
        UserDefaults.standard.set(optionShift, forKey: "optionShiftRecordShortcut")
    }

    @objc private func toggleRecording() { guard let model else { return }; model.setPaused(!model.paused) }

    @objc private func togglePanel() { panel?.isVisible == true ? hidePanel() : showPanelWindow() }
    private func showPanelWindow() {
        guard let model else { return }
        model.query = ""
        model.selectedID = nil
        model.reload()
        model.isPresented = true
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 540), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Stash"
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.delegate = self
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
