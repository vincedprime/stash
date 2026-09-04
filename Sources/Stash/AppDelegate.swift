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
            _ = shortcut.register(optionShift: UserDefaults.standard.bool(forKey: "optionShiftShortcut"))
            self.shortcut = shortcut
        } catch { showError(error) }
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Stash clipboard history")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
    }

    @objc private func togglePanel() { panel?.isVisible == true ? hidePanel() : showPanelWindow() }
    private func showPanelWindow() {
        guard let model else { return }
        model.query = ""
        model.selectedID = nil
        model.reload()
        model.isPresented = true
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
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
