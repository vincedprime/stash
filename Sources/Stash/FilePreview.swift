import Foundation
import SwiftUI

struct FilePreview: Equatable {
    static let byteLimit = 100 * 1024
    let name: String
    let text: String?
    let notice: String

    private static let extensions: Set<String> = [
        "txt", "md", "markdown", "swift", "c", "h", "cc", "cpp", "hpp", "m", "mm",
        "rs", "go", "py", "js", "jsx", "ts", "tsx", "json", "jsonc", "yaml", "yml",
        "toml", "xml", "html", "htm", "css", "scss", "less", "sql", "sh", "zsh",
        "bash", "fish", "rb", "php", "java", "kt", "kts", "dart", "vue", "svelte",
        "env", "ini", "conf", "cfg", "log", "csv", "tsv", "properties", "svg"
    ]
    private static let names: Set<String> = [
        "dockerfile", "makefile", "gemfile", "rakefile", "license", "readme",
        ".gitignore", ".gitattributes", ".editorconfig", ".env", ".zshrc", ".bashrc"
    ]

    static func load(path: String) -> FilePreview {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        func unavailable(_ notice: String) -> FilePreview { FilePreview(name: name, text: nil, notice: notice) }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard values.isRegularFile == true else { return unavailable("Preview is available for text and code files only.") }
            // Do not initiate an iCloud download just to display a preview.
            if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
                return unavailable("Download this file locally to preview it.")
            }
            guard extensions.contains(url.pathExtension.lowercased()) || names.contains(name.lowercased()) else {
                return unavailable("Text previews are not available for this file type.")
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: byteLimit + 1) ?? Data()
            let truncated = data.count > byteLimit
            var excerpt = Data(data.prefix(byteLimit))
            // UTF-8 scalars can straddle the byte limit. Trim at most three bytes;
            // never replace invalid binary bytes with misleading replacement text.
            var text = String(data: excerpt, encoding: .utf8)
            if truncated {
                for _ in 0..<3 where text == nil {
                    excerpt.removeLast()
                    text = String(data: excerpt, encoding: .utf8)
                }
            }
            guard let text, !text.unicodeScalars.contains(where: {
                ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
            }) else { return unavailable("This file contains binary data or an unsupported text encoding.") }
            return FilePreview(name: name, text: text,
                notice: truncated ? "Preview truncated at 100 KB. Copying restores the entire file."
                                  : "Current file contents · Copying restores the file")
        } catch CocoaError.fileReadNoSuchFile {
            return unavailable("File not found. It may have been moved or deleted.")
        } catch {
            return unavailable("Could not read this file. Check that it exists and you have permission to open it.")
        }
    }
}

struct FileEntryPreview: View {
    let entry: ClipboardEntry
    @State private var preview: FilePreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview {
                Text(preview.name).font(.headline).lineLimit(1).truncationMode(.middle)
                if (entry.text ?? "").contains("\n") {
                    Text("Previewing the first file in this group").font(.caption).foregroundStyle(.secondary)
                }
                if let text = preview.text {
                    ScrollView([.horizontal, .vertical]) {
                        Text(text.isEmpty ? "Empty file" : text)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    Text(preview.notice).font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Preview unavailable", systemImage: "doc.text.magnifyingglass", description: Text(preview.notice))
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: entry.id) {
            guard !Task.isCancelled,
                  let path = entry.text?.split(separator: "\n", maxSplits: 1).first else { return }
            preview = FilePreview.load(path: String(path))
        }
    }
}
