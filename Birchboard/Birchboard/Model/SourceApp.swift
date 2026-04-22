import AppKit

/// Describes the application that produced a clipboard entry. The icon is looked up
/// lazily via `IconCache` to avoid bloating the database.
struct SourceApp: Equatable, Hashable {
    let bundleID: String
    let name: String

    init?(runningApp: NSRunningApplication?) {
        guard let app = runningApp,
              let bundleID = app.bundleIdentifier else { return nil }
        self.bundleID = bundleID
        self.name = app.localizedName ?? bundleID
    }

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    var icon: NSImage? { IconCache.shared.icon(forBundleID: bundleID) }
}

/// Process-wide cache so we don't hit the workspace repeatedly for the same bundle.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(forBundleID bundleID: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 18, height: 18)
        cache[bundleID] = image
        return image
    }
}
