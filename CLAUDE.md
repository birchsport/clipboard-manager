# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

The Xcode project is **generated** from `Birchboard/project.yml` via xcodegen — do not hand-edit `Birchboard.xcodeproj`; it's gitignored. After editing sources or `project.yml`:

```sh
cd Birchboard
xcodegen generate
xcodebuild -project Birchboard.xcodeproj -scheme Birchboard \
           -configuration Debug -destination 'platform=macOS' \
           -derivedDataPath build build
```

The built app lands at `build/Build/Products/Debug/Birchboard.app`. Launching it directly from the command line works for a smoke test.

Signing is driven by `Birchboard/Config/Signing.xcconfig` (gitignored, contains the Developer Team ID). The committed `.example` is a template. **Debug** uses Apple Development (auto); **Release** overrides to manual signing + `CODE_SIGN_IDENTITY = "Developer ID Application"` — automatic + a specific identity is rejected by Xcode ("conflicting provisioning settings"), hence the `configs.Release` override in `project.yml`.

Release DMG with optional notarization:

```sh
cd Birchboard
NOTARY_PROFILE=notarytool-birchboard ./scripts/make-dmg.sh   # signed + notarized + stapled
./scripts/make-dmg.sh                                         # signed only (local use)
```

See the "Distributing to other Macs" section in `README.md` for the one-time `notarytool` setup.

## Tests

No automated tests. Verification is manual: rebuild, launch the app, hit the relevant keyboard shortcut, confirm behaviour. SourceKit warnings seen while editing single files ("cannot find type X in scope") are expected — cross-file references resolve only when the whole project compiles. Trust `xcodebuild`, not the live diagnostics, as the source of truth.

## Architecture

Background agent (`LSUIElement=true`) with a status-bar `MenuBarExtra` and a nonactivating floating `NSPanel`. The whole shell is in `App/`:

- `BirchboardApp.swift` — `@main`. A `MenuBarExtra` menu and the `Settings` scene. Opens Settings via `SettingsLink` wrapped with a `simultaneousGesture` calling `NSApp.activate(ignoringOtherApps: true)` — required: macOS 14+ blocks the manual `showSettingsWindow:` route from MenuBarExtra, and LSUIElement apps don't auto-activate so the window opens behind other apps without the explicit activate.
- `AppDelegate.swift` — owns the long-lived singletons via `Services`, starts the watcher, registers the global hotkey, runs the retention sweep on launch + hourly. **Does not** prompt for Accessibility on launch; that API returns false flakily for ad-hoc-signed builds.

### Panel as a state machine

`PanelController` (in `Panel/`) owns the `NSPanel` subclass (`ClipboardPanel`) and the SwiftUI `PanelContentView` hosted inside it. The content is driven by `PanelViewModel` (the largest file, ~700 LOC) which is a five-mode state machine:

```swift
enum PanelMode {
    case browse                           // history list
    case transformPicker(source, savedQuery)
    case snippetPicker(savedQuery)
    case actionPicker(source, savedQuery)
    case nicknameEditor(entry, savedQuery) // editing an obfuscated entry's label
}
```

Each non-browse mode has its own parallel `@Published` state (`transformQuery / Matches / SelectedIndex`, `snippetQuery / Matches / SelectedIndex`, `actionQuery / Matches / SelectedIndex`, `nicknameDraft`). The search field in `PanelContentView` binds to the correct query/draft depending on `mode`; the left column swaps between `EntryListView`, `TransformPickerView`, `SnippetPickerView`, `ActionPickerView` (the nickname editor reuses the search field — no dedicated left view). Keyboard routing is: `handle(event:)` switches on mode to `handleBrowse` / `handleTransform` / `handleSnippet` / `handleAction` / `handleNicknameEditor`; each handler returns `true` to consume the event or `false` to let it flow to the focused `TextField`. `handleNicknameEditor` swallows all ⌘-modified shortcuts so quick-paste / pin / delete / Quick Look don't fire mid-rename.

