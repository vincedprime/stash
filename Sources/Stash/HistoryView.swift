import AppKit
import Carbon
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = "" { didSet { scheduleSearchReload() } }
    @Published var filter: HistoryFilter = .all { didSet { reload() } }
    @Published var entries: [ClipboardEntry] = []
    @Published var selectedID: ClipboardEntry.ID? { didSet { refreshInspector() } }
    @Published private(set) var inspectorEntry: ClipboardEntry?
    @Published private(set) var hasMore = false
    @Published var usage = 0
    @Published var paused = false
    @Published var message = ""
    @Published var isPresented = false
    @Published var storageLimit: Int
    @Published var retentionMinutes: Int
    @Published var isEditingInspector = false
    @Published var isConfirmingClear = false
    weak var historyWindow: NSWindow?
    var onShowSettings: (() -> Void)?
    let store: ClipboardStore
    var onRestore: ((ClipboardEntry) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    private var searchTask: Task<Void, Never>?
    private var retentionTimer: Timer?
    private let defaults: UserDefaults
    let previewCache = PreviewImageCache()
    static let pageSize = 100
    static let textPreviewLimit = 16_000
    private var loadedQuery = ""
    private var loadedFilter = HistoryFilter.all

    init(store: ClipboardStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        usage = store.byteUsage()
        storageLimit = store.maximumBytes
        retentionMinutes = defaults.integer(forKey: "retentionMinutes")
        applyRetention()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            // The timer is installed on the main run loop by this MainActor initializer.
            MainActor.assumeIsolated { self?.applyRetention() }
        }
        retentionTimer?.tolerance = 5
    }
    var selectedEntry: ClipboardEntry? { entries.first { $0.id == selectedID } }

    func reload() {
        searchTask?.cancel()
        usage = store.byteUsage()
        guard isPresented else { return }
        let sameSearch = loadedQuery == query && loadedFilter == filter
        let count = sameSearch ? max(Self.pageSize, entries.count) : Self.pageSize
        loadedQuery = query
        loadedFilter = filter
        let page = store.entries(query: query, filter: filter, limit: count + 1)
        hasMore = page.count > count
        entries = Array(page.prefix(count))
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
        else { refreshInspector() }
    }

    private func refreshInspector() {
        inspectorEntry = isPresented ? selectedID.flatMap { store.entry(id: $0, textLimit: Self.textPreviewLimit) } : nil
    }

    func loadNextPage(ifLast id: UUID? = nil) {
        guard isPresented, hasMore, let last = entries.last,
              id == nil || last.id == id else { return }
        // Do not append results from the old search while the debounce is pending.
        guard loadedQuery == query, loadedFilter == filter else { return }
        let page = store.entries(query: query, filter: filter, after: last, limit: Self.pageSize + 1)
        hasMore = page.count > Self.pageSize
        entries.append(contentsOf: page.prefix(Self.pageSize))
    }

    func dismiss() {
        isPresented = false
        isConfirmingClear = false
        searchTask?.cancel()
        searchTask = nil
        isEditingInspector = false
        selectedID = nil
        entries.removeAll(keepingCapacity: false)
        hasMore = false
        previewCache.removeAll()
    }

    func noteHistoryChanged() {
        usage = store.byteUsage()
        if isPresented { reload() }
    }

    func applyRetention(now: Date = Date()) {
        guard retentionMinutes > 0 else { return }
        if store.deleteEntries(before: now.addingTimeInterval(-Double(retentionMinutes) * 60)) {
            noteHistoryChanged()
        }
    }

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard let path = entry.thumbnailPath ?? entry.imagePath else { return nil }
        return previewCache.image(at: store.imageURL(path), maxPixelSize: 64)
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard let path = entry.imagePath else { return nil }
        return previewCache.image(at: store.imageURL(path), maxPixelSize: 1024)
    }

    private func scheduleSearchReload() {
        searchTask?.cancel()
        guard isPresented else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        if current + offset >= entries.count { loadNextPage() }
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
    func setRetentionMinutes(_ minutes: Int) {
        retentionMinutes = max(0, minutes)
        defaults.set(retentionMinutes, forKey: "retentionMinutes")
        applyRetention()
    }
    func deleteRecent(_ minutes: Int) { store.deleteEntries(since: Date().addingTimeInterval(-Double(minutes * 60))); reload() }
    func setTags(_ tags: String, for entry: ClipboardEntry) -> Bool {
        let saved = store.setTags(tags, for: entry)
        if saved { reload() }
        return saved
    }
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
            .alert("Delete all clipboard history?", isPresented: $model.isConfirmingClear) {
                Button("Cancel", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
                Button("Delete All", role: .destructive) { model.clear() }
            } message: {
                Text("This permanently deletes all saved entries, including pinned items. This cannot be undone.")
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                      LazyVStack(spacing: 0) {
                        ForEach(model.entries) { entry in
                            HStack(spacing: 10) {
                                if entry.kind == .image, let image = model.thumbnail(for: entry) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 28)
                                }
                                Text(entry.preview.isEmpty ? "Empty text" : entry.preview)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                if entry.isPinned {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Pinned")
                                }
                            }
                            .id(entry.id)
                            .frame(height: 38)
                            .padding(.horizontal, 10)
                            .background(model.selectedID == entry.id ? Color.gray.opacity(0.4) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.restore(entry) }
                            .onTapGesture { model.selectedID = entry.id }
                            .onAppear { model.loadNextPage(ifLast: entry.id) }
                            .accessibilityAddTraits(model.selectedID == entry.id ? [.isSelected] : [])
                            Divider()
                        }
                      }
                    }
                    .frame(width: 420)
                    .onChange(of: model.selectedID) { _, selectedID in
                        if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                }

                Divider()
                EntryViewer(entry: model.inspectorEntry, model: model)
                    .id(model.selectedID)
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
        .onChange(of: model.isEditingInspector) { _, editing in if editing { searchIsFocused = false } }
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard model.isPresented, event.window === model.historyWindow else { return false }
        guard !model.isConfirmingClear else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Let the Edit menu and native text responder handle command shortcuts.
        let standardKeys: Set<UInt16> = [UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_C), UInt16(kVK_ANSI_X), UInt16(kVK_ANSI_V), UInt16(kVK_ANSI_Z), UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_Comma)]
        if modifiers.contains(.command), standardKeys.contains(event.keyCode) { return false }
        if model.isEditingInspector { return false }
        if let editor = event.window?.firstResponder as? NSTextView, !editor.isFieldEditor {
            return false
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
            .frame(width: 320)
        }
        .padding(12)
    }

    private var statusBar: some View {
        HStack {
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(model.usage), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(model.storageLimit), countStyle: .binary))")
            Button("Clear All") { model.isConfirmingClear = true }
                .disabled(model.usage == 0)
            Menu("Delete recent") {
                Button("Last 5 minutes") { model.deleteRecent(5) }
                Button("Last hour") { model.deleteRecent(60) }
                Button("Last day") { model.deleteRecent(24 * 60) }
            }
            Spacer()
            Button { model.onShowSettings?() } label: { Image(systemName: "gearshape") }
                .help("Settings (⌘,)")
            Toggle(model.paused ? "Recording paused" : "Recording", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
                .toggleStyle(.switch).controlSize(.small)
        }
        .font(.caption).padding(10)
    }
}

