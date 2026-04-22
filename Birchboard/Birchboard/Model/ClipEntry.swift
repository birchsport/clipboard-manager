import Foundation

/// One row in the clipboard history. `id` is assigned by the database; newly captured
/// entries are built with `id = 0` before insert.
struct ClipEntry: Identifiable, Equatable {
    var id: Int64
    var kind: EntryKind
    var createdAt: Date
    var source: SourceApp?
    var pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    /// Text used for searching and list row previews.
    var searchText: String { kind.plainText }
}