**Critical**: hotkeys inside the panel come from an `NSEvent.addLocalMonitorForEvents` installed in `PanelController.installEventMonitor()`, not SwiftUI `.onKeyPress`. Removed when the panel closes.

**Multi-paste is a sub-state of `.browse`, not a new mode.** `PanelViewModel.batchedIDs: Set<Int64>` (membership) and `batchedOrder: [Int64]` (paste order) survive query changes and refilters because they're keyed by entry id, not list index. `handleBrowse` adds three branches (⇧Space toggle, ⇧↑/⇧↓ extend) before the existing switch and ⏎ branches on `!batchedIDs.isEmpty` to call `actions.pasteBatch` instead of `actions.paste`. `pasteBatch` synthesises one `ClipEntry(.text(joined))` and reuses the existing single-entry `paste(_:asPlainText:)` choreography — `ClipboardWriter.write` is unchanged. Image entries (empty `plainText` → silent gaps) and obfuscated entries (concatenation would leak the value) beep on `toggleBatch` and are silently skipped by `extendBatch`. The batch is cleared in `focusSearchField()` so it resets every panel open. The delimiter lives on `Preferences.multiSelectDelimiter` (default `\n`); `PanelController.parseDelimiter` expands `\n` / `\t` / `\\` at paste time.

### Focus handling

The panel is `.nonactivatingPanel` so its parent app never becomes frontmost — this is how we keep `previousApp` valid for the paste flow. `makeKey()` is called (for typing into the search field) but `NSApp.activate(...)` is deliberately never called. A published `focusRequestTick` counter on the view model is bumped whenever a field should re-focus; `PanelContentView.onChange(of: focusRequestTick)` re-applies `@FocusState` via a `DispatchQueue.main.async` (same runloop writes get dropped).

### Paste flow

`PanelController.paste(entry, asPlainText:)` order matters:
1. Optionally snapshot the pasteboard (for restore-after-paste).
2. Write the entry via `ClipboardWriter.write` (marks the change count as self-produced so the watcher ignores it).
3. Activate `previousApp` **before** hiding the panel (so WindowServer has a stable frontmost).
4. Hide the panel.
5. 120ms later, `CGEvent.post` a `⌘V` at the `cgAnnotatedSessionEventTap` (not `cghidEventTap` — Electron/Qt apps sometimes reject HID-tap events).
6. 700ms later, if snapshotting, restore.

`ClipboardWatcher` tracks self-produced change counts in a small LRU set so pasting doesn't re-ingest.

### Transforms / Snippets / Actions

Three parallel registries, each roughly the same shape:

- **`Transforms/`** — a `TextTransform` protocol (`id`, `displayName`, `isApplicable`, `apply`) and a hard-coded `TransformRegistry.all`. Built-ins in `BuiltInTransforms.swift` (JSON / YAML / JWT / timestamp / hashes / number-bases / query-string / Base64 / URL / case / trim / strip / extract). Transforms always produce text that flows through the normal paste path. The three trim variants (`whitespace.trim`, `whitespace.rtrim_lines`, `whitespace.trim_lines`) share a private `LineTrim` helper enum in `BuiltInTransforms.swift` and all `isApplicable` only when applying would change the payload.
- **`Snippets/`** — user-authored, persisted. `SnippetStore` is `@MainActor`-isolated, `@Published` snippets array serialized to `UserDefaults` as JSON under key `snippets.v1`. Placeholders (`{clipboard}`, `{date[:FMT]}`, `{uuid}`, etc.) expand via `SnippetPlaceholders.expand` on apply.
- **`Actions/`** — an `EntryAction` protocol that takes an `ActionContext` exposing `paste(String)` and `dismiss()`. Actions may be pure side-effects (`Open in Browser` → `NSWorkspace.open`, no paste) or paste-producing (`Paste as rgb()`). Applicability is "pure match" — the entire trimmed payload must match the classifier (URL, email, hex color, phone).

