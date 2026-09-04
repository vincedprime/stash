import AppKit
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class ClipboardStore {
    static let maximumBytes = 50 * 1024 * 1024
    private var database: OpaquePointer?
    private let root: URL
    private let images: URL

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Stash", isDirectory: true)
        self.images = self.root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        guard sqlite3_open(self.root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK else { throw StoreError.open }
        try execute("""
        CREATE TABLE IF NOT EXISTS entries (
          id TEXT PRIMARY KEY, created_at REAL NOT NULL, kind TEXT NOT NULL,
          text TEXT, image_path TEXT, byte_count INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0
        ); CREATE INDEX IF NOT EXISTS entries_created ON entries(created_at DESC);
        """)
    }

    enum StoreError: Error { case open, sql, imageRead }

    func entries(query: String = "", filter: HistoryFilter = .all) -> [ClipboardEntry] {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var clauses: [String] = []
        if let kind = filter.kind { clauses.append("kind = '\(kind.rawValue)'") }
        if !searchText.isEmpty { clauses.append("text LIKE ?") }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT id,created_at,kind,text,image_path,byte_count,pinned FROM entries\(whereClause) ORDER BY pinned DESC,created_at DESC"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if !searchText.isEmpty { sqlite3_bind_text(statement, 1, "%\(searchText)%", -1, SQLITE_TRANSIENT) }
        var result: [ClipboardEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW, let entry = decode(statement) { result.append(entry) }
        return result
    }

    func byteUsage() -> Int {
        scalarInt("SELECT COALESCE(SUM(byte_count), 0) FROM entries")
    }

    func saveText(_ text: String) -> SaveResult {
        guard !text.isEmpty else { return .duplicate }
        if let last = entries().first, last.kind == .text, last.text == text { return .duplicate }
        return insert(kind: .text, text: text, imageData: nil)
    }

    func saveImage(_ image: NSImage) -> SaveResult {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return .duplicate }
        if let last = entries().first, last.kind == .image, last.byteCount == png.count { return .duplicate }
        return insert(kind: .image, text: nil, imageData: png)
    }

    func setPinned(_ entry: ClipboardEntry, pinned: Bool) {
        executeQuietly("UPDATE entries SET pinned = ? WHERE id = ?", bindings: [.int(pinned ? 1 : 0), .text(entry.id.uuidString)])
    }

    func delete(_ entry: ClipboardEntry) {
        if let imagePath = entry.imagePath { try? FileManager.default.removeItem(at: root.appendingPathComponent(imagePath)) }
        executeQuietly("DELETE FROM entries WHERE id = ?", bindings: [.text(entry.id.uuidString)])
    }

    func clear() {
        entries().forEach(delete)
    }

    func restore(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.kind {
        case .text: pasteboard.setString(entry.text ?? "", forType: .string)
        case .image:
            guard let path = entry.imagePath, let image = NSImage(contentsOf: root.appendingPathComponent(path)) else { return }
            pasteboard.writeObjects([image])
        }
    }

    func imageURL(_ path: String) -> URL { root.appendingPathComponent(path) }

    private func insert(kind: EntryKind, text: String?, imageData: Data?) -> SaveResult {
        let bytes = imageData?.count ?? (text?.utf8.count ?? 0)
        guard bytes <= Self.maximumBytes else { return .full }
        makeRoom(for: bytes)
        guard byteUsage() + bytes <= Self.maximumBytes else { return .full }
        let id = UUID()
        let relativePath: String?
        if let imageData {
            relativePath = "images/\(id.uuidString).png"
            do { try imageData.write(to: root.appendingPathComponent(relativePath!), options: .atomic) }
            catch { return .full }
        } else { relativePath = nil }
        executeQuietly("INSERT INTO entries(id,created_at,kind,text,image_path,byte_count,pinned) VALUES(?,?,?,?,?,?,0)", bindings: [
            .text(id.uuidString), .double(Date().timeIntervalSince1970), .text(kind.rawValue), .optionalText(text), .optionalText(relativePath), .int(bytes)
        ])
        return .saved
    }

    private func makeRoom(for bytes: Int) {
        while byteUsage() + bytes > Self.maximumBytes {
            let candidates = entries().filter { !$0.isPinned }
            guard let oldest = candidates.min(by: { $0.createdAt < $1.createdAt }) else { return }
            delete(oldest)
        }
    }

    private var statement: OpaquePointer?
    private enum Binding { case text(String), optionalText(String?), int(Int), double(Double) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.sql }
    }
    private func executeQuietly(_ sql: String, bindings: [Binding]) {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement); statement = nil }
        for (index, binding) in bindings.enumerated() { bind(binding, at: Int32(index + 1)) }
        _ = sqlite3_step(statement)
    }
    private func bind(_ value: Binding, at index: Int32) {
        switch value {
        case .text(let value): sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case .optionalText(let value):
            if let value { sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(statement, index) }
        case .int(let value): sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case .double(let value): sqlite3_bind_double(statement, index, value)
        }
    }
    private func scalarInt(_ sql: String) -> Int {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement); statement = nil }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }
    private func decode(_ statement: OpaquePointer?) -> ClipboardEntry? {
        guard let idText = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: idText)),
              let kindText = sqlite3_column_text(statement, 2), let kind = EntryKind(rawValue: String(cString: kindText)) else { return nil }
        return ClipboardEntry(id: id, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), kind: kind,
          text: sqlite3_column_text(statement, 3).map { String(cString: $0) }, imagePath: sqlite3_column_text(statement, 4).map { String(cString: $0) },
          byteCount: Int(sqlite3_column_int64(statement, 5)), isPinned: sqlite3_column_int(statement, 6) != 0)
    }
}
