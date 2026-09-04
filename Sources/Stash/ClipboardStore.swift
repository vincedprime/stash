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
    private var cachedByteUsage = 0

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Stash", isDirectory: true)
        self.images = self.root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        guard sqlite3_open(self.root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK else { throw StoreError.open }
        try execute("""
        CREATE TABLE IF NOT EXISTS entries (
          id TEXT PRIMARY KEY, created_at REAL NOT NULL, kind TEXT NOT NULL,
          text TEXT, image_path TEXT, byte_count INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0,
          source_app TEXT, copy_count INTEGER NOT NULL DEFAULT 1,
          pixel_width INTEGER, pixel_height INTEGER, image_format TEXT,
          thumbnail_path TEXT
        ); CREATE INDEX IF NOT EXISTS entries_created ON entries(created_at DESC);
        CREATE INDEX IF NOT EXISTS entries_unpinned_oldest ON entries(pinned, created_at ASC);
        """)
        try? execute("ALTER TABLE entries ADD COLUMN source_app TEXT")
        try? execute("ALTER TABLE entries ADD COLUMN copy_count INTEGER NOT NULL DEFAULT 1")
        try? execute("ALTER TABLE entries ADD COLUMN pixel_width INTEGER")
        try? execute("ALTER TABLE entries ADD COLUMN pixel_height INTEGER")
        try? execute("ALTER TABLE entries ADD COLUMN image_format TEXT")
        try? execute("ALTER TABLE entries ADD COLUMN thumbnail_path TEXT")
        cachedByteUsage = scalarInt("SELECT COALESCE(SUM(byte_count), 0) FROM entries")
    }

    enum StoreError: Error { case open, sql, imageRead }

    func entries(query: String = "", filter: HistoryFilter = .all) -> [ClipboardEntry] {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var clauses: [String] = []
        if let kind = filter.kind { clauses.append("kind = '\(kind.rawValue)'") }
        if !searchText.isEmpty { clauses.append("text LIKE ?") }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path FROM entries\(whereClause) ORDER BY pinned DESC,created_at DESC"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if !searchText.isEmpty { sqlite3_bind_text(statement, 1, "%\(searchText)%", -1, SQLITE_TRANSIENT) }
        var result: [ClipboardEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW, let entry = decode(statement) { result.append(entry) }
        return result
    }

    func byteUsage() -> Int {
        cachedByteUsage
    }

    func saveText(_ text: String, sourceApp: String?) -> SaveResult {
        guard !text.isEmpty else { return .duplicate }
        if let last = newestEntry(), last.kind == .text, last.text == text {
            refreshDuplicate(last, sourceApp: sourceApp, imageMetadata: nil)
            return .saved
        }
        return insert(kind: .text, text: text, imageData: nil, sourceApp: sourceApp, imageMetadata: nil)
    }

    func saveImage(_ capture: ImageCapture, sourceApp: String?) -> SaveResult {
        if let last = newestEntry(), last.kind == .image, last.byteCount == capture.pngData.count + capture.thumbnailData.count {
            refreshDuplicate(last, sourceApp: sourceApp, imageMetadata: capture.metadata)
            return .saved
        }
        return insert(kind: .image, text: nil, imageData: capture.pngData, thumbnailData: capture.thumbnailData, sourceApp: sourceApp, imageMetadata: capture.metadata)
    }

    func setPinned(_ entry: ClipboardEntry, pinned: Bool) {
        executeQuietly("UPDATE entries SET pinned = ? WHERE id = ?", bindings: [.int(pinned ? 1 : 0), .text(entry.id.uuidString)])
    }

    func delete(_ entry: ClipboardEntry) {
        if let imagePath = entry.imagePath { try? FileManager.default.removeItem(at: root.appendingPathComponent(imagePath)) }
        if let thumbnailPath = entry.thumbnailPath { try? FileManager.default.removeItem(at: root.appendingPathComponent(thumbnailPath)) }
        executeQuietly("DELETE FROM entries WHERE id = ?", bindings: [.text(entry.id.uuidString)])
        cachedByteUsage -= entry.byteCount
    }

    func clear() {
        var paths: [String] = []
        guard sqlite3_prepare_v2(database, "SELECT image_path, thumbnail_path FROM entries", -1, &statement, nil) == SQLITE_OK else { return }
        while sqlite3_step(statement) == SQLITE_ROW {
            for index in [0, 1] where sqlite3_column_type(statement, Int32(index)) != SQLITE_NULL {
                paths.append(String(cString: sqlite3_column_text(statement, Int32(index))))
            }
        }
        sqlite3_finalize(statement)
        statement = nil
        paths.forEach { try? FileManager.default.removeItem(at: root.appendingPathComponent($0)) }
        executeQuietly("DELETE FROM entries", bindings: [])
        cachedByteUsage = 0
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

    private func insert(kind: EntryKind, text: String?, imageData: Data?, thumbnailData: Data? = nil, sourceApp: String?, imageMetadata: ImageMetadata?) -> SaveResult {
        let bytes = (imageData?.count ?? (text?.utf8.count ?? 0)) + (thumbnailData?.count ?? 0)
        guard bytes <= Self.maximumBytes else { return .full }
        makeRoom(for: bytes)
        guard byteUsage() + bytes <= Self.maximumBytes else { return .full }
        let id = UUID()
        let relativePath: String?
        let thumbnailPath: String?
        if let imageData {
            relativePath = "images/\(id.uuidString).png"
            do { try imageData.write(to: root.appendingPathComponent(relativePath!), options: .atomic) }
            catch { return .full }
            thumbnailPath = "images/\(id.uuidString)-thumb.png"
            do { try thumbnailData?.write(to: root.appendingPathComponent(thumbnailPath!), options: .atomic) }
            catch { try? FileManager.default.removeItem(at: root.appendingPathComponent(relativePath!)); return .full }
        } else { relativePath = nil; thumbnailPath = nil }
        executeQuietly("INSERT INTO entries(id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path) VALUES(?,?,?,?,?,?,0,?,1,?,?,?,?)", bindings: [
            .text(id.uuidString), .double(Date().timeIntervalSince1970), .text(kind.rawValue), .optionalText(text), .optionalText(relativePath), .int(bytes), .optionalText(sourceApp),
            .optionalInt(imageMetadata?.pixelWidth), .optionalInt(imageMetadata?.pixelHeight), .optionalText(imageMetadata?.imageFormat), .optionalText(thumbnailPath)
        ])
        cachedByteUsage += bytes
        return .saved
    }

    private func refreshDuplicate(_ entry: ClipboardEntry, sourceApp: String?, imageMetadata: ImageMetadata?) {
        executeQuietly("UPDATE entries SET created_at = ?, source_app = ?, copy_count = copy_count + 1, pixel_width = ?, pixel_height = ?, image_format = ? WHERE id = ?", bindings: [
            .double(Date().timeIntervalSince1970), .optionalText(sourceApp), .optionalInt(imageMetadata?.pixelWidth), .optionalInt(imageMetadata?.pixelHeight), .optionalText(imageMetadata?.imageFormat), .text(entry.id.uuidString)
        ])
    }

    private func makeRoom(for bytes: Int) {
        while cachedByteUsage + bytes > Self.maximumBytes {
            guard let oldest = oldestUnpinnedEntry() else { return }
            delete(oldest)
        }
    }

    private func newestEntry() -> ClipboardEntry? {
        fetchOne("SELECT id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path FROM entries ORDER BY created_at DESC LIMIT 1")
    }

    private func oldestUnpinnedEntry() -> ClipboardEntry? {
        fetchOne("SELECT id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path FROM entries WHERE pinned = 0 ORDER BY created_at ASC LIMIT 1")
    }

    private func fetchOne(_ sql: String) -> ClipboardEntry? {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement); statement = nil }
        return sqlite3_step(statement) == SQLITE_ROW ? decode(statement) : nil
    }

    private var statement: OpaquePointer?
    private enum Binding { case text(String), optionalText(String?), int(Int), optionalInt(Int?), double(Double) }
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
        case .optionalInt(let value):
            if let value { sqlite3_bind_int64(statement, index, sqlite3_int64(value)) } else { sqlite3_bind_null(statement, index) }
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
          byteCount: Int(sqlite3_column_int64(statement, 5)), isPinned: sqlite3_column_int(statement, 6) != 0,
          sourceApp: sqlite3_column_text(statement, 7).map { String(cString: $0) }, copyCount: Int(sqlite3_column_int64(statement, 8)),
          pixelWidth: sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 9)),
          pixelHeight: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 10)),
          imageFormat: sqlite3_column_text(statement, 11).map { String(cString: $0) },
          thumbnailPath: sqlite3_column_text(statement, 12).map { String(cString: $0) })
    }
}
