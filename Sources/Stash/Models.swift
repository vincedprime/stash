import Foundation

enum EntryKind: String, Codable, Sendable { case text, image }

enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case text = "Text"
    case image = "Images"

    var id: Self { self }
    var kind: EntryKind? {
        switch self { case .all: nil; case .text: .text; case .image: .image }
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
    let detectedLanguage: String?
    let contentKind: String?
    let linkCount: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let imageFormat: String?

    var preview: String {
        switch kind {
        case .text: return text?.replacingOccurrences(of: "\n", with: " ") ?? ""
        case .image: return "Image"
        }
    }
}

struct TextMetadata: Sendable {
    let detectedLanguage: String?
    let contentKind: String
    let linkCount: Int
}

struct ImageMetadata: Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let imageFormat: String?
}

enum SaveResult: Equatable { case saved, duplicate, paused, full }
