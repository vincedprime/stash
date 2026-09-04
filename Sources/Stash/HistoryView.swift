import AppKit
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var query = "" { didSet { reload() } }
    @Published var entries: [ClipboardEntry] = []
    @Published var usage = 0
    @Published var paused = false
    @Published var message = ""
    let store: ClipboardStore
    var onRestore: ((ClipboardEntry) -> Void)?

    init(store: ClipboardStore) { self.store = store; reload() }
    func reload() { entries = store.entries(query: query); usage = store.byteUsage() }
    func restore(_ entry: ClipboardEntry) { store.restore(entry); onRestore?(entry) }
    func togglePin(_ entry: ClipboardEntry) { store.setPinned(entry, pinned: !entry.isPinned); reload() }
    func delete(_ entry: ClipboardEntry) { store.delete(entry); reload() }
    func clear() { store.clear(); reload() }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "archivebox")
                TextField("Search clipboard", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Toggle("Pause", isOn: $model.paused).labelsHidden()
            }.padding(12)
            Divider()
            List(model.entries) { entry in
                Button { model.restore(entry) } label: {
                    HStack(spacing: 10) {
                        if entry.kind == .image, let path = entry.imagePath,
                           let image = NSImage(contentsOf: model.storeImageURL(path)) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 44, height: 32)
                        } else { Image(systemName: entry.kind == .text ? "doc.text" : "photo") }
                        VStack(alignment: .leading) {
                            Text(entry.preview.isEmpty ? "Empty text" : entry.preview).lineLimit(2)
                            Text(entry.isPinned ? "Pinned" : entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.togglePin(entry) } label: { Image(systemName: entry.isPinned ? "pin.fill" : "pin") }.buttonStyle(.borderless)
                        Button { model.delete(entry) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }.buttonStyle(.plain)
            }.listStyle(.plain)
            Divider()
            HStack {
                Text(model.paused ? "Recording paused" : "Recording all clipboard changes")
                Spacer()
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(model.usage), countStyle: .file)) / 50 MB")
                Button("Clear All") { model.clear() }
            }.font(.caption).padding(10)
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).padding(.bottom, 8) }
        }.frame(width: 500, height: 520)
    }
}

extension HistoryModel {
    func storeImageURL(_ path: String) -> URL { store.imageURL(path) }
}