Adding a new transform, action, or snippet placeholder is a one-file change — add a struct conforming to the protocol and insert into the registry.

### Language detection + syntax highlighting

**`Detection/`** holds a pair of orthogonal helpers used by the panel:

- **`LanguageDetector`** — heuristic regex-based sniffer returning a `DetectedLanguage?` (JSON / YAML / XML / HTML / Swift / Java / JS / TS / Python / Go / Rust / Ruby / SQL / Shell / Dockerfile / Markdown / CSS). Runs on demand from views (no DB migration, no persisted field); a small thread-safe LRU cache keyed by entry id keeps re-lexing cheap during scroll. Detection order matters — shared-keyword languages (Java / Python / JS) are ordered by specificity so Java's high-confidence signals (`public class`, `System.out.println`, `package com.foo;`) beat Python's, which now rejects bare `class Foo` / `import X` and requires either a Python-specific high-confidence signal or ≥2 medium ones.
- **`CodeHighlighter`** — takes `(text, language)` → `AttributedString`. Swift goes through **Splash** (`SyntaxHighlighter<AttributedStringOutputFormat>`); every other language uses a generic regex-rule runner (`Rule` with a pattern and a `SwiftUI.Color`), applied in order. Splash's `Color` and `SyntaxHighlighter` types collide with SwiftUI and with one of our own types — hence `CodeHighlighter.Palette` uses fully-qualified `SwiftUI.Color(...)` and the wrapper is `CodeHighlighter` not `SyntaxHighlighter`. `CodeHighlighter.styledText(_:entryID:)` is the one-call helper for rendering a preview-ready `Text`. `CodeHighlighter.Palette` is also reused by the tree view (below).
- **`StructuredTree`** — `TreeNode` value type + `StructuredTreeBuilder.fromJSON(_:)` / `fromYAML(_:)` / `fromXML(_:)`. Returns `nil` on parse failure so callers can fall back to flat text. JSON goes through `JSONSerialization`; YAML through Yams; XML through `Foundation.XMLDocument` (macOS-only). `Panel/TreeView.swift` renders the tree via recursive `NodeView` with per-branch `@State` expansion; used by `QuickLookView` for JSON / YAML / XML payloads, which the `LanguageDetector` identifies. Labels use sigils — `[n]` for array indices, `<tag>` for XML elements, `@attr` for XML attributes, `#text` for XML text nodes, bare strings for JSON/YAML keys — and `TreeView.labelText` renders each style distinctly.

Adding a language = extend the `DetectedLanguage` enum + add a `looksLike…` case + add a rule set. Two matching additions, ~20 LOC.

### Auto-updates (Sparkle)

**`Updater/UpdaterController.swift`** wraps `SPUStandardUpdaterController` and lives on `Services`. Feed URL (`SUFeedURL`), public EdDSA key (`SUPublicEDKey`), 24-hour interval, and auto-check default are in `project.yml`'s Info.plist properties. The Settings General tab exposes a toggle, a Check Now button, and a version/last-check footer; the menu-bar menu has a "Check for Updates…" item.

Releases are built and signed by `.github/workflows/release.yml` on any `v*.*.*` tag push: it sets up a temporary keychain from the Developer ID `.p12`, runs `scripts/make-dmg.sh`, signs the DMG with Sparkle's `sign_update`, generates/appends an `<item>` to `docs/appcast.xml` (committed back to main), and publishes a GitHub Release. Seven repo secrets are required: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`.

Two gotchas wired into the workflow that are easy to break if you rewrite it:

- `make-dmg.sh` re-signs Sparkle's nested XPC services (`Downloader.xpc`, `Installer.xpc`), `Autoupdate`, and `Updater.app` with our Developer ID + `--timestamp` + hardened runtime before staging the DMG. `xcodebuild archive` only signs the outer framework wrapper; the pre-signed inner bundles fail notarization otherwise.
- The appcast's `<sparkle:version>` must be the integer `CURRENT_PROJECT_VERSION`, **not** the marketing string. Sparkle's default comparator matches it against the installed `CFBundleVersion`; feeding `"0.2.1"` against an installed `CFBundleVersion=2` makes Sparkle parse component-by-component (`2 > 0`) and conclude the installed build is already newer. The workflow derives `BUILD` by `awk`-ing `CURRENT_PROJECT_VERSION` out of `project.yml` so this stays honest.

