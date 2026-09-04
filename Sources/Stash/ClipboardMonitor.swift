import AppKit
import NaturalLanguage

@MainActor
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    var isPaused = false
    var onSave: ((SaveResult) -> Void)?

    init(store: ClipboardStore) { self.store = store }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readPasteboard() }
        }
    }

    private func readPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard !isPaused else { onSave?(.paused); return }
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let result: SaveResult
        if let string = pasteboard.string(forType: .string) {
            result = store.saveText(string, sourceApp: sourceApp, metadata: textMetadata(for: string))
        } else if let image = NSImage(pasteboard: pasteboard) {
            result = store.saveImage(image, sourceApp: sourceApp, metadata: imageMetadata(for: image, pasteboard: pasteboard))
        }
        else { return }
        onSave?(result)
    }

    private func textMetadata(for text: String) -> TextMetadata {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let linkCount = detector?.matches(in: text, range: range).count ?? 0

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detectedLanguage = recognizer.dominantLanguage.flatMap { language in
            Locale.current.localizedString(forLanguageCode: language.rawValue)?.capitalized
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentKind: String
        if linkCount == 1, URL(string: trimmed)?.scheme != nil { contentKind = "Link" }
        else if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil { contentKind = "JSON" }
        else if trimmed.hasPrefix("$") || trimmed.hasPrefix("git ") || trimmed.hasPrefix("sudo ") { contentKind = "Command" }
        else if trimmed.range(of: #"\b(func|let|var|class|import)\b"#, options: .regularExpression) != nil { contentKind = "Code" }
        else { contentKind = "Text" }

        return TextMetadata(detectedLanguage: detectedLanguage, contentKind: contentKind, linkCount: linkCount)
    }

    private func imageMetadata(for image: NSImage, pasteboard: NSPasteboard) -> ImageMetadata {
        let bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        let types = Set(pasteboard.types?.map(\.rawValue) ?? [])
        let imageFormat: String?
        if types.contains("public.png") { imageFormat = "PNG" }
        else if types.contains("public.jpeg") { imageFormat = "JPEG" }
        else if types.contains("public.heic") { imageFormat = "HEIC" }
        else if types.contains("public.gif") { imageFormat = "GIF" }
        else if types.contains("public.tiff") { imageFormat = "TIFF" }
        else { imageFormat = nil }
        return ImageMetadata(pixelWidth: bitmap?.pixelsWide ?? 0, pixelHeight: bitmap?.pixelsHigh ?? 0, imageFormat: imageFormat)
    }
}
