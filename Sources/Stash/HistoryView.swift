import AppKit
import Carbon
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = "" { didSet { reload() } }
    @Published var filter: HistoryFilter = .all { didSet { reload() } }
    @Published var entries: [ClipboardEntry] = []
    @Published var selectedID: ClipboardEntry.ID?
    @Published var usage = 0
    @Published var paused = false
    @Published var message = ""
    @Published var isPresented = false
    let store: ClipboardStore
    var onRestore: ((ClipboardEntry) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    init(store: ClipboardStore) { self.store = store; reload() }
    var selectedEntry: ClipboardEntry? { entries.first { $0.id == selectedID } }

    func reload() {
        entries = store.entries(query: query, filter: filter)
        usage = store.byteUsage()
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
    }

    func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        selectedID = entries[max(0, min(entries.count - 1, current + offset))].id
    }

    func restoreSelection() { if let selectedEntry { restore(selectedEntry) } }
    func deleteSelection() { if let selectedEntry { delete(selectedEntry) } }
    func cycleFilter() {
        guard let index = HistoryFilter.allCases.firstIndex(of: filter) else { return }
        filter = HistoryFilter.allCases[(index + 1) % HistoryFilter.allCases.count]
    }
    func setPaused(_ paused: Bool) { self.paused = paused; onPauseChanged?(paused) }
    func restore(_ entry: ClipboardEntry) { store.restore(entry); onRestore?(entry) }
    func togglePin(_ entry: ClipboardEntry) { store.setPinned(entry, pinned: !entry.isPinned); reload() }
    func delete(_ entry: ClipboardEntry) { store.delete(entry); reload() }
    func clear() { store.clear(); reload() }
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
        VStack(spacing: 0) {
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
                .frame(width: 210)
            }
            .padding(12)

            Divider()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.entries) { entry in
                            HStack(spacing: 10) {
                                if entry.kind == .image, let path = entry.imagePath,
                                   let image = NSImage(contentsOf: model.storeImageURL(path)) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 36)
                                }
                                Text(entry.kind == .text ? (entry.preview.isEmpty ? "Empty text" : entry.preview) : "Image")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Button { model.togglePin(entry) } label: { Image(systemName: entry.isPinned ? "pin.fill" : "pin") }
                                    .buttonStyle(.borderless)
                                Button { model.delete(entry) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                            .tag(entry.id)
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .background(model.selectedID == entry.id ? Color.accentColor.opacity(0.20) : Color.clear)
                            .onTapGesture { model.selectedID = entry.id }
                            .onTapGesture(count: 2) { model.restore(entry) }
                            .frame(height: 46)
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 420)
                    .onChange(of: model.selectedID) { _, selectedID in
                        if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                }

                Divider()
                EntryViewer(entry: model.selectedEntry, store: model.store, onTogglePin: model.togglePin)
                    .frame(width: 320)
            }

            Divider()
            HStack {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(model.usage), countStyle: .file)) / 50 MB")
                Button("Clear All") { model.clear() }
                Spacer()
                Toggle(model.paused ? "Recording paused" : "Recording", isOn: Binding(
                    get: { model.paused },
                    set: { model.setPaused($0) }
                ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .font(.caption)
            .padding(10)
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).padding(.bottom, 8) }
        }
        .frame(width: 740, height: 540)
        .onAppear { searchIsFocused = true }
        .onChange(of: model.isPresented) { _, isPresented in if isPresented { searchIsFocused = true } }
        .background(KeyEventMonitor { event in
            let isOptionOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            if isOptionOnly, event.keyCode == UInt16(kVK_ANSI_X) {
                model.deleteSelection()
                return true
            }
            if isOptionOnly, event.keyCode == UInt16(kVK_ANSI_Q) {
                model.cycleFilter()
                return true
            }
            switch event.keyCode {
            case UInt16(kVK_UpArrow): model.moveSelection(by: -1); return true
            case UInt16(kVK_DownArrow): model.moveSelection(by: 1); return true
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter): model.restoreSelection(); return true
            default: return false
            }
        })
    }
}

extension HistoryModel {
    func storeImageURL(_ path: String) -> URL { store.imageURL(path) }
}

private struct EntryViewer: View {
    let entry: ClipboardEntry?
    let store: ClipboardStore
    let onTogglePin: (ClipboardEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(entry.kind == .image ? "Image" : "Text").font(.headline)
                        Spacer()
                        Button { onTogglePin(entry) } label: {
                            Label(entry.isPinned ? "Pinned" : "Pin", systemImage: entry.isPinned ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.borderless)
                    }
                    Grid(alignment: .leading, verticalSpacing: 6) {
                        metadataRow("Copied", entry.createdAt.formatted(date: .long, time: .shortened))
                        metadataRow("From", entry.sourceApp ?? "Unknown app")
                        metadataRow("Size", sizeDescription(for: entry))
                        metadataRow("Copies", entry.copyCount == 1 ? "Once" : "\(entry.copyCount) times")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    if entry.kind == .image, let path = entry.imagePath,
                       let image = NSImage(contentsOf: store.imageURL(path)) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(entry.text ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Clipboard item", systemImage: "doc.on.clipboard", description: Text("Select an item to see its details."))
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.tertiary)
            Text(value).lineLimit(1).truncationMode(.tail)
        }
    }

    private func sizeDescription(for entry: ClipboardEntry) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file)
        guard entry.kind == .text, let text = entry.text else { return bytes }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(text.count) characters · \(lines) \(lines == 1 ? "line" : "lines") · \(bytes)"
    }
}
