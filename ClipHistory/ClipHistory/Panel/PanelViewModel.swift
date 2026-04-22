import AppKit
import Combine
import Foundation

/// Backing state for `PanelContentView`. Loads entries from the repository, runs the
/// fuzzy filter off-thread when the query changes, and translates keyboard events into
/// either list navigation or actions dispatched through `PanelActions`.
@MainActor
final class PanelViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var entries: [ClipEntry] = []
    @Published var selectedIndex: Int = 0
    /// Bumped every time we want the view to re-focus the search field. Observed via
    /// `.onChange` so each increment fires even when the NSPanel is reopened.
    @Published var focusRequestTick: Int = 0

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

        refresh()
    }

    func refresh() {
        allEntries = services.repository.allEntries()
        applyFilter(query: query)
    }

    func focusSearchField() {
        query = ""
        selectedIndex = 0
        focusRequestTick &+= 1
    }

    var selectedEntry: ClipEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    // MARK: - Filtering

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

    // MARK: - Keyboard handling

    /// Called by the panel controller's local event monitor while the panel is key.
    /// Returns true to consume the event, false to let the text field handle it.
    func handle(event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)

        switch event.keyCode {
        case 53: // Esc
            actions.dismiss()
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

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let next = max(0, min(entries.count - 1, selectedIndex + delta))
        selectedIndex = next
    }
}
