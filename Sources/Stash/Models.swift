import Foundation

enum EntryKind: String, Codable, Sendable { case text, image, file, color, link
    var title: String { rawValue.capitalized }
    var isEditable: Bool { self == .text || self == .link || self == .color }
}

enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case text = "Text"
    case image = "Images"
    case file = "Files"
    case color = "Colors"
    case link = "Links"

    var id: Self { self }
    var kind: EntryKind? {
        switch self { case .all: nil; case .text: .text; case .image: .image; case .file: .file; case .color: .color; case .link: .link }
    }
}

struct ClipboardEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let kind: EntryKind
    let text: String?
    let imagePath: String?
    let byteCount: Int
    var isPinned: Bool
    let sourceApp: String?
    let copyCount: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
    let imageFormat: String?
    let thumbnailPath: String?
    let tags: String?

    var preview: String {
        switch kind {
        case .text, .link:
            // Keep list rendering proportional to the preview, not to the copied item.
            let excerpt = text?.prefix(360) ?? ""
            return excerpt.replacingOccurrences(of: "\n", with: " ")
        case .image: return "Image"
        case .file: return URL(fileURLWithPath: text ?? "").lastPathComponent
        case .color: return text ?? "Color"
        }
    }
}

// Deliberately bounded: classify whole short literals, never scan prose or large logs.
nonisolated enum TextContent {
    static func kind(for text: String) -> EntryKind {
        guard text.utf8.count <= 4096 else { return .text }
        let literal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rgba(literal) != nil { return .color }
        guard !literal.contains(where: \.isWhitespace),
              let url = URL(string: literal),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return .text }
        return .link
    }

    static func rgba(_ text: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard text.utf8.count <= 9 else { return nil }
        let prefixed = text.hasPrefix("#")
        let digits = prefixed ? String(text.dropFirst()) : text
        guard (prefixed ? [3, 4, 6, 8].contains(digits.count) : digits.count == 6),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        let expanded = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : digits
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        let rgba = expanded.count == 8 ? value : (value << 8) | 255
        return (Double((rgba >> 24) & 255) / 255, Double((rgba >> 16) & 255) / 255,
                Double((rgba >> 8) & 255) / 255, Double(rgba & 255) / 255)
    }
}

struct ImageMetadata: Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let imageFormat: String?
}

struct ImageCapture: Sendable {
    let pngData: Data
    let thumbnailData: Data
    let metadata: ImageMetadata
}

enum SaveResult: Equatable { case saved, duplicate, paused, full }
