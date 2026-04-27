import Foundation
import GRDB
import Combine

/// The app's single read/write gateway to the `entries` table. All mutations flow
/// through here so observers (the panel view model) can be notified via `changes`.
///
/// Safe to use from any thread: GRDB's `DatabasePool` serialises access
/// internally and `PassthroughSubject` publishes are likewise thread-safe.
/// Marked `@unchecked Sendable` so background `Task.detached` work (export /
/// import) can call through without actor-isolation warnings.
final class EntryRepository: @unchecked Sendable {
    private let database: Database
    private let blobStore: BlobStore
    private let subject = PassthroughSubject<Void, Never>()

    /// Emits every time the entries table changes (insert / update / delete).
    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    init(database: Database, blobStore: BlobStore) {
        self.database = database
        self.blobStore = blobStore
    }

    // MARK: - Reads

    /// Fetches all entries sorted `(pinned first, then newest first)`.
    func allEntries() -> [ClipEntry] {
        (try? database.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM entries
                ORDER BY (pinned_at IS NOT NULL) DESC,
                         pinned_at DESC,
                         created_at DESC
                """)
        }.map(Self.entry(from:))) ?? []
    }

    // MARK: - Writes

    /// Inserts a new entry for `kind`, or bumps `created_at` on the matching dedup row.
    func upsert(kind: EntryKind, source: SourceApp?) throws {
        let hash = kind.dedupHash
        let now = Date()
        try database.pool.write { db in
            if let id = try Int64.fetchOne(db, sql: "SELECT id FROM entries WHERE dedup_hash = ? LIMIT 1", arguments: [hash]) {
                try db.execute(sql: "UPDATE entries SET created_at = ? WHERE id = ?",
                               arguments: [now, id])
            } else {
                try Self.insert(kind: kind, source: source, createdAt: now, hash: hash, db: db)
            }
        }
        subject.send()
    }

    func delete(id: Int64) throws {
        try database.pool.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT blob_path FROM entries WHERE id = ?", arguments: [id]),
               let path: String = row["blob_path"] {
                self.blobStore.delete(at: URL(fileURLWithPath: path))
            }
            try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [id])
        }
        subject.send()
    }

    func togglePin(id: Int64) throws {
        try database.pool.write { db in
            if let pinned = try Bool.fetchOne(db, sql: "SELECT pinned_at IS NOT NULL FROM entries WHERE id = ?", arguments: [id]) {
                if pinned {
                    try db.execute(sql: "UPDATE entries SET pinned_at = NULL WHERE id = ?",
                                   arguments: [id])
                } else {
                    try db.execute(sql: "UPDATE entries SET pinned_at = ? WHERE id = ?",
                                   arguments: [Date(), id])
                }
            }
        }
        subject.send()
    }

    /// Toggles obfuscation on `id`. Toggling off clears the nickname so
    /// re-obfuscating later starts fresh.
    func toggleObfuscation(id: Int64) throws {
        try database.pool.write { db in
            if let obfuscated = try Bool.fetchOne(db, sql: "SELECT obfuscated_at IS NOT NULL FROM entries WHERE id = ?", arguments: [id]) {
                if obfuscated {
                    try db.execute(sql: "UPDATE entries SET obfuscated_at = NULL, obfuscation_nickname = NULL WHERE id = ?",
                                   arguments: [id])
                } else {
                    try db.execute(sql: "UPDATE entries SET obfuscated_at = ? WHERE id = ?",
                                   arguments: [Date(), id])
                }
            }
        }
        subject.send()
    }

    /// Sets the user-supplied display nickname for an obfuscated entry.
    /// Pass nil/empty to clear it (entry stays obfuscated, just no label).
    func setObfuscationNickname(id: Int64, _ nickname: String?) throws {
        let cleaned = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (cleaned?.isEmpty ?? true) ? nil : cleaned
        try database.pool.write { db in
            try db.execute(sql: "UPDATE entries SET obfuscation_nickname = ? WHERE id = ?",
                           arguments: [value, id])
        }
        subject.send()
    }

    func clearAll() throws {
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM entries")
        }
        blobStore.pruneUnreferenced(referencedPaths: [])
        subject.send()
    }

    func clearUnpinned() throws {
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM entries WHERE pinned_at IS NULL AND obfuscated_at IS NULL")
        }
        pruneBlobs()
        subject.send()
    }

    // MARK: - Archive (export / import)

    /// Summary returned from an import so the UI can tell the user what
    /// happened.
    struct ImportSummary {
        let imported: Int
        let skippedDuplicates: Int
    }

    /// Build an in-memory archive of every entry. Image entries load their
    /// blob bytes so the archive is self-contained.
    func exportArchive() throws -> HistoryArchive {
        let entries = allEntries()
        var archived: [ArchivedEntry] = []
        archived.reserveCapacity(entries.count)
        for entry in entries {
            // If an image blob is missing on disk, skip the entry rather
            // than explode — the DB reference is stale. Rare in practice.
            do {
                let a = try ArchivedEntry(from: entry) { url in
                    try Data(contentsOf: url)
                }
                archived.append(a)
            } catch {
                NSLog("Birchboard: skipping entry \(entry.id) during export: \(error)")
            }
        }
        return HistoryArchive(entries: archived)
    }

    /// Restore `archive` into the database. Entries whose `dedup_hash`
    /// already exists are counted as duplicates and skipped — the caller
    /// sees them in the returned `ImportSummary`.
    @discardableResult
    func importArchive(_ archive: HistoryArchive) throws -> ImportSummary {
        var imported = 0
        var skipped = 0

        for entry in archive.entries {
            let inserted = try database.pool.write { db -> Bool in
                // Dedup by hash.
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM entries WHERE dedup_hash = ?)",
                    arguments: [entry.dedupHash]
                ) ?? false
                if exists { return false }

                try Self.insertArchived(entry, blobStore: blobStore, db: db)
                return true
            }
            if inserted { imported += 1 } else { skipped += 1 }
        }
        subject.send()
        return ImportSummary(imported: imported, skippedDuplicates: skipped)
    }

    private static func insertArchived(_ entry: ArchivedEntry,
                                       blobStore: BlobStore,
                                       db: GRDB.Database) throws {
        var text: String?
        var rtf: Data?
        var blobPath: String?
        var width: Int?
        var height: Int?
        var imageHash: String?
        var fileURLsJSON: String?

        switch entry.kind {
        case .text:
            text = entry.text ?? ""
        case .rtf:
            rtf = entry.rtfData
            text = entry.text ?? ""
        case .image:
            guard let png = entry.imagePNG,
                  let hash = entry.imageHash else { return }
            let url = try blobStore.store(data: png, hash: hash, ext: "png")
            blobPath = url.path
            width = entry.imageWidth
            height = entry.imageHeight
            imageHash = hash
        case .fileURLs:
            let strings = entry.fileURLs ?? []
            if let data = try? JSONSerialization.data(withJSONObject: strings, options: []) {
                fileURLsJSON = String(data: data, encoding: .utf8)
            }
        }

        let searchText: String = {
            switch entry.kind {
            case .text, .rtf: return entry.text ?? ""
            case .image:      return ""
            case .fileURLs:   return (entry.fileURLs ?? []).joined(separator: "\n")
            }
        }()

        try db.execute(sql: """
            INSERT INTO entries
            (kind, text, rtf_data, blob_path, image_width, image_height, image_hash,
             file_urls, search_text, dedup_hash, source_bundle_id, source_name,
             created_at, pinned_at, obfuscated_at, obfuscation_nickname)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                entry.kind.rawValue,
                text,
                rtf,
                blobPath,
                width,
                height,
                imageHash,
                fileURLsJSON,
                searchText,
                entry.dedupHash,
                entry.sourceBundleID,
                entry.sourceName,
                entry.createdAt,
                entry.pinnedAt,
                entry.obfuscatedAt,
                entry.obfuscationNickname,
            ])
    }

    // MARK: - Retention

    /// Trims by count and age; pinned and obfuscated rows are never removed.
    /// Then prunes orphan blobs.
    func runRetentionSweep(preferences: Preferences) {
        let maxCount = preferences.retentionCount
        let maxAgeDays = preferences.retentionDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date.distantPast
        do {
            try database.pool.write { db in
                // Age-based trim.
                try db.execute(sql: """
                    DELETE FROM entries
                    WHERE pinned_at IS NULL AND obfuscated_at IS NULL AND created_at < ?
                    """, arguments: [cutoff])

                // Count-based trim (unpinned + non-obfuscated only).
                let unpinnedCount = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM entries WHERE pinned_at IS NULL AND obfuscated_at IS NULL") ?? 0
                if unpinnedCount > maxCount {
                    let overflow = unpinnedCount - maxCount
                    try db.execute(sql: """
                        DELETE FROM entries
                        WHERE id IN (
                            SELECT id FROM entries
                            WHERE pinned_at IS NULL AND obfuscated_at IS NULL
                            ORDER BY created_at ASC
                            LIMIT ?
                        )
                        """, arguments: [overflow])
                }
            }
            pruneBlobs()
            subject.send()
        } catch {
            NSLog("Birchboard: retention sweep failed: \(error)")
        }
    }

    private func pruneBlobs() {
        let paths: Set<String> = (try? database.pool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT blob_path FROM entries WHERE blob_path IS NOT NULL"))
        }) ?? []
        blobStore.pruneUnreferenced(referencedPaths: paths)
    }

    // MARK: - Row mapping

    private static func insert(kind: EntryKind,
                               source: SourceApp?,
                               createdAt: Date,
                               hash: String,
                               db: GRDB.Database) throws {
        var text: String?
        var rtf: Data?
        var blobPath: String?
        var width: Int?
        var height: Int?
        var imageHash: String?
        var fileURLsJSON: String?

        switch kind {
        case .text(let s):
            text = s
        case .rtf(let data, let plain):
            rtf = data
            text = plain
        case .image(let path, let w, let h, let ih):
            blobPath = path.path
            width = w
            height = h
            imageHash = ih
        case .fileURLs(let urls):
            let strings = urls.map { $0.absoluteString }
            if let data = try? JSONSerialization.data(withJSONObject: strings, options: []) {
                fileURLsJSON = String(data: data, encoding: .utf8)
            }
        }

        try db.execute(sql: """
            INSERT INTO entries
            (kind, text, rtf_data, blob_path, image_width, image_height, image_hash,
             file_urls, search_text, dedup_hash, source_bundle_id, source_name,
             created_at, pinned_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            """, arguments: [
                kind.tag,
                text,
                rtf,
                blobPath,
                width,
                height,
                imageHash,
                fileURLsJSON,
                kind.plainText,
                hash,
                source?.bundleID,
                source?.name,
                createdAt,
            ])
    }

    private static func entry(from row: Row) -> ClipEntry {
        let tag: Int = row["kind"] ?? 0
        let kind: EntryKind = {
            switch tag {
            case 0:
                return .text(row["text"] ?? "")
            case 1:
                let data: Data = row["rtf_data"] ?? Data()
                let plain: String = row["text"] ?? ""
                return .rtf(data, plainText: plain)
            case 2:
                let path: String = row["blob_path"] ?? ""
                return .image(blobPath: URL(fileURLWithPath: path),
                              width: row["image_width"] ?? 0,
                              height: row["image_height"] ?? 0,
                              hash: row["image_hash"] ?? "")
            case 3:
                let json: String = row["file_urls"] ?? "[]"
                let urls: [URL] = (try? JSONSerialization.jsonObject(with: Data(json.utf8)))
                    .flatMap { $0 as? [String] }?
                    .compactMap { URL(string: $0) } ?? []
                return .fileURLs(urls)
            default:
                return .text("")
            }
        }()

        let source: SourceApp? = {
            if let bid: String = row["source_bundle_id"],
               let name: String = row["source_name"] {
                return SourceApp(bundleID: bid, name: name)
            }
            return nil
        }()

        return ClipEntry(id: row["id"] ?? 0,
                         kind: kind,
                         createdAt: row["created_at"] ?? Date(),
                         source: source,
                         pinnedAt: row["pinned_at"],
                         obfuscatedAt: row["obfuscated_at"],
                         obfuscationNickname: row["obfuscation_nickname"])
    }
}
