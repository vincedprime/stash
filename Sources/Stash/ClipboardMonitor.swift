import AppKit

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
            result = store.saveText(string, sourceApp: sourceApp)
        } else if let image = NSImage(pasteboard: pasteboard),
                  let capture = imageCapture(for: image, pasteboard: pasteboard) {
            result = store.saveImage(capture, sourceApp: sourceApp)
        }
        else { return }
        onSave?(result)
    }

    private func imageCapture(for image: NSImage, pasteboard: NSPasteboard) -> ImageCapture? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let types = Set(pasteboard.types?.map(\.rawValue) ?? [])
        let imageFormat: String?
        if types.contains("public.png") { imageFormat = "PNG" }
        else if types.contains("public.jpeg") { imageFormat = "JPEG" }
        else if types.contains("public.heic") { imageFormat = "HEIC" }
        else if types.contains("public.gif") { imageFormat = "GIF" }
        else if types.contains("public.tiff") { imageFormat = "TIFF" }
        else { imageFormat = nil }
        let thumbnailSide = 160.0
        let scale = min(thumbnailSide / max(Double(bitmap.pixelsWide), 1), thumbnailSide / max(Double(bitmap.pixelsHigh), 1), 1)
        let thumbnailSize = NSSize(width: CGFloat(Double(bitmap.pixelsWide) * scale), height: CGFloat(Double(bitmap.pixelsHigh) * scale))
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        guard let thumbnailTIFF = thumbnail.tiffRepresentation,
              let thumbnailBitmap = NSBitmapImageRep(data: thumbnailTIFF),
              let thumbnailData = thumbnailBitmap.representation(using: .png, properties: [:]) else { return nil }
        let metadata = ImageMetadata(pixelWidth: bitmap.pixelsWide, pixelHeight: bitmap.pixelsHigh, imageFormat: imageFormat)
        return ImageCapture(pngData: pngData, thumbnailData: thumbnailData, metadata: metadata)
    }
}
