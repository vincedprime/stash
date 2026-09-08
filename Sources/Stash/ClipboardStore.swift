import AppKit
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class ClipboardStore {
    static let defaultMaximumBytes = 50 * 1024 * 1024
    private var database: OpaquePointer?
    private let root: URL
    private let images: URL
    private let defaults: UserDefaults
    private var cachedByteUsage = 0
    private var restoredPasteboard: (name: NSPasteboard.Name, changeCount: Int)?
    private(set) var maximumBytes: Int

    init(root: URL? = nil, defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        let savedLimit = defaults.integer(forKey: "storageLimitBytes")
        self.maximumBytes = savedLimit > 0 ? savedLimit : Self.defaultMaximumBytes
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
          thumbnail_path TEXT, tags TEXT
        ); CREATE INDEX IF NOT EXISTS entries_created ON entries(created_at DESC);
        CREATE INDEX IF NOT EXISTS entries_unpinned_oldest ON entries(pinned, created_at ASC);
        CREATE INDEX IF NOT EXISTS entries_history ON entries(pinned DESC, created_at DESC, id DESC);
        """)
        try? execute("ALTER TABLE entries ADD COLUMN source_app TEXT")
        try? execute("ALTER TABLE entries ADD COLUMN copy_count INTEGER NOT NULL DEFAULT 1")
        try? execute("ALTER TABLE entries ADD COLUMN pixel_width INTEGER")
        try? execute("ALTER TABLE entries ADD COLUMN pixel_height INTEGER")
        try? execute("ALTER TABLE entries ADD COLUMN image_format TEXT")
        try? execute("ALTER TABLE entries ADD COLUMN thumbnail_path TEXT")
        try? execute("ALTER TABLE entries ADD COLUMN tags TEXT")
        try classifyLegacyText()
        cachedByteUsage = scalarInt("SELECT COALESCE(SUM(byte_count), 0) FROM entries")
    }

    enum StoreError: Error { case open, sql, imageRead }

    func entries(query: String = "", filter: HistoryFilter = .all,
                 after cursor: ClipboardEntry? = nil, limit: Int = 100) -> [ClipboardEntry] {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var clauses: [String] = []
        if let kind = filter.kind { clauses.append("kind = '\(kind.rawValue)'") }
        if !searchText.isEmpty { clauses.append("(text LIKE ? OR tags LIKE ?)") }
        if cursor != nil { clauses.append("(pinned,created_at,id) < (?,?,?)") }
        let whereClause = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT id,created_at,kind,substr(text,1,360),image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path,tags FROM entries\(whereClause) ORDER BY pinned DESC,created_at DESC,id DESC LIMIT \(max(1, limit))"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement); statement = nil }
        if !searchText.isEmpty {
            sqlite3_bind_text(statement, 1, "%\(searchText)%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, "%\(searchText)%", -1, SQLITE_TRANSIENT)
        }
        if let cursor {
            let first: Int32 = searchText.isEmpty ? 1 : 3
            sqlite3_bind_int(statement, first, cursor.isPinned ? 1 : 0)
            sqlite3_bind_double(statement, first + 1, cursor.createdAt.timeIntervalSince1970)
            sqlite3_bind_text(statement, first + 2, cursor.id.uuidString, -1, SQLITE_TRANSIENT)
        }
        var result: [ClipboardEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW, let entry = decode(statement) { result.append(entry) }
        return result
    }

    // Full text is read only for an explicit restore or edit. Search still matches
    // the original SQL text even when the returned list excerpt is short.
    func entry(id: UUID, textLimit: Int? = nil) -> ClipboardEntry? {
        let textColumn = textLimit.map { "substr(text,1,\(max(1, $0)))" } ?? "text"
        let sql = "SELECT id,created_at,kind,\(textColumn),image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path,tags FROM entries WHERE id = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement); statement = nil }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW ? decode(statement) : nil
    }

    func byteUsage() -> Int {
        cachedByteUsage
    }

    func setMaximumBytes(_ value: Int) {
        maximumBytes = value
        defaults.set(value, forKey: "storageLimitBytes")
        makeRoom(for: 0)
    }

    func saveText(_ text: String, sourceApp: String?) -> SaveResult {
        guard !text.isEmpty else { return .duplicate }
        let kind = TextContent.kind(for: text)
        if let last = newestEntry(), last.kind == kind, last.text == text {
            refreshDuplicate(last, sourceApp: sourceApp, imageMetadata: nil)
            return .saved
        }
        return insert(kind: kind, text: text, imageData: nil, sourceApp: sourceApp, imageMetadata: nil)
    }

    func saveImage(_ capture: ImageCapture, sourceApp: String?) -> SaveResult {
        if let last = newestEntry(), last.kind == .image, last.byteCount == capture.pngData.count + capture.thumbnailData.count {
            refreshDuplicate(last, sourceApp: sourceApp, imageMetadata: capture.metadata)
            return .saved
        }
        return insert(kind: .image, text: nil, imageData: capture.pngData, thumbnailData: capture.thumbnailData, sourceApp: sourceApp, imageMetadata: capture.metadata)
    }

    func saveFiles(_ urls: [URL], sourceApp: String?) -> SaveResult {
        let paths = urls.map(\.path).joined(separator: "\n")
        guard !paths.isEmpty else { return .duplicate }
        if let last = newestEntry(), last.kind == .file, last.text == paths {
            refreshDuplicate(last, sourceApp: sourceApp, imageMetadata: nil)
            return .saved
        }
        return insert(kind: .file, text: paths, imageData: nil, sourceApp: sourceApp, imageMetadata: nil)
    }

    func saveColor(_ color: NSColor, sourceApp: String?) -> SaveResult {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .duplicate }
        let hex = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        return insert(kind: .color, text: hex, imageData: nil, sourceApp: sourceApp, imageMetadata: nil)
    }

    func setTags(_ tags: String, for entry: ClipboardEntry) -> Bool {
        var seen = Set<String>()
        let normalized = tags.prefix(512).split(separator: ",").compactMap { part -> String? in
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag.lowercased()).inserted ? tag : nil
        }.joined(separator: ", ")
        return executeQuietly("UPDATE entries SET tags = ? WHERE id = ?", bindings: [.optionalText(normalized.isEmpty ? nil : normalized), .text(entry.id.uuidString)])
    }

    func updateText(_ text: String, for entry: ClipboardEntry) -> Bool {
        guard entry.kind.isEditable, !text.isEmpty else { return false }
        let newBytes = text.utf8.count
        guard cachedByteUsage - entry.byteCount + newBytes <= maximumBytes else { return false }
        guard executeQuietly("UPDATE entries SET text = ?, byte_count = ?, kind = ? WHERE id = ?", bindings: [.text(text), .int(newBytes), .text(TextContent.kind(for: text).rawValue), .text(entry.id.uuidString)]) else { return false }
        cachedByteUsage += newBytes - entry.byteCount
        return true
    }

    func deleteEntries(since date: Date) {
        _ = deleteEntries(matching: "created_at >= ?", date: date)
    }

    @discardableResult
    func deleteEntries(before date: Date) -> Bool {
        deleteEntries(matching: "created_at < ?", date: date)
    }

    // Read only payload paths and sizes for expiry, never materialize history text.
    private func deleteEntries(matching predicate: String, date: Date) -> Bool {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT image_path,thumbnail_path,byte_count FROM entries WHERE pinned = 0 AND \(predicate)", -1, &query, nil) == SQLITE_OK else { return false }
        sqlite3_bind_double(query, 1, date.timeIntervalSince1970)
        var paths: [String] = []
        var bytes = 0
        var count = 0
        while sqlite3_step(query) == SQLITE_ROW {
            for index: Int32 in [0, 1] {
                if let path = sqlite3_column_text(query, index) { paths.append(String(cString: path)) }
            }
            bytes += Int(sqlite3_column_int64(query, 2))
            count += 1
        }
        sqlite3_finalize(query)
        guard count > 0, executeQuietly("DELETE FROM entries WHERE pinned = 0 AND \(predicate)", bindings: [.double(date.timeIntervalSince1970)]) else { return false }
        cachedByteUsage -= bytes
        for path in paths { try? FileManager.default.removeItem(at: root.appendingPathComponent(path)) }
        return true
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

    func restore(_ summary: ClipboardEntry, to pasteboard: NSPasteboard = .general) {
        guard let entry = entry(id: summary.id) else { return }
        pasteboard.clearContents()
        let written: Bool
        switch entry.kind {
        case .text, .color: written = pasteboard.setString(entry.text ?? "", forType: .string)
        case .link:
            let textWritten = pasteboard.setString(entry.text ?? "", forType: .string)
            let urlWritten = pasteboard.setString((entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), forType: .URL)
            written = textWritten && urlWritten
        case .file:
            let urls = (entry.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            written = pasteboard.writeObjects(urls as [NSURL])
        case .image:
            guard let path = entry.imagePath, let image = NSImage(contentsOf: root.appendingPathComponent(path)) else { return }
            written = pasteboard.writeObjects([image])
        }
        if written { restoredPasteboard = (pasteboard.name, pasteboard.changeCount) }
    }

    func isRestoredPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        restoredPasteboard?.name == pasteboard.name && restoredPasteboard?.changeCount == pasteboard.changeCount
    }

    func imageURL(_ path: String) -> URL { root.appendingPathComponent(path) }

    private func insert(kind: EntryKind, text: String?, imageData: Data?, thumbnailData: Data? = nil, sourceApp: String?, imageMetadata: ImageMetadata?) -> SaveResult {
        let bytes = (imageData?.count ?? (text?.utf8.count ?? 0)) + (thumbnailData?.count ?? 0)
        guard bytes <= maximumBytes else { return .full }
        makeRoom(for: bytes)
        guard byteUsage() + bytes <= maximumBytes else { return .full }
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
        executeQuietly("INSERT INTO entries(id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path,tags) VALUES(?,?,?,?,?,?,0,?,1,?,?,?,?,?)", bindings: [
            .text(id.uuidString), .double(Date().timeIntervalSince1970), .text(kind.rawValue), .optionalText(text), .optionalText(relativePath), .int(bytes), .optionalText(sourceApp),
            .optionalInt(imageMetadata?.pixelWidth), .optionalInt(imageMetadata?.pixelHeight), .optionalText(imageMetadata?.imageFormat), .optionalText(thumbnailPath), .optionalText(nil)
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
        while cachedByteUsage + bytes > maximumBytes {
            guard let oldest = oldestUnpinnedEntry() else { return }
            delete(oldest)
        }
    }

    private func newestEntry() -> ClipboardEntry? {
        fetchOne("SELECT id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path,tags FROM entries ORDER BY created_at DESC LIMIT 1")
    }

    private func oldestUnpinnedEntry() -> ClipboardEntry? {
        fetchOne("SELECT id,created_at,kind,text,image_path,byte_count,pinned,source_app,copy_count,pixel_width,pixel_height,image_format,thumbnail_path,tags FROM entries WHERE pinned = 0 ORDER BY created_at ASC LIMIT 1")
    }

    private func fetchOne(_ sql: String) -> ClipboardEntry? {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement); statement = nil }
        return sqlite3_step(statement) == SQLITE_ROW ? decode(statement) : nil
    }

    private var statement: OpaquePointer?
    private func classifyLegacyText() throws {
        guard scalarInt("PRAGMA user_version") == 0 else { return }
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id,text FROM entries WHERE kind = 'text' AND byte_count <= 4096", -1, &query, nil) == SQLITE_OK else { throw StoreError.sql }
        var changes: [(String, EntryKind)] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = sqlite3_column_text(query, 0), let text = sqlite3_column_text(query, 1) else { continue }
            let kind = TextContent.kind(for: String(cString: text))
            if kind != .text { changes.append((String(cString: id), kind)) }
        }
        sqlite3_finalize(query)
        try execute("BEGIN TRANSACTION")
        do {
            for (id, kind) in changes {
                guard executeQuietly("UPDATE entries SET kind = ? WHERE id = ?", bindings: [.text(kind.rawValue), .text(id)]) else { throw StoreError.sql }
            }
            try execute("PRAGMA user_version = 1")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    private enum Binding { case text(String), optionalText(String?), int(Int), optionalInt(Int?), double(Double) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.sql }
    }
    @discardableResult
    private func executeQuietly(_ sql: String, bindings: [Binding]) -> Bool {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement); statement = nil }
        for (index, binding) in bindings.enumerated() { bind(binding, at: Int32(index + 1)) }
        return sqlite3_step(statement) == SQLITE_DONE
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
        var entry = ClipboardEntry(id: id, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), kind: kind,
          text: sqlite3_column_text(statement, 3).map { String(cString: $0) }, imagePath: sqlite3_column_text(statement, 4).map { String(cString: $0) },
          byteCount: Int(sqlite3_column_int64(statement, 5)), isPinned: sqlite3_column_int(statement, 6) != 0,
          sourceApp: sqlite3_column_text(statement, 7).map { String(cString: $0) }, copyCount: Int(sqlite3_column_int64(statement, 8)),
          pixelWidth: sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 9)),
          pixelHeight: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 10)),
          imageFormat: sqlite3_column_text(statement, 11).map { String(cString: $0) },
          thumbnailPath: sqlite3_column_text(statement, 12).map { String(cString: $0) },
          tags: sqlite3_column_text(statement, 13).map { String(cString: $0) })
        entry.textIsComplete = kind == .image || (entry.text?.utf8.count ?? 0) == entry.byteCount
        return entry
    }
}
