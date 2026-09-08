import AppKit
import Carbon
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = "" { didSet { scheduleSearchReload() } }
    @Published var filter: HistoryFilter = .all { didSet { reload() } }
    @Published var entries: [ClipboardEntry] = []
    @Published var selectedID: ClipboardEntry.ID?
    @Published var usage = 0
    @Published var paused = false
    @Published var message = ""
    @Published var isPresented = false
    @Published var storageLimit: Int
    @Published var retentionMinutes: Int
    let store: ClipboardStore
    var onRestore: ((ClipboardEntry) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    private var searchTask: Task<Void, Never>?
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let imageCache = NSCache<NSString, NSImage>()

    init(store: ClipboardStore) {
        self.store = store
        usage = store.byteUsage()
        storageLimit = store.maximumBytes
        retentionMinutes = UserDefaults.standard.integer(forKey: "retentionMinutes")
        thumbnailCache.countLimit = 160
        imageCache.countLimit = 3
    }
    var selectedEntry: ClipboardEntry? { entries.first { $0.id == selectedID } }

    func reload() {
        searchTask?.cancel()
        entries = store.entries(query: query, filter: filter)
        usage = store.byteUsage()
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
    }

    func noteHistoryChanged() {
        if retentionMinutes > 0 { store.deleteEntries(before: Date().addingTimeInterval(-Double(retentionMinutes * 60))) }
        usage = store.byteUsage()
        if isPresented { reload() }
    }

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard let path = entry.thumbnailPath ?? entry.imagePath else { return nil }
        let key = path as NSString
        if let image = thumbnailCache.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: store.imageURL(path)) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard let path = entry.imagePath else { return nil }
        let key = path as NSString
        if let image = imageCache.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: store.imageURL(path)) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    private func scheduleSearchReload() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        selectedID = entries[max(0, min(entries.count - 1, current + offset))].id
    }

    func restoreSelection() { if let selectedEntry { restore(selectedEntry) } }
    func copySelection() { if let selectedEntry { store.restore(selectedEntry) } }
    func deleteSelection() { if let selectedEntry { delete(selectedEntry) } }
    func togglePinSelection() { if let selectedEntry { togglePin(selectedEntry) } }
    func cycleFilter() {
        guard let index = HistoryFilter.allCases.firstIndex(of: filter) else { return }
        filter = HistoryFilter.allCases[(index + 1) % HistoryFilter.allCases.count]
    }
    func setPaused(_ paused: Bool) { self.paused = paused; onPauseChanged?(paused) }
    func restore(_ entry: ClipboardEntry) { store.restore(entry); onRestore?(entry) }
    func togglePin(_ entry: ClipboardEntry) { store.setPinned(entry, pinned: !entry.isPinned); reload() }
    func delete(_ entry: ClipboardEntry) {
        let deletedIndex = entries.firstIndex { $0.id == entry.id }
        let deletedWasSelected = selectedID == entry.id
        store.delete(entry)
        reload()

        // Keep keyboard flow contiguous: select the item that replaced the deleted
        // row, or the preceding row when the deleted item was the last one.
        guard deletedWasSelected, let deletedIndex, !entries.isEmpty else { return }
        selectedID = entries[min(deletedIndex, entries.count - 1)].id
    }
    func clear() { store.clear(); reload() }
    func setStorageLimit(_ bytes: Int) { store.setMaximumBytes(bytes); storageLimit = bytes; reload() }
    func setRetentionMinutes(_ minutes: Int) { retentionMinutes = minutes; UserDefaults.standard.set(minutes, forKey: "retentionMinutes"); if minutes > 0 { store.deleteEntries(before: Date().addingTimeInterval(-Double(minutes * 60))); reload() } }
    func deleteRecent(_ minutes: Int) { store.deleteEntries(since: Date().addingTimeInterval(-Double(minutes * 60))); reload() }
    func setTags(_ tags: String, for entry: ClipboardEntry) { store.setTags(tags, for: entry); reload() }
    func updateText(_ text: String, for entry: ClipboardEntry) -> Bool { let saved = store.updateText(text, for: entry); if saved { reload() }; return saved }
}

