import AppKit
import ImageIO

/// Bounds retained decoded pixels, not just the number of compressed files.
@MainActor
final class PreviewImageCache {
    private struct Key: Hashable { let url: URL; let maxPixelSize: Int }
    private struct CachedImage { let image: NSImage; let cost: Int; var lastUse: UInt64 }
    let byteLimit: Int
    private(set) var byteUsage = 0
    private var clock: UInt64 = 0
    private var images: [Key: CachedImage] = [:]

    init(byteLimit: Int = 8 * 1024 * 1024) { self.byteLimit = max(0, byteLimit) }

    func image(at url: URL, maxPixelSize: Int) -> NSImage? {
        let dimension = min(1024, max(1, maxPixelSize))
        let key = Key(url: url, maxPixelSize: dimension)
        clock &+= 1
        if var cached = images[key] {
            cached.lastUse = clock
            images[key] = cached
            return cached.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
        let cost = pixels.bytesPerRow * pixels.height
        guard cost <= byteLimit else { return image }
        while byteUsage + cost > byteLimit || images.count >= 128,
              let oldest = images.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            byteUsage -= oldest.value.cost
            images.removeValue(forKey: oldest.key)
        }
        images[key] = CachedImage(image: image, cost: cost, lastUse: clock)
        byteUsage += cost
        return image
    }

    func removeAll() {
        images.removeAll(keepingCapacity: false)
        byteUsage = 0
    }
}
