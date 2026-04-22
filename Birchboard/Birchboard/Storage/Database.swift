import Foundation
import GRDB

/// Thin GRDB wrapper: owns the `DatabasePool` and runs migrations on open.
final class Database {
    let pool: DatabasePool

    init(url: URL) throws {
        var config = Configuration()
        config.label = "Birchboard.db"
        self.pool = try DatabasePool(path: url.path, configuration: config)
        try migrator.migrate(pool)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_entries") { db in
            try db.create(table: "entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .integer).notNull()
                t.column("text", .text)
                t.column("rtf_data", .blob)
                t.column("blob_path", .text)
                t.column("image_width", .integer)
                t.column("image_height", .integer)
                t.column("image_hash", .text)
                t.column("file_urls", .text) // JSON array of absolute URLs
                t.column("search_text", .text).notNull().defaults(to: "")
                t.column("dedup_hash", .text).notNull().indexed()
                t.column("source_bundle_id", .text)
                t.column("source_name", .text)
                t.column("created_at", .datetime).notNull().indexed()
                t.column("pinned_at", .datetime).indexed()
            }
        }

        return m
    }
}