struct KeyEventMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(handler: handler) }
    func makeNSView(context: Context) -> NSView { context.coordinator.install(); return NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.handler = handler }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) { self.handler = handler }
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handler(event) ? nil : event
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        content
            .background(KeyEventMonitor(handler: handleKeyEvent))
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.entries) { entry in
                            HStack(spacing: 10) {
                                if entry.kind == .image, let image = model.thumbnail(for: entry) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 28)
                                }
                                Text(entry.kind == .text ? (entry.preview.isEmpty ? "Empty text" : entry.preview) : "Image")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                if entry.isPinned {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Pinned")
                                }
                            }
                            .tag(entry.id)
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedID = entry.id }
                            .onTapGesture(count: 2) { model.restore(entry) }
                            .frame(height: 38)
                            .listRowBackground(model.selectedID == entry.id ? Color.accentColor.opacity(0.82) : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 420)
                    .onChange(of: model.selectedID) { _, selectedID in
                        if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                }

                Divider()
                EntryViewer(entry: model.selectedEntry, model: model)
                    .frame(width: 320)
            }

            Divider()
            statusBar
            Divider()
            HStack(spacing: 14) {
                Text("Shortcuts")
                Text("↑↓ Navigate")
                Text("↩ Copy")
                Text("⌥P Pin")
                Text("⌥X Delete")
                Text("⌥Q Filter")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).padding(.bottom, 8) }
        }
        .frame(width: 740, height: 540)
        .onAppear { searchIsFocused = true }
        .onChange(of: model.isPresented) { _, isPresented in if isPresented { searchIsFocused = true } }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command {
            let selector: Selector? = switch event.keyCode {
            case UInt16(kVK_ANSI_A): #selector(NSResponder.selectAll(_:)); case UInt16(kVK_ANSI_C): Selector(("copy:")); case UInt16(kVK_ANSI_X): Selector(("cut:")); case UInt16(kVK_ANSI_V): Selector(("paste:")); case UInt16(kVK_ANSI_Z): event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:")); default: nil
            }
            if let selector { return NSApp.sendAction(selector, to: nil, from: nil) }
        }
        for action in PanelShortcut.allCases where matches(event, action) {
            switch action { case .delete: model.deleteSelection(); case .pin: model.togglePinSelection(); case .filter: model.cycleFilter(); case .up: model.moveSelection(by: -1); case .down: model.moveSelection(by: 1); case .copy: model.restoreSelection() }
            return true
        }
        return false
    }

    private func matches(_ event: NSEvent, _ action: PanelShortcut) -> Bool {
        let binding = ShortcutStorage.binding(for: action)
        let flags = event.modifierFlags
        let modifiers: UInt32 = (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0) | (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
        return UInt32(event.keyCode) == binding.keyCode && modifiers == binding.modifiers
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .onSubmit { model.restoreSelection() }
            Picker("", selection: $model.filter) {
                ForEach(HistoryFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(12)
    }

    private var statusBar: some View {
        HStack {
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(model.usage), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(model.storageLimit), countStyle: .file))")
            Button("Clear All") { model.clear() }
            Menu("Delete recent") {
                Button("Last 5 minutes") { model.deleteRecent(5) }
                Button("Last hour") { model.deleteRecent(60) }
                Button("Last day") { model.deleteRecent(24 * 60) }
            }
            Menu("Storage") { ForEach([25, 50, 100, 250], id: \.self) { size in Button("\(size) MB") { model.setStorageLimit(size * 1024 * 1024) } } }
            Menu("Auto-delete") {
                Button("Never") { model.setRetentionMinutes(0) }
                Button("After 1 hour") { model.setRetentionMinutes(60) }
                Button("After 1 day") { model.setRetentionMinutes(24 * 60) }
                Button("After 1 week") { model.setRetentionMinutes(7 * 24 * 60) }
            }
            Spacer()
            Toggle(model.paused ? "Recording paused" : "Recording", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
                .toggleStyle(.switch).controlSize(.small)
        }
        .font(.caption).padding(10)
    }
}

private struct EntryViewer: View {
    let entry: ClipboardEntry?
    let model: HistoryModel

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.kind.title).font(.headline)
                        Spacer()
                        Button("Copy") { model.copySelection() }
                    }
                    if entry.kind == .image, let image = model.image(for: entry) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if entry.kind == .text {
                        TextEntryEditor(entry: entry, model: model)
                            .id(entry.id)
                    } else {
                        ScrollView { Text(entry.text ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: .infinity)
                    }
                    Divider()
                    metadata(for: entry)
                }
            } else {
                ContentUnavailableView("Clipboard item", systemImage: "doc.on.clipboard", description: Text("Select an item to see its details."))
            }
        }
        .padding(12)
    }

    private func sizeDescription(for entry: ClipboardEntry) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file)
    }

    @ViewBuilder
    private func metadata(for entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            metadataRow("Copied", entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            metadataRow("From", entry.sourceApp ?? "Unknown app")
            metadataRow("Size", sizeDescription(for: entry))
            metadataRow("Copies", entry.copyCount == 1 ? "Once" : "\(entry.copyCount) times")
            metadataRow("Type", entry.kind.title)
            TextField("Tags (comma separated)", text: Binding(
                get: { entry.tags ?? "" },
                set: { model.setTags($0, for: entry) }
            ))
            .textFieldStyle(.roundedBorder)

            if entry.kind == .image {
                if let width = entry.pixelWidth, let height = entry.pixelHeight, width > 0, height > 0 {
                    metadataRow("Dimensions", "\(width) × \(height) px")
                    metadataRow("Aspect ratio", aspectRatio(width: width, height: height))
                }
                metadataRow("Format", entry.imageFormat ?? "Unknown")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).frame(width: 76, alignment: .leading)
            Text(value).foregroundStyle(.primary)
        }
    }

    private func aspectRatio(width: Int, height: Int) -> String {
        let divisor = greatestCommonDivisor(width, height)
        return "\(width / divisor):\(height / divisor)"
    }

    private func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
        var left = left
        var right = right
        while right != 0 {
            let remainder = left % right
            left = right
            right = remainder
        }
        return left
    }
}

private struct TextEntryEditor: View {
    let entry: ClipboardEntry
    let model: HistoryModel
    @State private var text: String
    @State private var saved = false

    init(entry: ClipboardEntry, model: HistoryModel) {
        self.entry = entry
        self.model = model
        _text = State(initialValue: entry.text ?? "")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $text).font(.body.monospaced()).frame(maxHeight: .infinity)
            Button(saved ? "Saved" : "Save edit") { saved = model.updateText(text, for: entry) }
                .disabled(text == entry.text || text.isEmpty)
        }
    }
}
