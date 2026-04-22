import AppKit
import Combine
import Foundation

/// The panel is a small state machine: ordinary browsing of the history, or
/// picking a transform (`⌘T`) or snippet (`⌘S`). `savedQuery` lets Esc
/// restore the prior browse-mode search text.
enum PanelMode: Equatable {
    case browse
    case transformPicker(source: ClipEntry, savedQuery: String)
    case snippetPicker(savedQuery: String)
}

/// Backing state for `PanelContentView`. Loads entries from the repository, runs the
/// fuzzy filter off-thread when the query changes, and translates keyboard events into
/// either list navigation or actions dispatched through `PanelActions`.
@MainActor
final class PanelViewModel: ObservableObject {
    // MARK: - Browse-mode state

    @Published var query: String = ""
    @Published var entries: [ClipEntry] = []
    @Published var selectedIndex: Int = 0

    /// Bumped every time we want the view to re-focus the search field. Observed via
    /// `.onChange` so each increment fires even when the NSPanel is reopened.
    @Published var focusRequestTick: Int = 0

    // MARK: - Transform-mode state

    @Published var mode: PanelMode = .browse
    @Published var transformQuery: String = ""
    @Published var transformMatches: [any TextTransform] = []
    @Published var transformSelectedIndex: Int = 0
    /// Brief error message when a transform's `apply` returns nil. Cleared
    /// automatically after a short delay or on mode change.
    @Published var transformError: String?

    // MARK: - Snippet-mode state

    @Published var snippetQuery: String = ""
    @Published var snippetMatches: [Snippet] = []
    @Published var snippetSelectedIndex: Int = 0

    // MARK: - Quick Look

    /// Overlay showing a full-size preview of the currently-selected entry.
    /// Toggled with ⌘Y; tracks the selection so Up/Down still navigates while
    /// the overlay is visible.
    @Published var isQuickLookOpen: Bool = false

    let actions: PanelActions
    private let services: Services
    private var allEntries: [ClipEntry] = []
    private var cancellables = Set<AnyCancellable>()