Per-release steps + troubleshooting notes live in `RELEASE_PROCESS.md` at the repo root.

### Storage

`Storage/` uses GRDB:
- `Database` — single table `entries` with flattened columns per `EntryKind` case. Migrations: `v1_entries` creates the table; `v2_obfuscation` adds nullable `obfuscated_at` (timestamp) and `obfuscation_nickname` (text) columns. Both are additive; old DBs migrate forward without data loss.
- `EntryRepository` — the **only** read/write gateway. Marked `@unchecked Sendable` because GRDB's `DatabasePool` is thread-safe and we need to call it from `Task.detached` for export/import. Publishes a `PassthroughSubject<Void, Never>` named `changes` that the view model subscribes to. `togglePin` / `toggleObfuscation` / `setObfuscationNickname` are sibling mutators; toggling obfuscation off clears the nickname so re-obfuscating later starts fresh. Retention sweeps and `clearUnpinned` skip rows with `pinned_at IS NOT NULL OR obfuscated_at IS NOT NULL` — obfuscated entries are user-curated, like pins.
- `BlobStore` — content-addressed image blobs at `~/Library/Application Support/Birchboard/blobs/<sha256>.png`. Pruned during retention sweeps.
- `HistoryArchive` — Codable JSON export/import, images inlined as base64. Dedup on import is by `dedup_hash`. Round-trips `obfuscatedAt` and `obfuscationNickname` so backups preserve the hidden state. The synthesized Codable for these `T?` fields is missing-key tolerant, so older v1 archives still import (their obfuscation fields land as nil).

`EntryKind` is an enum with four cases (`text / rtf / image / fileURLs`). Its `tag: Int`, `plainText: String`, `dedupHash: String`, and `withReplacedText(_:) -> EntryKind` together are the "protocol surface" every other module treats as the clipboard payload abstraction.

`ClipEntry.searchText` is a separate computed property from `plainText`. For non-obfuscated text/RTF entries it returns the payload verbatim; for images it appends `"image WxH W×H"` tokens so typing "image" or the dimensions matches; for file URLs it prepends `"file"` / `"files"` plus the basenames. **For obfuscated entries it short-circuits to `obfuscationNickname ?? ""`** so the underlying payload never enters the fuzzy index — typing the password doesn't surface the row. This is what the fuzzy matcher operates on — **do not replace `plainText` calls with `searchText` for anything that needs the literal payload** (hashing, previewing, the transform/action pickers, `ClipboardWriter.write`).

### Obfuscation

Per-entry "screen-share safety" flag. Pin's exact shape: a nullable timestamp + an optional text label. State lives only in the database; nothing on `Preferences`. The paste path (`ClipboardWriter.write`, `PanelController.paste`) reads `entry.kind` directly and is **untouched** — obfuscated entries paste their real value. All hiding is at the rendering layer:

- `Panel/PanelContentView.swift`: `EntryRow.previewText` returns `"\(nickname)  ••••••••"` (or just dots) when `entry.isObfuscated`; `detectedLanguage` short-circuits to nil so the language chip can't leak; `EntryPreviewView` early-returns to `obfuscatedView` (centered nickname + dots, no `.text` / `.rtf` payload access).
- `Panel/QuickLookView.swift`: same early-return; `sizeString` is suppressed (even char-count would leak); `LanguageDetector.detect` and `CodeHighlighter.styledText` are never reached.
- `Panel/PanelViewModel.swift`: ⌘O toggles obfuscation; on toggle-on it enters `.nicknameEditor` mode pre-populated with `""` so the user can name the entry while it's fresh. ⌘R re-edits the nickname on an already-obfuscated entry. ⌘T / ⌘S / ⌘K / ⌘Y all `NSSound.beep()` and short-circuit when `selectedEntry?.isObfuscated == true`.
- Image / file-URL entries are not obfuscatable (passwords are text); `toggleObfuscationForSelected()` beeps for them.

