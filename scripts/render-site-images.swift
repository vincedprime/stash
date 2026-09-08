import AppKit
import SwiftUI

/// Render the shipping views with sample data. Never start the clipboard monitor,
/// read the general pasteboard, or open the user's Stash database.
@main
struct SiteImages {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stash-site-\(UUID())")
        let suite = "stash-site-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Cannot create demo defaults") }
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = try ClipboardStore(root: folder, defaults: defaults)
        let file = folder.appendingPathComponent("hello.swift")
        try """
        import Foundation

        struct Note {
            let title: String
            let tags: [String]

            var summary: String {
                tags.joined(separator: ", ")
            }
        }

        let note = Note(
            title: "A little less to remember",
            tags: ["ideas", "weekend"]
        )

        print(note.title)
        """.write(to: file, atomically: true, encoding: .utf8)
        _ = store.saveText("Book a table for Saturday", sourceApp: "Notes")
        _ = store.saveText("https://example.com/weekend", sourceApp: "Safari")
        _ = store.saveText("#F7ADAD", sourceApp: "Safari")
        _ = store.saveFiles([file], sourceApp: "Finder")
        let artwork = makeArtwork()
        guard let tiff = artwork.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode demo image") }
        _ = store.saveImage(ImageCapture(pngData: png, thumbnailData: png,
            metadata: ImageMetadata(pixelWidth: bitmap.pixelsWide, pixelHeight: bitmap.pixelsHigh, imageFormat: "PNG")), sourceApp: "Preview")
        _ = store.saveText("Shopping list: coffee, lemons, sourdough", sourceApp: "Notes")
        let note = """
        A few ideas for the weekend

        Take the early train.
        Find a quiet place for coffee.
        Bring a book, leave room for a walk.

        Nothing else on the list.
        """
        _ = store.saveText(note, sourceApp: "Notes")
        if let entry = store.entries().first {
            store.setPinned(entry, pinned: true)
            _ = store.setTags("weekend, ideas", for: entry)
        }
        let model = HistoryModel(store: store, defaults: defaults)
        model.isPresented = true
        model.reload()
        try render(HistoryView(model: model), width: 740, height: 540, to: output.appendingPathComponent("history.png"))
        model.selectedID = model.entries.first { $0.kind == .image }?.id
        try render(HistoryView(model: model), width: 740, height: 540, to: output.appendingPathComponent("images.png"))
        model.selectedID = model.entries.first { $0.kind == .file }?.id
        try render(HistoryView(model: model), width: 740, height: 540, to: output.appendingPathComponent("code.png"))
        let bindings = Dictionary(uniqueKeysWithValues: PanelShortcut.configurable.map { ($0, $0.defaultBinding) })
        try render(ShortcutSettingsView(model: model, open: .openDefault, recording: .recordDefault,
            panel: bindings, onSave: { _, _, _ in true }), width: 460, height: 620,
            to: output.appendingPathComponent("settings.png"))
        model.dismiss()
        print("Rendered four native feature screenshots with isolated sample data.")
    }

    private static func render(_ view: some View, width: CGFloat, height: CGFloat, to url: URL) throws {
        // Use native dark appearance for clear, consistent documentation images.
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US")))
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot snapshot native view") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode screenshot") }
        try png.write(to: url)
    }

    private static func makeArtwork() -> NSImage {
        let image = NSImage(size: NSSize(width: 800, height: 600))
        image.lockFocus()
        NSColor(red: 0.94, green: 0.91, blue: 0.83, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 800, height: 600).fill()
        NSColor(red: 0.83, green: 0.42, blue: 0.25, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 555, y: 330, width: 120, height: 120)).fill()
        NSColor(red: 0.40, green: 0.49, blue: 0.36, alpha: 1).setFill()
        let hill = NSBezierPath()
        hill.move(to: .zero)
        hill.line(to: NSPoint(x: 0, y: 260))
        hill.curve(to: NSPoint(x: 800, y: 250), controlPoint1: NSPoint(x: 340, y: 490), controlPoint2: NSPoint(x: 520, y: 90))
        hill.line(to: NSPoint(x: 800, y: 0))
        hill.close()
        hill.fill()
        ("Take the long\nway home." as NSString).draw(at: NSPoint(x: 56, y: 435), withAttributes: [
            .font: NSFont.systemFont(ofSize: 48, weight: .medium),
            .foregroundColor: NSColor(red: 0.18, green: 0.24, blue: 0.18, alpha: 1)
        ])
        image.unlockFocus()
        return image
    }
}
