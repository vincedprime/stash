import Foundation

enum EntryKind: String, Codable, Sendable { case text, image }

struct ClipboardEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let kind: EntryKind
    let text: String?
    let imagePath: String?
    let byteCount: Int
    var isPinned: Bool

    var preview: String {
        switch kind {
        case .text: return text?.replacingOccurrences(of: "\n", with: " ") ?? ""
        case .image: return "Image"
        }
    }
}

enum SaveResult: Equatable { case saved, duplicate, paused, full }
