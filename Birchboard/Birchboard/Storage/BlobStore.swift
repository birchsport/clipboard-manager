import Foundation

/// Content-addressed filesystem store for binary blobs (images). Keeps the SQLite
/// database small by keeping only a path reference in the `entries` table.
final class BlobStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes `data` into `<root>/<hash>.<ext>` and returns the resulting URL.
    /// Idempotent: if the file already exists we skip the write.
    func store(data: Data, hash: String, ext: String) throws -> URL {
        let url = url(forHash: hash, ext: ext)
        if !fm.fileExists(atPath: url.path) {
            try data.write(to: url, options: [.atomic])
        }
        return url
    }

    func url(forHash hash: String, ext: String) -> URL {
        root.appendingPathComponent("\(hash).\(ext)")
    }

    /// Removes a single blob; silently ignores missing files.
    func delete(at url: URL) {
        try? fm.removeItem(at: url)
    }

    /// Deletes blobs that no entry in `referencedPaths` references. Called from the
    /// retention sweep so orphans from deleted rows get cleaned up.
    func pruneUnreferenced(referencedPaths: Set<String>) {
        guard let entries = try? fm.contentsOfDirectory(at: root,
                                                        includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries where !referencedPaths.contains(entry.path) {
            try? fm.removeItem(at: entry)
        }
    }
}
