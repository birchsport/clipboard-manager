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

See `RELEASE.md` for the one-time `notarytool` setup.

## Tests

No automated tests. Verification is manual: rebuild, launch the app, hit the relevant keyboard shortcut, confirm behaviour. SourceKit warnings seen while editing single files ("cannot find type X in scope") are expected — cross-file references resolve only when the whole project compiles. Trust `xcodebuild`, not the live diagnostics, as the source of truth.

## Architecture

Background agent (`LSUIElement=true`) with a status-bar `MenuBarExtra` and a nonactivating floating `NSPanel`. The whole shell is in `App/`:

- `BirchboardApp.swift` — `@main`. A `MenuBarExtra` menu and the `Settings` scene. Opens Settings via `SettingsLink` wrapped with a `simultaneousGesture` calling `NSApp.activate(ignoringOtherApps: true)` — required: macOS 14+ blocks the manual `showSettingsWindow:` route from MenuBarExtra, and LSUIElement apps don't auto-activate so the window opens behind other apps without the explicit activate.
- `AppDelegate.swift` — owns the long-lived singletons via `Services`, starts the watcher, registers the global hotkey, runs the retention sweep on launch + hourly. **Does not** prompt for Accessibility on launch; that API returns false flakily for ad-hoc-signed builds.

### Panel as a state machine

`PanelController` (in `Panel/`) owns the `NSPanel` subclass (`ClipboardPanel`) and the SwiftUI `PanelContentView` hosted inside it. The content is driven by `PanelViewModel` (the largest file, ~600 LOC) which is a four-mode state machine:

```swift
enum PanelMode {
    case browse                           // history list
    case transformPicker(source, savedQuery)
    case snippetPicker(savedQuery)
    case actionPicker(source, savedQuery)
}
```

Each non-browse mode has its own parallel `@Published` state (`transformQuery / Matches / SelectedIndex`, `snippetQuery / Matches / SelectedIndex`, `actionQuery / Matches / SelectedIndex`). The search field in `PanelContentView` binds to the correct query depending on `mode`; the left column swaps between `EntryListView`, `TransformPickerView`, `SnippetPickerView`, `ActionPickerView`. Keyboard routing is: `handle(event:)` switches on mode to `handleBrowse` / `handleTransform` / `handleSnippet` / `handleAction`; each handler returns `true` to consume the event or `false` to let it flow to the focused `TextField`.

**Critical**: hotkeys inside the panel come from an `NSEvent.addLocalMonitorForEvents` installed in `PanelController.installEventMonitor()`, not SwiftUI `.onKeyPress`. Removed when the panel closes.

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

- **`Transforms/`** — a `TextTransform` protocol (`id`, `displayName`, `isApplicable`, `apply`) and a hard-coded `TransformRegistry.all`. 16 built-ins in `BuiltInTransforms.swift`. Transforms always produce text that flows through the normal paste path.
- **`Snippets/`** — user-authored, persisted. `SnippetStore` is `@MainActor`-isolated, `@Published` snippets array serialized to `UserDefaults` as JSON under key `snippets.v1`. Placeholders (`{clipboard}`, `{date[:FMT]}`, `{uuid}`, etc.) expand via `SnippetPlaceholders.expand` on apply.
- **`Actions/`** — an `EntryAction` protocol that takes an `ActionContext` exposing `paste(String)` and `dismiss()`. Actions may be pure side-effects (`Open in Browser` → `NSWorkspace.open`, no paste) or paste-producing (`Paste as rgb()`). Applicability is "pure match" — the entire trimmed payload must match the classifier (URL, email, hex color, phone).

Adding a new transform, action, or snippet placeholder is a one-file change — add a struct conforming to the protocol and insert into the registry.

### Storage

`Storage/` uses GRDB:
- `Database` — single table `entries` with flattened columns per `EntryKind` case, migration `v1_entries`.
- `EntryRepository` — the **only** read/write gateway. Marked `@unchecked Sendable` because GRDB's `DatabasePool` is thread-safe and we need to call it from `Task.detached` for export/import. Publishes a `PassthroughSubject<Void, Never>` named `changes` that the view model subscribes to.
- `BlobStore` — content-addressed image blobs at `~/Library/Application Support/Birchboard/blobs/<sha256>.png`. Pruned during retention sweeps.
- `HistoryArchive` — Codable JSON export/import, images inlined as base64. Dedup on import is by `dedup_hash`.

`EntryKind` is an enum with four cases (`text / rtf / image / fileURLs`). Its `tag: Int`, `plainText: String`, `dedupHash: String`, and `withReplacedText(_:) -> EntryKind` together are the "protocol surface" every other module treats as the clipboard payload abstraction.

### Clipboard ingestion

`ClipboardWatcher.tick` runs every 0.4s on the main run loop. Skips:
1. Change counts it produced itself (self-produced LRU).
2. Sensitive pasteboards — `SensitiveContentFilter` checks for the `nspasteboard.org` concealed/transient types and some well-known password-manager markers.
3. Captures whose frontmost app's `bundleIdentifier` is in `preferences.ignoredAppBundleIDs` (user-editable set cached as a `Set` for O(1) lookup; a Combine subscription keeps it in sync).

`ClipboardReader.read` extracts richest-first: file URLs → images (TIFF/PNG normalized to PNG + blob-stored) → RTF (with plain-text projection) → plain text.

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