    init(services: Services, actions: PanelActions) {
        self.services = services
        self.actions = actions

        // Refilter whenever the query changes.
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] q in self?.applyFilter(query: q) }
            .store(in: &cancellables)

        // Refresh the full list whenever the repository mutates.
        services.repository.changes
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        // Refilter transforms as the user types in transform mode.
        $transformQuery
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshTransformMatches() }
            .store(in: &cancellables)

        // Refilter snippets as the user types in snippet mode.
        $snippetQuery
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshSnippetMatches() }
            .store(in: &cancellables)

        // Refresh the snippet list whenever the store mutates (e.g. user adds
        // or edits one in Settings while the panel is open).
        services.snippetStore.$snippets
            .sink { [weak self] _ in self?.refreshSnippetMatches() }
            .store(in: &cancellables)

        refresh()
    }

    func refresh() {
        allEntries = services.repository.allEntries()
        applyFilter(query: query)
    }

    func focusSearchField() {
        query = ""
        selectedIndex = 0
        mode = .browse
        transformError = nil
        isQuickLookOpen = false
        focusRequestTick &+= 1
    }

    func toggleQuickLook() {
        isQuickLookOpen.toggle()
    }

    var selectedEntry: ClipEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    // MARK: - Filtering (browse)

    private func applyFilter(query: String) {
        let snapshot = allEntries
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.entries = snapshot
            self.selectedIndex = min(selectedIndex, max(0, snapshot.count - 1))
            return
        }

        // Off-main filter — keeps typing smooth with large histories.
        Task.detached(priority: .userInitiated) {
            let filtered = FuzzyMatcher.filter(snapshot, query: query)
            await MainActor.run {
                self.entries = filtered
                self.selectedIndex = filtered.isEmpty ? 0 : 0
            }
        }
    }

    // MARK: - Transform mode

    /// Enter the transform picker for the currently selected entry. No-op if
    /// nothing is selected or the entry is not transformable.
    func enterTransformMode() {
        guard let entry = selectedEntry else { return }
        guard isTransformable(entry) else { return }
        let savedQuery = query
        mode = .transformPicker(source: entry, savedQuery: savedQuery)
        transformQuery = ""
        transformSelectedIndex = 0
        transformError = nil
        refreshTransformMatches()
        focusRequestTick &+= 1
    }

    /// Exit back to browse mode, restoring the previously-typed search query.
    func exitTransformMode() {
        if case .transformPicker(_, let savedQuery) = mode {
            query = savedQuery
        }
        mode = .browse
        transformError = nil
        focusRequestTick &+= 1
    }

    private func isTransformable(_ entry: ClipEntry) -> Bool {
        switch entry.kind {
        case .text, .rtf:
            return !entry.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image, .fileURLs:
            return false
        }
    }

    private func refreshTransformMatches() {
        guard case .transformPicker(let source, _) = mode else {
            transformMatches = []
            return
        }
        let applicable = TransformRegistry.applicable(to: source.searchText)
        let trimmed = transformQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            transformMatches = applicable
        } else {
            let scored: [(t: any TextTransform, score: Int, order: Int)] = applicable
                .enumerated()
                .compactMap { idx, t in
                    guard let s = FuzzyMatcher.score(query: trimmed, candidate: t.displayName) else {
                        return nil
                    }
                    return (t, s, idx)
                }
            transformMatches = scored
                .sorted { a, b in
                    if a.score != b.score { return a.score > b.score }
                    return a.order < b.order
                }
                .map { $0.t }
        }

        if transformSelectedIndex >= transformMatches.count {
            transformSelectedIndex = max(0, transformMatches.count - 1)
        }
    }

    var selectedTransform: (any TextTransform)? {
        transformMatches.indices.contains(transformSelectedIndex)
            ? transformMatches[transformSelectedIndex]
            : nil
    }

    // MARK: - Snippet mode

    func enterSnippetMode() {
        // Refuse to stack picker modes on top of each other.
        guard case .browse = mode else { return }
        let savedQuery = query
        mode = .snippetPicker(savedQuery: savedQuery)
        snippetQuery = ""
        snippetSelectedIndex = 0
        refreshSnippetMatches()
        focusRequestTick &+= 1
    }

    func exitSnippetMode() {
        if case .snippetPicker(let savedQuery) = mode {
            query = savedQuery
        }
        mode = .browse
        focusRequestTick &+= 1
    }

    private func refreshSnippetMatches() {
        let all = services.snippetStore.snippets
        let trimmed = snippetQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            snippetMatches = all
        } else {
            let scored: [(s: Snippet, score: Int, order: Int)] = all
                .enumerated()
                .compactMap { idx, s in
                    guard let score = FuzzyMatcher.score(
                        query: trimmed,
                        candidate: s.displayName
                    ) else { return nil }
                    return (s, score, idx)
                }
            snippetMatches = scored
                .sorted { a, b in
                    if a.score != b.score { return a.score > b.score }
                    return a.order < b.order
                }
                .map { $0.s }
        }

        if snippetSelectedIndex >= snippetMatches.count {
            snippetSelectedIndex = max(0, snippetMatches.count - 1)
        }
    }

    var selectedSnippet: Snippet? {
        snippetMatches.indices.contains(snippetSelectedIndex)
            ? snippetMatches[snippetSelectedIndex]
            : nil
    }

    /// Live-expanded preview of the currently-selected snippet. Reads the
    /// current pasteboard so `{clipboard}` shows the real value the user
    /// would get on paste.
    func previewForSelectedSnippet() -> String? {
        guard let snippet = selectedSnippet else { return nil }
        let clipboardText = NSPasteboard.general.string(forType: .string)
        return SnippetPlaceholders.expand(snippet.body, clipboard: clipboardText)
    }

    /// Expand `snippet`'s placeholders against the current pasteboard and
    /// paste via the normal paste flow as a one-shot synthetic entry.
    func applySnippet(_ snippet: Snippet) {
        // Read the current clipboard BEFORE we overwrite it.
        let clipboardText = NSPasteboard.general.string(forType: .string)
        let expanded = SnippetPlaceholders.expand(snippet.body,
                                                  clipboard: clipboardText)

        let entry = ClipEntry(
            id: 0,
            kind: .text(expanded),
            createdAt: Date(),
            source: nil,
            pinnedAt: nil
        )

        mode = .browse
        actions.paste(entry, asPlainText: false)
    }

    /// Apply `transform` to the entry we entered transform mode for, then kick
    /// the normal paste flow. On failure, show an inline error and stay in
    /// transform mode.
    func applyTransform(_ transform: any TextTransform) {
        guard case .transformPicker(let source, _) = mode else { return }
        guard let output = transform.apply(to: source.searchText) else {
            showTransformError("“\(transform.displayName)” produced no result.")
            return
        }

        var transformed = source
        transformed.kind = source.kind.withReplacedText(output)

        // Reset mode *before* paste so the panel's hide() doesn't leave us in
        // transform mode when reopened.
        mode = .browse
        transformError = nil

        actions.paste(transformed, asPlainText: false)
    }

    private func showTransformError(_ message: String) {
        transformError = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            if self.transformError == message {
                self.transformError = nil
            }
        }
    }

    // MARK: - Keyboard handling

    /// Called by the panel controller's local event monitor while the panel is key.
    /// Returns true to consume the event, false to let the text field handle it.
    func handle(event: NSEvent) -> Bool {
        switch mode {
        case .browse:
            return handleBrowse(event: event)
        case .transformPicker:
            return handleTransform(event: event)
        case .snippetPicker:
            return handleSnippet(event: event)
        }
    }

    private func handleBrowse(event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)

        // ⌘1–⌘9: paste the Nth visible entry. ⇧⌘N pastes plain text.
        // Keycode-based so Shift's character-remap (1→!, etc.) doesn't break it.
        if cmd, let digit = Self.digitForTopRowKeyCode[event.keyCode] {
            let idx = digit - 1
            if entries.indices.contains(idx) {
                actions.paste(entries[idx], asPlainText: shift)
            }
            return true
        }

        switch event.keyCode {
        case 53: // Esc
            if isQuickLookOpen {
                isQuickLookOpen = false
            } else {
                actions.dismiss()
            }
            return true
        case 125: // Down
            moveSelection(+1); return true
        case 126: // Up
            moveSelection(-1); return true
        case 36, 76: // Return / numpad Enter
            if let entry = selectedEntry {
                actions.paste(entry, asPlainText: shift)
            }
            return true
        case 16: // Y — ⌘Y toggles Quick Look
            if cmd {
                toggleQuickLook()
                return true
            }
            return false
        case 17: // T — ⌘T enters transform mode
            if cmd {
                enterTransformMode()
                return true
            }
            return false
        case 1: // S — ⌘S enters snippet mode
            if cmd {
                enterSnippetMode()
                return true
            }
            return false
        case 35: // P — ⌘P pins
            if cmd, let entry = selectedEntry {
                actions.togglePin(entry)
                return true
            }
            return false
        case 51: // Delete/backspace
            if cmd, let entry = selectedEntry {
                actions.delete(entry)
                return true
            }
            return false
        default:
            return false
        }
    }

    private func handleTransform(event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            exitTransformMode()
            return true
        case 125: // Down
            moveTransformSelection(+1); return true
        case 126: // Up
            moveTransformSelection(-1); return true
        case 36, 76: // Return
            if let t = selectedTransform {
                applyTransform(t)
            }
            return true
        default:
            return false
        }
    }

    private func handleSnippet(event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            exitSnippetMode()
            return true
        case 125: // Down
            moveSnippetSelection(+1); return true
        case 126: // Up
            moveSnippetSelection(-1); return true
        case 36, 76: // Return
            if let s = selectedSnippet {
                applySnippet(s)
            }
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = max(0, min(entries.count - 1, selectedIndex + delta))
    }

    private func moveTransformSelection(_ delta: Int) {
        guard !transformMatches.isEmpty else { return }
        transformSelectedIndex = max(0, min(transformMatches.count - 1,
                                            transformSelectedIndex + delta))
    }

    private func moveSnippetSelection(_ delta: Int) {
        guard !snippetMatches.isEmpty else { return }
        snippetSelectedIndex = max(0, min(snippetMatches.count - 1,
                                          snippetSelectedIndex + delta))
    }

    /// Physical top-row number keycodes (stable across US/AZERTY/DVORAK) →
    /// their visual digit. Used by ⌘N quick-select.
    private static let digitForTopRowKeyCode: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]
}
