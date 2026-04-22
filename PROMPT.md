# Clipboard History Manager — macOS Native App

Build a native macOS clipboard history manager (Swift/SwiftUI) similar to the clipboard panels in Alfred and Raycast. This is a personal toy project — favor clarity, modularity, and idiomatic SwiftUI/AppKit over premature optimization.

---

## High-level requirements

- **Native macOS app** — Swift + SwiftUI, AppKit where SwiftUI falls short (panels, global hotkeys, focus management).
- **Background app** — no Dock icon, status bar item only (`LSUIElement = true`).
- **Configurable global hotkey** triggers a floating panel over any other window (including fullscreen apps).
- **Clipboard history** captures text, RTF, images, and file references. Store source app metadata (bundle ID, name, icon) per entry.
- **Latest entries on top**, pinned entries above unpinned.
- **fzf-style fuzzy filtering** as the user types in a search field.
- **Esc dismisses** the panel without changing focus or pasting.
- **Selecting an entry** (Enter or click) writes it to the clipboard, restores focus to the previously frontmost app, and synthesizes ⌘V.
- **⇧⏎** pastes as plain text (strips RTF/HTML formatting).
- **Persistent storage** across launches with a configurable retention policy.

---

## Tech stack

- **Language**: Swift 5.10+
- **UI**: SwiftUI for the panel content and settings; AppKit (`NSPanel`, `NSStatusItem`) for the shell.
- **Min macOS**: 14.0 (Sonoma).
- **Build**: Xcode project (not SwiftPM executable — we need entitlements, Info.plist, and a proper bundle).
- **Dependencies** (SwiftPM):
  - [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey registration + SwiftUI recorder.
  - [`GRDB.swift`](https://github.com/groue/GRDB.swift) — SQLite wrapper for history persistence.
- **No third-party fuzzy lib** — write a small subsequence matcher (described below).

---

## Project layout

```
ClipHistory/
├── ClipHistory.xcodeproj
├── ClipHistory/
│   ├── App/
│   │   ├── ClipHistoryApp.swift          # @main, AppDelegate adapter
│   │   ├── AppDelegate.swift             # status bar, panel lifecycle, permissions
│   │   └── Info.plist                    # LSUIElement=true, usage strings
│   ├── Panel/
│   │   ├── ClipboardPanel.swift          # NSPanel subclass (nonactivating, floating)
│   │   ├── PanelController.swift         # show/hide, focus capture/restore
│   │   └── PanelContentView.swift        # SwiftUI root for the panel
│   ├── Clipboard/
│   │   ├── ClipboardWatcher.swift        # changeCount polling
│   │   ├── ClipboardReader.swift         # extract representations from NSPasteboard
│   │   ├── ClipboardWriter.swift         # write entry back, synthesize ⌘V
│   │   └── SensitiveContentFilter.swift  # nspasteboard.org concealed/transient detection
│   ├── Model/
│   │   ├── ClipEntry.swift               # entry struct + kind enum
│   │   ├── SourceApp.swift               # bundleID, name, icon cache
│   │   └── EntryKind.swift               # .text / .rtf / .image / .fileURLs
│   ├── Storage/
│   │   ├── Database.swift                # GRDB setup, migrations
│   │   ├── EntryRepository.swift         # CRUD + retention policy
│   │   └── BlobStore.swift               # filesystem store for images/large data
│   ├── Search/
│   │   └── FuzzyMatcher.swift            # subsequence + scoring
│   ├── Settings/
│   │   ├── SettingsView.swift            # SwiftUI settings window
│   │   └── Preferences.swift             # @AppStorage / UserDefaults wrapper
│   └── Util/
│       ├── AccessibilityPermission.swift # AX trust check + prompt
│       └── ImageHash.swift               # dedup hashing for images
└── README.md
```

---

## Implementation notes by area

### App shell & status bar

- `@main struct ClipHistoryApp: App` with `@NSApplicationDelegateAdaptor`.
- The `App` body should use `Settings { SettingsView() }` for the settings scene only — no main `WindowGroup`.
- `Info.plist`: `LSUIElement = true`, `NSAppleEventsUsageDescription`, app category `public.app-category.productivity`.
- `AppDelegate.applicationDidFinishLaunching`:
  1. Build `NSStatusItem` with a clipboard SF Symbol.
  2. Initialize `Database`, `EntryRepository`, `BlobStore`.
  3. Start `ClipboardWatcher`.
  4. Register the global hotkey via `KeyboardShortcuts.onKeyDown(for: .togglePanel) { … }`.
  5. Check Accessibility permission; show a one-time onboarding window if not granted.

### The panel

- `ClipboardPanel: NSPanel` with `init` style mask `[.nonactivatingPanel, .titled, .fullSizeContentView]`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `isMovableByWindowBackground = false`.
- `level = .floating` (try `.popUpMenu` if `.floating` doesn't beat fullscreen reliably).
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`.
- `hidesOnDeactivate = false` (we control dismissal manually).
- Center on the screen with the cursor each time it opens (`NSScreen.main`).
- Host `PanelContentView` via `NSHostingView`.

### Showing without stealing focus

This is the part most hobby clipboard managers get wrong:

```swift
func show() {
    previousApp = NSWorkspace.shared.frontmostApplication
    panel.orderFrontRegardless()
    panel.makeKey()         // key, but not active — search field still gets typing
    // DO NOT call NSApp.activate(...)
}
```

Capture `previousApp` *before* `orderFrontRegardless`. Esc and outside-clicks should call `hide()` which just calls `panel.orderOut(nil)`.

### Pasting back

```swift
func paste(_ entry: ClipEntry, asPlainText: Bool) {
    ClipboardWriter.write(entry, asPlainText: asPlainText)
    panel.orderOut(nil)
    previousApp?.activate()
    // Small delay so the target app is actually frontmost before the keystroke
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        Self.synthesizeCmdV()
    }
}

private static func synthesizeCmdV() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let kVK_ANSI_V: CGKeyCode = 0x09
    let down = CGEvent(keyboardEventSource: src, virtualKey: kVK_ANSI_V, keyDown: true)!
    let up   = CGEvent(keyboardEventSource: src, virtualKey: kVK_ANSI_V, keyDown: false)!
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}
```

Optionally snapshot the user's pre-paste clipboard and restore it ~500ms after paste so the history isn't disturbed by its own use. Make this a setting.

### Clipboard watcher

- `Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true)` on the main run loop.
- Compare `NSPasteboard.general.changeCount` to last seen.
- On change: capture `NSWorkspace.shared.frontmostApplication`, then call `ClipboardReader.read()`.
- Reader extraction order: `.fileURL` → `.tiff`/`.png` → `.rtf` → `.string`. Store the richest plus a plain-text projection for search.
- Skip if `SensitiveContentFilter.isConcealed(pasteboard)` — checks for types `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `com.agilebits.onepassword`, `com.googlecode.iterm2.SecureInput`.

