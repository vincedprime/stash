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

        print("Passed: literals, private pasteboard types, persisted edits/tags, expiry/pins/Never, legacy migration, editor keyboard routing and Edit menu.")
    }
}
