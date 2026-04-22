import AppKit

/// Polls `NSPasteboard.general.changeCount` on the main run loop. When it changes we
/// capture the frontmost app, ask the reader for an `EntryKind`, and hand it off to
/// the repository. The watcher also tracks its own writes so we don't re-ingest them.
final class ClipboardWatcher {
    private let repository: EntryRepository
    private let reader: ClipboardReader
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Change counts produced by our own writes (`ClipboardWriter`). We skip these so
    /// pasting an old entry doesn't create a duplicate at the top of the list.
    private static var selfProducedChangeCounts = Set<Int>()
    private static let selfProducedLock = NSLock()

    init(repository: EntryRepository, blobStore: BlobStore) {
        self.repository = repository
        self.reader = ClipboardReader(blobStore: blobStore)
        self.lastChangeCount = NSPasteboard.general.changeCount
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

        let source = SourceApp(runningApp: NSWorkspace.shared.frontmostApplication)
        guard let kind = reader.read(pasteboard: pb) else { return }

        do {
            try repository.upsert(kind: kind, source: source)
        } catch {
            NSLog("ClipHistory: upsert failed: \(error)")
        }
    }
}