### Model

```swift
enum EntryKind {
    case text(String)
    case rtf(Data, plainText: String)
    case image(blobPath: URL, width: Int, height: Int, hash: String)
    case fileURLs([URL])
}

struct ClipEntry: Identifiable {
    let id: Int64
    let kind: EntryKind
    let createdAt: Date
    let source: SourceApp?
    let isPinned: Bool
    var searchText: String { /* derived plain text */ }
}
```

### Storage

- GRDB with one `entries` table and one `pinned_at` column (nil when unpinned, timestamp when pinned).
- Blob files in `~/Library/Application Support/ClipHistory/blobs/<hash>.png`.
- Image dedup: SHA-256 the bytes; if a row with that hash exists, bump its `createdAt` rather than insert a new row.
- Text dedup: same idea on a hash of the trimmed string.
- Retention policy (configurable): max N entries (default 500) OR max age (default 30 days). Pinned entries never expire. Run a sweep on app launch and once an hour.

### Search / fuzzy matcher

A small subsequence matcher with scoring is enough. Pseudocode:

```
score(query, candidate):
  i = j = 0
  score = 0
  prevMatchedIndex = -2
  while i < query.count and j < candidate.count:
    if query[i].lowercased == candidate[j].lowercased:
      score += 1
      if j == prevMatchedIndex + 1: score += 2          # consecutive bonus
      if j == 0 or candidate[j-1] in " /-_.": score += 3  # word boundary bonus
      if candidate[j].isUppercase and candidate[j-1].isLowercase: score += 2  # camelCase
      prevMatchedIndex = j
      i += 1
    j += 1
  return i == query.count ? score : nil
```