private struct EntryViewer: View {
    let entry: ClipboardEntry?
    let model: HistoryModel
    @State private var editing = false
    @State private var tagging = false

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 8) {
                    if entry.kind == .image, let image = model.image(for: entry) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if entry.kind == .file {
                        FileEntryPreview(entry: entry)
                    } else if editing {
                        TextEntryEditor(entry: entry, model: model) { editing = false }
                            .id(entry.id)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if entry.kind == .color, let rgba = TextContent.rgba((entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha))
                                        .frame(height: 100)
                                        .accessibilityLabel("Colour preview")
                                }
                                Text(entry.text ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if !entry.textIsComplete {
                                    Text(entry.kind.isEditable
                                         ? "Preview shortened. Copy restores the full content; Edit opens the full text."
                                         : "Preview shortened. Copy restores the full content.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                            .frame(maxHeight: .infinity)
                    }
                    if !editing && !tagging {
                        HStack {
                            if entry.kind.isEditable { Button("Edit") { editing = true } }
                            Spacer()
                            Button((entry.tags ?? "").isEmpty ? "Add tags" : "Edit tags") { tagging = true }
                        }
                        .controlSize(.small)
                    }
                    if tagging {
                        EntryTagsEditor(entry: entry, model: model) { tagging = false }
                    }
                    Divider()
                    metadata(for: entry)
                }
            } else {
                ContentUnavailableView("Clipboard item", systemImage: "doc.on.clipboard", description: Text("Select an item to see its details."))
            }
        }
        .padding(12)
        .onChange(of: editing || tagging) { _, active in model.isEditingInspector = active }
        .onDisappear { model.isEditingInspector = false }
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
            if let tags = entry.tags, !tags.isEmpty { metadataRow("Tags", tags) }

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
    @StateObject private var session = TextEditSession()
    let onFinish: () -> Void
    @State private var error = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            FullTextEditor(entryID: entry.id, store: model.store, session: session)
                .frame(maxHeight: .infinity)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel", action: onFinish)
                Spacer()
                Button("Save") {
                    if let text = session.textView?.string, model.updateText(text, for: entry) { onFinish() }
                    else { error = "Could not save. Check the storage limit in Settings." }
                }
                .disabled(!session.hasChanges)
            }
        }
        .onExitCommand(perform: onFinish)
    }
}

private struct EntryTagsEditor: View {
    let entry: ClipboardEntry
    let model: HistoryModel
    let onFinish: () -> Void
    @State private var tags: String
    @State private var error = ""
    @FocusState private var focused: Bool

    init(entry: ClipboardEntry, model: HistoryModel, onFinish: @escaping () -> Void) {
        self.entry = entry
        self.model = model
        self.onFinish = onFinish
        _tags = State(initialValue: entry.tags ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("work, design, ideas", text: $tags)
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
            Text("Separate tags with commas. Search by any tag.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("Cancel", action: onFinish); Spacer(); Button("Save tags", action: save) }
        }
        .onAppear { focused = true }
        .onExitCommand(perform: onFinish)
    }

    private func save() {
        if model.setTags(tags, for: entry) { onFinish() }
        else { error = "Could not save tags. Try again." }
    }
}
