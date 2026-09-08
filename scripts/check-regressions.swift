// The managed CLT installation lacks Swift Testing. This standalone regression
// runner uses only SDK frameworks, isolated storage, and a private pasteboard.
import AppKit
import Carbon
import SQLite3
import SwiftUI

@main
struct RegressionChecks {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stash-checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "stash-regressions-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for (text, kind) in [("#F7ADAD", EntryKind.color), ("F7ADAD", .color), ("#abc", .color),
                             ("#AABBCC80", .color), ("#gggggg", .text), ("hello #F7ADAD", .text),
                             ("https://example.com/path?q=1", .link), ("http://localhost/test", .link),
                             ("https://example.com and words", .text), ("file:///tmp/a", .text),
                             (String(repeating: "x", count: 5000), .text)] {
            precondition(TextContent.kind(for: text) == kind, "Incorrect literal classification")
        }
        precondition(TextContent.rgba("#F7ADAD")!.red == 247.0 / 255)
        precondition(TextContent.rgba("#AABBCC80")!.alpha == 128.0 / 255)

        let store = try ClipboardStore(root: folder, defaults: defaults)
        precondition(store.saveText("#F7ADAD", sourceApp: "Sample app") == .saved)
        let color = store.entries().first!
        precondition(color.kind == .color)
        precondition(store.setTags(" design, work, DESIGN,  ", for: color))
        precondition(store.entries(query: "work").first?.tags == "design, work")
        precondition(store.updateText("https://example.com", for: color))
        let link = store.entries(filter: .link).first!
        precondition(link.id == color.id && link.tags == "design, work")
        precondition(store.updateText("first line\nsecond line", for: link))
        precondition(store.entries(filter: .text).first?.text == "first line\nsecond line")

        // Persist edits, tags, and classification across reopening the database.
        let reopened = try ClipboardStore(root: folder, defaults: defaults)
        precondition(reopened.entries().first?.tags == "design, work")
        precondition(reopened.entries().first?.text == "first line\nsecond line")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let monitor = ClipboardMonitor(store: store)
        pasteboard.setString("#F7ADAD", forType: .string)
        precondition(monitor.capture(from: pasteboard, sourceApp: "Test") == .saved)
        precondition(store.entries().first?.kind == .color)
        pasteboard.clearContents()
        pasteboard.setString("https://example.org", forType: .URL)
        pasteboard.setString("https://example.org", forType: .string)
        precondition(monitor.capture(from: pasteboard, sourceApp: "Test") == .saved)
        precondition(store.entries().first?.kind == .link, "Web URLs must never be files")
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/example.txt") as NSURL])
        pasteboard.setString("example.txt", forType: .string)
        precondition(monitor.capture(from: pasteboard, sourceApp: "Test") == .saved)
        precondition(store.entries().first?.kind == .file)

        // The same expiry path runs from the timer without needing another copy.
        let pinned = store.entries().first!
        store.setPinned(pinned, pinned: true)
        defaults.set(60, forKey: "retentionMinutes")
        let model = HistoryModel(store: store, defaults: defaults)
        model.applyRetention(now: Date().addingTimeInterval(7200))
        precondition(store.entries().count == 1 && store.entries().first?.id == pinned.id)
        precondition(store.byteUsage() == pinned.byteCount)
        model.setRetentionMinutes(0)
        _ = store.saveText("Kept when expiry is disabled", sourceApp: nil)
        model.applyRetention(now: Date().addingTimeInterval(86400))
        precondition(store.entries().count == 2)

        // An existing database gets reclassified once, preserving IDs and pins.
        let legacy = folder.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        var db: OpaquePointer?
        precondition(sqlite3_open(legacy.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        let id = UUID().uuidString
        let sql = """
        CREATE TABLE entries(id TEXT PRIMARY KEY,created_at REAL NOT NULL,kind TEXT NOT NULL,text TEXT,image_path TEXT,byte_count INTEGER NOT NULL,pinned INTEGER NOT NULL DEFAULT 0,source_app TEXT,copy_count INTEGER NOT NULL DEFAULT 1);
        INSERT INTO entries VALUES('\(id)',0,'text','#F7ADAD',NULL,7,1,NULL,3);
        """
        precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let migrated = try ClipboardStore(root: legacy, defaults: defaults)
        let entry = migrated.entries().first!
        precondition(entry.kind == .color && entry.isPinned && entry.id.uuidString == id && entry.copyCount == 3)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        delegate.makeApplicationMenu()
        let editMenu = NSApp.mainMenu!.items[1].submenu!
        precondition(editMenu.items.contains { $0.title == "Redo" && $0.keyEquivalentModifierMask == [.command, .shift] })
        let keyboardWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        model.historyWindow = keyboardWindow
        model.isPresented = true
        model.reload()
        let history = HistoryView(model: model)
        func key(_ code: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: keyboardWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
        }
        let selected = model.selectedID
        model.isEditingInspector = true
        precondition(!history.handleKeyEvent(key(kVK_Return)))
        precondition(!history.handleKeyEvent(key(kVK_DownArrow)))
        precondition(model.selectedID == selected)
        model.isEditingInspector = false
        precondition(!history.handleKeyEvent(key(kVK_ANSI_Z, flags: [.command, .shift])))
        precondition(history.handleKeyEvent(key(kVK_DownArrow)))
        precondition(model.selectedID != selected)
        model.isPresented = false

        try checkBoundedHistory(in: folder.appendingPathComponent("paging"), defaults: defaults, pasteboard: pasteboard)
        try checkFiles(in: folder.appendingPathComponent("files"), defaults: defaults)

        print("Passed: literals, private pasteboard types, persisted edits/tags, expiry/pins/Never, legacy migration, editor keyboard routing and Edit menu.")
    }

    @MainActor
    static func checkFiles(in folder: URL, defaults: UserDefaults) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [folder.appendingPathComponent("Example code.swift"), folder.appendingPathComponent("Other.txt")]
        let code = "func hello() {\n\tprint(\"Hello 🦊\")\n}\n"
        try code.write(to: files[0], atomically: true, encoding: .utf8)
        try "Other contents".write(to: files[1], atomically: true, encoding: .utf8)
        let store = try ClipboardStore(root: folder.appendingPathComponent("history"), defaults: defaults)
        let monitor = ClipboardMonitor(store: store)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        precondition(board.writeObjects(files as [NSURL]))
        precondition(monitor.capture(from: board, sourceApp: "Fixture") == .saved)
        let original = store.entries().first!
        for _ in 0..<3 {
            store.restore(original, to: board)
            precondition(monitor.capture(from: board, sourceApp: "Stash") == nil)
            precondition(store.entries().count == 1 && store.entries().first?.copyCount == 1)
            for _ in 0..<2 {
                let restored = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as! [URL]
                precondition(restored == files, "Repeated pastes must retain both file references")
                let data = try String(contentsOf: restored[0], encoding: .utf8)
                precondition(data == code)
            }
        }
        // A genuine new clipboard write must not be suppressed as our restore.
        board.clearContents()
        precondition(board.writeObjects(files as [NSURL]))
        precondition(monitor.capture(from: board, sourceApp: "Fixture") == .saved)
        precondition(store.entries().count == 1 && store.entries().first?.copyCount == 2)
        _ = store.saveText("Another item", sourceApp: "Fixture")
        store.restore(original, to: board)
        precondition(monitor.capture(from: board, sourceApp: "Stash") == nil)
        precondition(store.entries().count == 2, "Restoring an older file must not create a new row")
        board.clearContents()
        board.setString("A new external copy", forType: .string)
        precondition(monitor.capture(from: board, sourceApp: "Fixture") == .saved)
        precondition(store.entries().first?.text == "A new external copy")

        let preview = FilePreview.load(path: files[0].path)
        precondition(preview.text == code, "Code previews must preserve indentation and Unicode")
        let bigCode = String(repeating: "a", count: FilePreview.byteLimit - 1) + "🦊" + String(repeating: "z", count: 200_000)
        try bigCode.write(to: files[0], atomically: true, encoding: .utf8)
        let bounded = FilePreview.load(path: files[0].path)
        precondition(bounded.text?.utf8.count == FilePreview.byteLimit - 1)
        precondition(bounded.notice.contains("truncated"))
        try Data([0, 1, 2, 0xFF]).write(to: files[0])
        precondition(FilePreview.load(path: files[0].path).text == nil)
        try "Changed contents".write(to: files[0], atomically: true, encoding: .utf8)
        precondition(FilePreview.load(path: files[0].path).text == "Changed contents")
        precondition(FilePreview.load(path: folder.path).text == nil)
        precondition(FilePreview.load(path: folder.appendingPathComponent("missing.swift").path).text == nil)
        let binary = folder.appendingPathComponent("binary.bin")
        try Data([0, 1, 2]).write(to: binary)
        precondition(FilePreview.load(path: binary.path).text == nil)
        print("Passed: repeat file restore/paste, self-capture suppression, genuine file recopy deduplication, bounded code previews, Unicode boundaries, binary/directory/missing files, and current file contents.")
    }

    @MainActor
    static func checkBoundedHistory(in folder: URL, defaults: UserDefaults, pasteboard: NSPasteboard) throws {
        let store = try ClipboardStore(root: folder, defaults: defaults)
        let largeText = String(repeating: "🦊 sample text\n", count: 100_000) + "unique-tail-token"
        precondition(store.saveText(largeText, sourceApp: "Fixture") == .saved)
        let summary = store.entries().first!
        precondition(!summary.textIsComplete && summary.text!.unicodeScalars.count <= 360)
        precondition(store.entries(query: "unique-tail-token").first?.id == summary.id,
                     "Search must match text beyond the excerpt")
        let detail = store.entry(id: summary.id, textLimit: HistoryModel.textPreviewLimit)!
        precondition(!detail.textIsComplete && detail.text!.unicodeScalars.count == HistoryModel.textPreviewLimit)
        store.restore(summary, to: pasteboard)
        precondition(pasteboard.string(forType: .string) == largeText, "Restore must never copy an excerpt")
        let fullEntry = store.entry(id: summary.id)!
        precondition(fullEntry.textIsComplete && fullEntry.text == largeText)

        // Exercise the actual native editor: it must start with the original,
        // preserve its tail, and avoid publishing a whole string per keystroke.
        let session = TextEditSession()
        let editor = NSHostingView(rootView: FullTextEditor(entryID: summary.id, store: store, session: session))
        editor.frame = NSRect(x: 0, y: 0, width: 300, height: 240)
        editor.layoutSubtreeIfNeeded()
        let textView = session.textView!
        precondition(textView.bounds.width > 0 && textView.bounds.height > 0, "The native editor must have a visible text area")
        precondition(textView.string == largeText)
        let end = NSRange(location: textView.textStorage!.length, length: 0)
        precondition(textView.shouldChangeText(in: end, replacementString: " edited"))
        textView.textStorage?.replaceCharacters(in: end, with: " edited")
        textView.didChangeText()
        precondition(session.hasChanges)
        precondition(store.updateText(textView.string, for: summary))
        store.restore(summary, to: pasteboard)
        precondition(pasteboard.string(forType: .string) == largeText + " edited")

        // Identical timestamps and a pinned group straddling a page boundary.
        var db: OpaquePointer?
        precondition(sqlite3_open(folder.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        var inserts = "BEGIN;"
        for index in 0..<205 {
            inserts += "INSERT INTO entries(id,created_at,kind,text,byte_count,pinned) VALUES('\(UUID())',1,'text','row \(index)',\("row \(index)".utf8.count),\(index < 105 ? 1 : 0));"
        }
        inserts += "COMMIT;"
        precondition(sqlite3_exec(db, inserts, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let pagingStore = try ClipboardStore(root: folder, defaults: defaults)
        let model = HistoryModel(store: pagingStore, defaults: defaults)
        model.isPresented = true
        model.reload()
        precondition(model.entries.count == 100 && model.hasMore)
        let firstPage = model.entries.map(\.id)
        model.selectedID = model.entries.last!.id
        model.moveSelection(by: 1)
        precondition(model.entries.count == 200 && model.selectedID == model.entries[100].id)
        model.loadNextPage()
        precondition(model.entries.count == 206 && !model.hasMore)
        precondition(Set(model.entries.map(\.id)).count == 206, "Pages must have no duplicates or omissions")
        precondition(Array(model.entries.prefix(100).map(\.id)) == firstPage)
        precondition(model.entries.prefix(105).allSatisfy(\.isPinned))
        precondition(model.entries.dropFirst(105).allSatisfy { !$0.isPinned })
        model.selectedID = model.entries[150].id
        model.deleteSelection()
        precondition(model.entries.count == 205 && model.selectedID == model.entries[150].id)
        model.query = "unique-tail-token"
        model.reload()
        precondition(model.entries.count == 1 && model.selectedID == summary.id && !model.hasMore)
        precondition(model.inspectorEntry?.textIsComplete == false)
        model.filter = .image
        precondition(model.entries.isEmpty && model.inspectorEntry == nil)

        // Synthetic 4096×2048 image; no real clipboard images are inspected.
        let context = CGContext(data: nil, width: 4096, height: 2048, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4096, height: 2048))
        let pixels = context.makeImage()!
        let png = NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:])!
        precondition(pagingStore.saveImage(ImageCapture(pngData: png, thumbnailData: png,
            metadata: ImageMetadata(pixelWidth: 4096, pixelHeight: 2048, imageFormat: "PNG")), sourceApp: "Fixture") == .saved)
        let imageEntry = pagingStore.entries(filter: .image).first!
        pagingStore.restore(imageEntry, to: pasteboard)
        let restoredImage = NSImage(pasteboard: pasteboard)!
        var imageRect = NSRect(origin: .zero, size: restoredImage.size)
        let restoredPixels = restoredImage.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)!
        precondition(restoredPixels.width == 4096 && restoredPixels.height == 2048,
                     "Image restore must preserve the original resolution")
        let tinyCache = PreviewImageCache(byteLimit: 12 * 1024)
        for index in 0..<6 {
            let url = folder.appendingPathComponent("fixture-\(index).png")
            try png.write(to: url)
            let preview = model.previewCache.image(at: url, maxPixelSize: 1024)!
            precondition(preview.size == NSSize(width: 1024, height: 512))
            precondition(model.previewCache.byteUsage <= model.previewCache.byteLimit)
            let thumbnail = tinyCache.image(at: url, maxPixelSize: 64)!
            precondition(thumbnail.size == NSSize(width: 64, height: 32))
            precondition(tinyCache.byteUsage > 0 && tinyCache.byteUsage <= tinyCache.byteLimit)
        }
        precondition(model.previewCache.byteUsage > 0)
        model.query = "pending search"
        model.dismiss()
        precondition(model.entries.isEmpty && model.selectedID == nil && model.inspectorEntry == nil)
        precondition(model.previewCache.byteUsage == 0 && !model.hasMore)
        model.noteHistoryChanged()
        model.reload()
        precondition(model.entries.isEmpty, "Hidden panels must not reload history")
        model.query = ""
        model.filter = .all
        model.isPresented = true
        model.reload()
        precondition(model.entries.count == 100 && model.selectedID == model.entries.first?.id)
        print("Passed: bounded Unicode excerpts, full-content search/restore/native editing, tied-date pagination, arrow boundary/deletion, image downsampling/cache budgets, hidden-state release and reopen.")
    }
}
