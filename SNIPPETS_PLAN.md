# Plan: Snippets

## Context

Snippets are user-authored canned text you can paste without having first
copied it. Alfred and Raycast both treat snippets as a first-class feature —
one of the top reasons people pay for a launcher-ish tool. Adding them to
Birchboard turns it from "history only" into "history + vocabulary".

This plan scopes a v1 that's genuinely useful without ballooning into
auto-expansion territory (which requires watching global keystrokes via
Accessibility, a significant complexity and trust surcharge).

Intended outcome:
- `⌘S` inside the panel switches to a snippet picker — fuzzy search by name,
  ⏎ expands placeholders and pastes exactly like any other clipboard entry.
- A Settings tab lets the user CRUD their snippets.
- A small placeholder language (`{clipboard}`, `{date}`, `{uuid}`) makes the
  boring snippets (email openers, stock responses) dramatically more useful.

## Scope (v1)

**In:**
- Named snippets: a `name` (shown in the picker) and a multi-line `body`.
- Panel integration: ⌘S enters `.snippetPicker` mode, analogous to `.transformPicker`.
- Settings UI: list + add/edit/delete, reordering by drag.
- Placeholder expansion on paste: `{clipboard}`, `{date[:FMT]}`, `{time[:FMT]}`,
  `{uuid}`, `{newline}`, `{tab}`.
- Persistence: JSON blob in `UserDefaults` (same style as `Preferences`). A
  small file-based export/import can come later.
- Source-app attribution at paste time mimics the normal paste flow (uses the
  previous frontmost app stored by `PanelController`).

**Out (deferred to v2+):**
- **Auto-expansion while typing** — e.g. ";addr" expands to your address as you
  type it. Needs a global keystroke monitor (AX-trust + real engineering for
  the trie-based matcher + whitelist of which apps to expand in). The panel
  picker handles 80% of the value at 20% of the cost.
- **`{cursor}` placeholder** — deterministic cursor positioning requires
  app-specific AX queries. Punt.
- **Snippet collections / folders** — a single flat list is enough for v1.
- **Rich-text snippets** — text-only for now.
- **Sync / export / import** — JSON export is easy and can be added later.
- **Variable prompts** ("ask me for the customer name") — too fiddly for v1.

## Architecture

### New module: `Snippets/`

`Birchboard/Birchboard/Snippets/Snippet.swift`
```swift
struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
}
```
A plain value type. The `id` is stable across edits so the picker can keep a
selection as the user edits in Settings.

`Birchboard/Birchboard/Snippets/SnippetStore.swift`
```swift
@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    private let defaults: UserDefaults
    private let key = "snippets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(name: String, body: String) -> Snippet { … }
    func update(_ snippet: Snippet) { … }
    func remove(id: UUID) { … }
    func move(from source: IndexSet, to destination: Int) { … }

    private func load() { … }      // decode [Snippet] from defaults
    private func persist() { … }   // encode + write (called from each mutator)
}
```
Single source of truth. Lives on `Services` (next to `preferences`).

`Birchboard/Birchboard/Snippets/SnippetPlaceholders.swift`
```swift
enum SnippetPlaceholders {
    /// Expand `{clipboard}`, `{date[:FMT]}`, `{time[:FMT]}`, `{uuid}`,
    /// `{newline}`, `{tab}`. Anything else is left literal.
    static func expand(_ body: String, clipboard: String?) -> String
}
```
A single regex pass over `\{[^}]+\}` tokens, with a small switch on the
token's prefix. No templating engine; no loops/conditionals.

### Panel integration

`PanelViewModel`
- Extend `PanelMode` with a third case:
  ```swift
  case snippetPicker(savedQuery: String)
  ```
  (No "source" payload — snippets are selected in their own right, not
  applied over an existing entry.)
- Add parallel state: `@Published var snippetQuery: String`,
  `@Published var snippetMatches: [Snippet]`,
  `@Published var snippetSelectedIndex: Int`.
- `enterSnippetMode()`, `exitSnippetMode()`, `applySnippet(_:)`.
- `handleSnippet(event:)` mirrors `handleTransform`: Esc exits, ↑/↓ navigates,
  ⏎ applies + pastes, anything else flows to the text field.
- `handleBrowse` gets a `case 1: // S` (keycode) block: `⌘S` enters snippet
  mode.

`PanelContentView`
- The mode switch that already chooses between `EntryListView` and
  `TransformPickerView` gets a third branch for a new `SnippetPickerView`.
- Search field placeholder/icon swaps: "Find snippet…" and a `text.badge.plus`
  glyph so the user sees the mode.
- Preview column in snippet mode shows a live-expanded preview of the selected
  snippet's body (so `{date}` actually shows today's date).

`SnippetPickerView.swift`
- Structurally mirrors `TransformPickerView` (list of rows, error bar area).
- Row: name (primary) + first ~60 chars of body (muted secondary). Consistent
  with `EntryRow`'s visual weight so the panel doesn't feel bolted-on.

### Paste integration

`applySnippet(_:)` builds a one-shot `ClipEntry`:
1. Read current pasteboard's text so `{clipboard}` can expand to whatever was
   copied before the user opened the panel. (Important: read before we write
   anything to it.)
2. `let expanded = SnippetPlaceholders.expand(body, clipboard: currentText)`.
3. Build a synthetic entry:
   ```swift
   var entry = ClipEntry(id: 0, kind: .text(expanded),
                         createdAt: Date(), source: nil, pinnedAt: nil)
   ```
