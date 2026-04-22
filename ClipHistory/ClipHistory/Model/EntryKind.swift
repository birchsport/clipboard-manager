import Foundation

/// The payload carried by a `ClipEntry`. One case per pasteboard representation we
/// capture. Persistence flattens this into columns in the `entries` table.
enum EntryKind: Equatable {
    case text(String)
    case rtf(Data, plainText: String)
    case image(blobPath: URL, width: Int, height: Int, hash: String)
    case fileURLs([URL])

    /// Stable int tag for persistence.
    var tag: Int {
        switch self {
        case .text:     return 0
        case .rtf:      return 1
        case .image:    return 2
        case .fileURLs: return 3
        }
    }

    /// Plain-text projection used for search and row previews.
    var plainText: String {
        switch self {
        case .text(let s): return s
        case .rtf(_, let plain): return plain
        case .image: return ""
        case .fileURLs(let urls):
            return urls.map { $0.path }.joined(separator: "\n")
        }
    }

    /// Hash that identifies this entry for deduplication. Same text / same image bytes
    /// should collide so we can bump `createdAt` instead of inserting duplicates.
    var dedupHash: String {
        switch self {
        case .text(let s):
            return Self.sha256(of: Data(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        case .rtf(let data, _):
            return Self.sha256(of: data)
        case .image(_, _, _, let hash):
            return hash
        case .fileURLs(let urls):
            let joined = urls.map { $0.absoluteString }.sorted().joined(separator: "\u{0}")
            return Self.sha256(of: Data(joined.utf8))
        }
    }

    static func sha256(of data: Data) -> String {
        ImageHash.sha256Hex(of: data)
    }
}
