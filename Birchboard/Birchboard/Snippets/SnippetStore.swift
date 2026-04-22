import Foundation
import SwiftUI

/// Owns the user's snippet list. Publishes on every mutation so the Settings
/// tab and the panel picker stay in sync without wiring Combine pipelines.
/// Serialised to `UserDefaults` under a versioned key.
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []

    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard, key: String = "snippets.v1") {
        self.defaults = defaults
        self.key = key
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        load()
    }

    // MARK: - Mutations

    @discardableResult
    func add(name: String = "", body: String = "") -> Snippet {
        let snippet = Snippet(name: name, body: body)
        snippets.append(snippet)
        persist()
        return snippet
    }

    func update(_ snippet: Snippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var updated = snippet
        updated.updatedAt = Date()
        snippets[idx] = updated
        persist()
    }

    func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        snippets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Queries

    func snippet(withID id: UUID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        do {
            snippets = try decoder.decode([Snippet].self, from: data)
        } catch {
            NSLog("Birchboard: failed to decode snippets: \(error)")
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(snippets)
            defaults.set(data, forKey: key)
        } catch {
            NSLog("Birchboard: failed to encode snippets: \(error)")
        }
    }
}