4. Hand to the existing `actions.paste(entry, asPlainText: false)` — same
   activation + ⌘V post flow. No new paste path.

### Services wiring

`AppDelegate.Services` adds `let snippetStore = SnippetStore()`. Wired through
the same `environmentObject(appDelegate.services.snippetStore)` propagation
the Settings window already uses for `preferences`.

### Settings UI

New tab `SnippetsTab.swift` in `Settings/`, placed between General and Hotkey.
Layout:
- Left column: list of snippets with reorder handle + delete button. `+`
  button below adds a new one (blank name and body, auto-focus the name field).
- Right column: editor for the selected snippet — name `TextField`, body
  `TextEditor` (multi-line, monospaced), last-updated timestamp, a small
  "Available placeholders" legend.
- Changes persist on each keystroke (debounced, via `SnippetStore.update`).

## UX flow

1. User opens the panel (⌘⇧V). Browse mode as usual.
2. User hits ⌘S. Mode switches: left column becomes the snippet list, search
   bar swaps to "Find snippet…", preview pane shows the selected snippet's
   expanded body.
3. User types ("addr", "sig", "signoff") — fuzzy filter over snippet name.
4. ↑/↓ navigates. Preview live-updates.
5. ⏎ expands placeholders and pastes via the normal paste flow. Panel
   dismisses.
6. Esc cancels, restoring prior browse-mode query.

## Placeholder language

| Token                    | Expands to                                     |
| ------------------------ | ---------------------------------------------- |
| `{clipboard}`            | Current pasteboard text, or empty string       |
| `{date}`                 | `yyyy-MM-dd`                                   |
| `{date:FMT}`             | `FMT` applied via `DateFormatter`              |
| `{time}`                 | `HH:mm:ss`                                     |
| `{time:FMT}`             | `FMT` applied via `DateFormatter`              |
| `{uuid}`                 | A new `UUID().uuidString` per expansion        |
| `{newline}`              | `\n` (convenience for template-literal authors)|
| `{tab}`                  | `\t`                                           |
| `{{`                     | Literal `{`                                    |
| `}}`                     | Literal `}`                                    |

Unknown tokens (`{made_up}`) pass through unchanged — users shouldn't be
punished for typos with silent deletions.

## Build sequence

Each step leaves the app buildable and testable.

1. Add `Snippet.swift` + `SnippetStore.swift` + `SnippetPlaceholders.swift`.
   Services exposes `snippetStore`. No UI yet. Confirm compilation.
2. Add Settings tab for CRUD. No panel integration yet — the user can add
   snippets but can't use them. Confirm adding / editing / deleting /
   reordering all persist across relaunch.
3. Extend `PanelMode` + view-model parallel state + `handleSnippet`. Still no
   UI. Confirm compilation.
4. Add `SnippetPickerView.swift` and the mode switch in `PanelContentView`.
   Confirm ⌘S opens the picker and fuzzy filtering works.
5. Wire paste: `applySnippet` builds the synthetic entry, runs placeholder
   expansion, hands to `actions.paste`. End-to-end: create a snippet, open
   panel, ⌘S, pick it, verify it pastes into the target app.
6. Polish: live preview pane with expansion applied; empty states; a small
   "recently used" sort option; README updates.

Estimated: ~500–650 LOC across 5 new files + ~60 LOC edits in 4 existing
files. Larger than transforms because of the Settings editor, which is
inherently form-heavy.

## Verification

End-to-end manual tests after step 5 and again after step 6:

1. **CRUD.** Add "signoff" with body "Best,\nJames". Edit it. Delete it.
   Re-launch the app — verify each state persists.
2. **Basic paste.** Snippet "hello" with body "Hi there". ⌘⇧V → ⌘S → type
   "hello" → ⏎. Target app shows "Hi there".
3. **Clipboard placeholder.** Snippet "reply" with body "Thanks for {clipboard}!".
   Copy "the link" in another app. ⌘⇧V → ⌘S → "reply" → ⏎. Target shows
   "Thanks for the link!".
4. **Date placeholders.** `Meeting {date}` → `Meeting 2026-04-22`.
   `Logged at {time:HH:mm}` → `Logged at 03:04`.
5. **UUID.** Each application of the same snippet produces a different UUID.
6. **Escape braces.** `use {{} literally` → `use {} literally`.
7. **Unknown tokens.** `Hi {name}` (no such placeholder) → `Hi {name}` —
   passes through, no error.
8. **Fuzzy search.** Snippets "address" and "signoff"; typing "sig" ranks
   `signoff` top.
9. **Esc restores prior query.** Type "john" in browse mode, ⌘S, pick nothing,
   Esc. Search field shows "john" again.
10. **Focus persists across mode switches.** Same `focusRequestTick` pattern
    used by transforms — confirm.
11. **Reorder.** Drag a snippet in settings; new order reflected in the
    picker immediately.
12. **Big bodies.** Paste a 10KB snippet — no pauses, no truncation.
13. **Non-text active app.** Open panel over Finder, pick snippet, ⏎ —
    should silently no-op (Finder doesn't accept ⌘V text paste) but not
    crash.

Rebuild + smoke tests via `xcodebuild … build` between milestones; no
automated tests in v1. When it ships, document the shortcut in `README.md`
("snippets") and cross off the entry in `FUTURE_IDEAS.md` (it's not listed
explicitly there — the gap-list response mentioned it as a planned future).
