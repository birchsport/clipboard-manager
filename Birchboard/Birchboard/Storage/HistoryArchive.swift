import Foundation

/// On-disk format for `Birchboard export` / `import`. A single JSON file with
/// image bytes inlined as base64 — keeps the UX "one file" without a zip
/// dependency. Text-heavy histories are tiny; a few hundred images adds maybe
/// 50–100 MB which is still reasonable for a personal tool.
///
/// Version is bumped whenever a backwards-incompatible shape change lands.
struct HistoryArchive: Codable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let entries: [ArchivedEntry]

    init(entries: [ArchivedEntry]) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.entries = entries
    }
}

/// A single history entry flattened for portability. Mirrors the shape of the
/// `entries` SQLite table except that blob references are replaced with
/// inlined PNG bytes, and the database `id` is dropped — on import we mint new
/// ids and dedupe by hash.
struct ArchivedEntry: Codable {
    enum Kind: Int, Codable {
        case text = 0
        case rtf = 1
        case image = 2
        case fileURLs = 3
    }

    let kind: Kind
    let createdAt: Date
    let pinnedAt: Date?
    let sourceBundleID: String?
    let sourceName: String?
    let dedupHash: String

    // Payload — exactly one populated based on `kind`.
    let text: String?            // .text or .rtf plain projection
    let rtfData: Data?           // .rtf only
    let imagePNG: Data?          // .image only
    let imageWidth: Int?         // .image only
    let imageHeight: Int?        // .image only
    let imageHash: String?       // .image only (sha256 of bytes)
    let fileURLs: [String]?      // .fileURLs only

    // MARK: - Convert from a live ClipEntry

    init(from entry: ClipEntry, imageDataLoader: (URL) throws -> Data) rethrows {
        self.createdAt = entry.createdAt
        self.pinnedAt = entry.pinnedAt
        self.sourceBundleID = entry.source?.bundleID
        self.sourceName = entry.source?.name
        self.dedupHash = entry.kind.dedupHash

        switch entry.kind {
        case .text(let s):
            self.kind = .text
            self.text = s
            self.rtfData = nil
            self.imagePNG = nil
            self.imageWidth = nil
            self.imageHeight = nil
            self.imageHash = nil
            self.fileURLs = nil

        case .rtf(let data, let plain):
            self.kind = .rtf
            self.text = plain
            self.rtfData = data
            self.imagePNG = nil
            self.imageWidth = nil
            self.imageHeight = nil
            self.imageHash = nil
            self.fileURLs = nil

        case .image(let path, let w, let h, let hash):
            self.kind = .image
            self.text = nil
            self.rtfData = nil
            self.imagePNG = try imageDataLoader(path)
            self.imageWidth = w
            self.imageHeight = h
            self.imageHash = hash
            self.fileURLs = nil

        case .fileURLs(let urls):
            self.kind = .fileURLs
            self.text = nil
            self.rtfData = nil
            self.imagePNG = nil
            self.imageWidth = nil
            self.imageHeight = nil
            self.imageHash = nil
            self.fileURLs = urls.map { $0.absoluteString }
        }
    }
}
