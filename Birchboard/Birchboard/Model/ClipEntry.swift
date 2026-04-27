import Foundation

/// One row in the clipboard history. `id` is assigned by the database; newly captured
/// entries are built with `id = 0` before insert.
struct ClipEntry: Identifiable, Equatable {
    var id: Int64
    var kind: EntryKind
    var createdAt: Date
    var source: SourceApp?
    var pinnedAt: Date?
    var obfuscatedAt: Date?
    var obfuscationNickname: String?

    var isPinned: Bool { pinnedAt != nil }
    var isObfuscated: Bool { obfuscatedAt != nil }

    /// Text the fuzzy matcher searches against. Always includes the
    /// payload's `plainText`, and — for non-text kinds — appends
    /// descriptive tokens so users can find entries by type keyword
    /// ("image", "file"), dimensions ("400x300"), or filename.
    var searchText: String {
        // Obfuscated entries are searchable only by nickname — the
        // underlying payload is removed from the fuzzy index so typing
        // the password doesn't reveal it via filter.
        if isObfuscated {
            return obfuscationNickname ?? ""
        }
        switch kind {
        case .text, .rtf:
            return kind.plainText
        case .image(_, let w, let h, _):
            // Both `×` (U+00D7) and ASCII `x` so "400x300" and "400×300"
            // both match; the literal word "image" lets users filter by
            // type.
            return "image \(w)×\(h) \(w)x\(h)"
        case .fileURLs(let urls):
            // File paths plus the bare filenames (for quick matches on
            // names without typing parent directories) plus the keywords
            // "file" / "files".
            let paths = urls.map { $0.path }.joined(separator: " ")
            let names = urls.map { $0.lastPathComponent }.joined(separator: " ")
            let keyword = urls.count == 1 ? "file" : "files file"
            return "\(keyword) \(names) \(paths)"
        }
    }
}
