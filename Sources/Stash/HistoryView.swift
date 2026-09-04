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
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 28)
                                }
                                Text(entry.kind == .text ? (entry.preview.isEmpty ? "Empty text" : entry.preview) : "Image")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Button { model.togglePin(entry) } label: { Image(systemName: entry.isPinned ? "pin.fill" : "pin") }
                                    .buttonStyle(.borderless)
                                Button { model.delete(entry) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                            .tag(entry.id)
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedID = entry.id }
                            .onTapGesture(count: 2) { model.restore(entry) }
                            .frame(height: 38)
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 420)
                    .onChange(of: model.selectedID) { _, selectedID in
                        if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                    }
                }

                Divider()
                EntryViewer(entry: model.selectedEntry, store: model.store)
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
        .background(KeyEventMonitor { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            func matches(_ action: PanelShortcut) -> Bool {
                let binding = ShortcutStorage.binding(for: action)
                let eventModifiers: UInt32 = (event.modifierFlags.contains(.command) ? UInt32(cmdKey) : 0) | (event.modifierFlags.contains(.option) ? UInt32(optionKey) : 0) | (event.modifierFlags.contains(.control) ? UInt32(controlKey) : 0) | (event.modifierFlags.contains(.shift) ? UInt32(shiftKey) : 0)
                return UInt32(event.keyCode) == binding.keyCode && eventModifiers == binding.modifiers
            }
            if modifiers == .command, event.keyCode == UInt16(kVK_ANSI_A) {
                // SwiftUI's FocusState can lag behind the AppKit field editor in a
                // non-activating panel. Let AppKit resolve the actual responder.
                return NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
            }
            if matches(.delete) {
                model.deleteSelection()
                return true
            }
            if matches(.pin) {
                model.togglePinSelection()
                return true
            }
            if matches(.filter) {
                model.cycleFilter()
                return true
            }
            if matches(.up) { model.moveSelection(by: -1); return true }
            if matches(.down) { model.moveSelection(by: 1); return true }
            if matches(.copy) { model.restoreSelection(); return true }
            return false
        })
    }
}

extension HistoryModel {
    func storeImageURL(_ path: String) -> URL { store.imageURL(path) }
}

private struct EntryViewer: View {
    let entry: ClipboardEntry?
    let store: ClipboardStore

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.kind == .image ? "Image" : "Text").font(.headline)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Copied · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("From · \(entry.sourceApp ?? "Unknown app")")
                        Text("\(sizeDescription(for: entry)) · \(entry.copyCount == 1 ? "Copied once" : "Copied \(entry.copyCount) times")")
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

    private func sizeDescription(for entry: ClipboardEntry) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file)
        guard entry.kind == .text, let text = entry.text else { return bytes }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(text.count) characters · \(lines) \(lines == 1 ? "line" : "lines") · \(bytes)"
    }
}
