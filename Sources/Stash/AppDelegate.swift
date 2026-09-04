import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
            model.onPauseChanged = { [weak monitor, weak self] paused in
                monitor?.isPaused = paused
                self?.statusItem.menu?.items[2].title = paused ? "Resume Recording" : "Pause Recording"
            }
            monitor.onSave = { [weak model] result in
                switch result { case .saved: model?.reload(); case .full: model?.message = "History is full. Delete or unpin items to resume recording."; default: break }
            }
            self.monitor = monitor
            monitor.start()
            makeStatusItem()
            let shortcut = ShortcutManager()
            shortcut.onActivate = { [weak self] in self?.togglePanel() }
            _ = shortcut.register(optionShift: UserDefaults.standard.bool(forKey: "optionShiftShortcut"))
            self.shortcut = shortcut
        } catch { showError(error) }
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Stash clipboard history")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show History", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: shortcutTitle, action: #selector(toggleShortcut), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Stash", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func showPanel() { showPanelWindow() }
    @objc private func togglePause() { guard let model, let monitor else { return }; model.paused.toggle(); monitor.isPaused = model.paused; statusItem.menu?.items[2].title = model.paused ? "Resume Recording" : "Pause Recording" }
    @objc private func toggleShortcut() {
        let next = !UserDefaults.standard.bool(forKey: "optionShiftShortcut")
        UserDefaults.standard.set(next, forKey: "optionShiftShortcut")
        _ = shortcut?.register(optionShift: next)
        statusItem.menu?.items[3].title = shortcutTitle
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    private var shortcutTitle: String { UserDefaults.standard.bool(forKey: "optionShiftShortcut") ? "Shortcut: Option-Shift-Space" : "Shortcut: Option-Space" }
    private func togglePanel() { panel?.isVisible == true ? hidePanel() : showPanelWindow() }
    private func showPanelWindow() {
        guard let model else { return }
        model.query = ""
        model.reload()
        model.isPresented = true
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 610, height: 540), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
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
