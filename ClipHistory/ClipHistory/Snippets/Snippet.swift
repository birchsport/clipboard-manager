import Foundation

/// A user-authored text snippet. Pasted via the panel's snippet picker (⌘S)
/// after placeholder expansion. Persisted as part of a JSON blob in
/// `UserDefaults` — no schema migration required to add a field.
struct Snippet: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         body: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Used in the picker and settings list when the user hasn't named one.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