Run filtering off the main thread for >2k entries. Empty query = show all, sorted by `(isPinned desc, createdAt desc)`.

### Panel UI (SwiftUI sketch)

- `VStack`:
  - Search `TextField` at top, focused on appear.
  - `List` of entries with arrow-key navigation. Each row: icon (source app), preview (truncated text or thumbnail for images), source app name, relative timestamp.
  - Right pane (split view): full preview of the selected entry. For images, show full-size; for text, monospaced.
- Keyboard handling via `.onKeyPress` (macOS 14+):
  - `↑/↓` move selection
  - `⏎` paste rich
  - `⇧⏎` paste plain
  - `⌘P` toggle pin
  - `⌘⌫` delete entry
  - `Esc` dismiss
- The search `TextField` should let arrow keys propagate to the list.

### Settings

- General tab: launch at login (use `SMAppService.mainApp`), retention count, retention age, restore-clipboard-after-paste toggle.
- Hotkey tab: `KeyboardShortcuts.Recorder("Toggle clipboard panel:", name: .togglePanel)`.
- Privacy tab: button "Clear all history", button "Clear unpinned".

### Permissions

- Accessibility: required for `CGEvent.post` to synthesize ⌘V. On first launch, call `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` and show a friendly window explaining why with a "Open System Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
- Sandboxing: **disable App Sandbox** — clipboard monitoring + global event posting + arbitrary file URL access don't play well with the sandbox for a personal tool. Note this in the README.

---

## Suggested build order

1. Xcode project, `LSUIElement`, status bar item, empty `Settings` scene. Verify no Dock icon.
2. `ClipboardPanel` + `PanelController`. Toggle it from a status bar menu item first (no hotkey yet). Confirm focus is preserved and it appears over fullscreen apps.
3. `KeyboardShortcuts` integration; bind to ⌘⇧V by default.
4. `ClipboardWatcher` + `ClipboardReader` writing to an in-memory array. Render a stub list in the panel.
5. GRDB + `EntryRepository` + `BlobStore`. Migrate the in-memory list to persistent.
6. `ClipboardWriter` + `synthesizeCmdV` + Accessibility permission flow.
7. Fuzzy matcher + search field + arrow-key nav.
8. Settings UI, retention sweep, pin/delete, plain-text paste.
9. Polish: source app icon caching, image thumbnails, sensitive-content filter, "restore previous clipboard" option.

Each step should leave the app in a runnable, testable state. Don't move on until the previous step works end-to-end.

---

## Out of scope (for v1)

- iCloud sync.
- Snippet expansion / templates.
- OCR on copied images.
- Per-app paste rules.
- Touch Bar or menu bar dropdown UI.

Keep these in mind for the data model so they're not painful to add later, but don't build them.

---

## Deliverables

- A working Xcode project that builds and runs on macOS 14+.
- README with build instructions, permissions setup, and a screenshot.
- All source files commented at the type level explaining the role of the component.
- No TODOs in the code for v1 features listed above; either implement or explicitly defer with a `// v2:` comment.
