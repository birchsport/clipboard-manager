import AppKit
import Combine

/// Polls `NSPasteboard.general.changeCount` on the main run loop. When it changes we
/// capture the frontmost app, ask the reader for an `EntryKind`, and hand it off to
/// the repository. The watcher also tracks its own writes so we don't re-ingest them,
/// and skips capture entirely when the frontmost app is on the user's ignore list
/// (password managers etc.).
final class ClipboardWatcher {
    private let repository: EntryRepository
    private let reader: ClipboardReader
    private let preferences: Preferences
    private var lastChangeCount: Int
    private var timer: Timer?

    /// O(1) lookup over the current ignore list. Rebuilt whenever
    /// `preferences.ignoredAppBundleIDs` changes.
    private var ignoredBundleIDs: Set<String> = []
    private var preferencesSubscription: AnyCancellable?

    /// Change counts produced by our own writes (`ClipboardWriter`). We skip these so
    /// pasting an old entry doesn't create a duplicate at the top of the list.
    private static var selfProducedChangeCounts = Set<Int>()
    private static let selfProducedLock = NSLock()

    init(repository: EntryRepository, blobStore: BlobStore, preferences: Preferences) {
        self.repository = repository
        self.reader = ClipboardReader(blobStore: blobStore)
        self.preferences = preferences
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.ignoredBundleIDs = Set(preferences.ignoredAppBundleIDs)

        // Keep the cached set in sync when the user edits the ignore list.
        self.preferencesSubscription = preferences.$ignoredAppBundleIDs
            .sink { [weak self] ids in
                self?.ignoredBundleIDs = Set(ids)
            }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func markSelfProduced(changeCount: Int) {
        selfProducedLock.lock(); defer { selfProducedLock.unlock() }
        selfProducedChangeCounts.insert(changeCount)
        // Keep this set tiny — we only need to remember the most recent few.
        if selfProducedChangeCounts.count > 16 {
            selfProducedChangeCounts.removeFirst()
        }
    }

    private static func isSelfProduced(_ changeCount: Int) -> Bool {
        selfProducedLock.lock(); defer { selfProducedLock.unlock() }
        return selfProducedChangeCounts.remove(changeCount) != nil
    }

    private func tick() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if Self.isSelfProduced(current) { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if let bundleID = frontmost?.bundleIdentifier,
           ignoredBundleIDs.contains(bundleID) {
            // Skip silently — whatever's on the pasteboard stays off our record.
            return
        }

        let source = SourceApp(runningApp: frontmost)
        guard let kind = reader.read(pasteboard: pb) else { return }

        do {
            try repository.upsert(kind: kind, source: source)
        } catch {
            NSLog("Birchboard: upsert failed: \(error)")
        }
    }
}