### Clipboard ingestion

`ClipboardWatcher.tick` runs every 0.4s on the main run loop. Skips:
1. Change counts it produced itself (self-produced LRU).
2. Sensitive pasteboards — `SensitiveContentFilter` checks for the `nspasteboard.org` concealed/transient types and some well-known password-manager markers.
3. Captures whose frontmost app's `bundleIdentifier` is in `preferences.ignoredAppBundleIDs` (user-editable set cached as a `Set` for O(1) lookup; a Combine subscription keeps it in sync).

`ClipboardReader.read` extracts richest-first: file URLs → images (TIFF/PNG normalized to PNG + blob-stored) → RTF (with plain-text projection) → plain text.

### Predictive Paste (easter egg)

`EasterEgg/PredictivePaste.swift` is a tiny opt-in feature: a second global hotkey (default `⌃⌥⌘P`, registered as `KeyboardShortcuts.Name.predictivePaste`) pastes a random hardcoded quote into the frontmost app, no panel involved. The handler in `AppDelegate` is gated on `Preferences.predictivePasteEnabled` (off by default) so the registered shortcut is a no-op until the user opts in via Settings → General → Easter Eggs. The flow captures `NSWorkspace.shared.frontmostApplication` synchronously, writes the quote directly to `NSPasteboard.general`, calls `ClipboardWatcher.markSelfProduced` so the watcher does not ingest the quote into history, then reuses `ClipboardWriter.synthesizeCmdV` (and optionally `snapshot` / `restore`) for the rest of the paste choreography. Adding a new quote = appending to the `PredictivePasteQuotes.all` array — no other change required.

### Services container

`Services` on `AppDelegate` is `@MainActor` and owns `preferences`, `snippetStore`, `database`, `repository`, `blobStore`. `database / repository / blobStore` are implicitly-unwrapped until `bootstrap()` runs from `applicationDidFinishLaunching`. Wired into the SwiftUI environment at the Settings scene construction:

```swift
Settings {
    SettingsView()
        .environmentObject(appDelegate.services)
        .environmentObject(appDelegate.services.preferences)
        .environmentObject(appDelegate.services.snippetStore)
}
```

Preferences and SnippetStore are injected separately (not just via Services) because their `@Published` properties don't propagate through a containing `ObservableObject`; SwiftUI only observes the object it's directly bound to.

## Conventions

- **Do not commit** `.xcodeproj`, generated `Info.plist`, generated `.entitlements`, `Config/Signing.xcconfig`, or `build/`. All gitignored.
- **Bundle ID** is `dev.birch.Birchboard`. Changing it invalidates TCC permissions and will re-prompt for Accessibility.
- **UserDefaults keys** versioned when the shape may change (`snippets.v1`). Archive format similarly (`HistoryArchive.currentVersion`).
- **LOG prefix** `"Birchboard: "` for all `NSLog` calls so the app's lines stand out in Console.
- User-facing settings live on `Preferences` (a single `ObservableObject`); `@Published` setters write through to `UserDefaults` in `didSet`.

## Signing / distribution notes

- `Apple Development` identity is what Debug uses; it's fine for running locally but macOS treats each ad-hoc rebuild as a different app and resets TCC.
- A stable `DEVELOPMENT_TEAM` in `Config/Signing.xcconfig` (plus a real Apple Developer membership) makes TCC remember grants across rebuilds.
- For DMGs shared with other Macs, the Release config is already set up for Developer ID Application. Notarization requires a `notarytool` keychain profile; `make-dmg.sh` is the one-button path once that's set up. Gatekeeper rejects ad-hoc-signed DMGs on other Macs.
