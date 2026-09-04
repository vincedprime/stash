import AppKit

@MainActor
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    var isPaused = false
    var onSave: ((SaveResult) -> Void)?

    init(store: ClipboardStore) { self.store = store }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readPasteboard() }
        }
    }

    private func readPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard !isPaused else { onSave?(.paused); return }
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let result: SaveResult
        if let string = pasteboard.string(forType: .string) { result = store.saveText(string, sourceApp: sourceApp) }
        else if let image = NSImage(pasteboard: pasteboard) { result = store.saveImage(image, sourceApp: sourceApp) }
        else { return }
        onSave?(result)
    }
}
