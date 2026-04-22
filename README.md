# ClipHistory

A native macOS clipboard history manager — a personal toy project inspired by the
clipboard panels in Alfred and Raycast. Swift + SwiftUI with AppKit where SwiftUI
falls short (nonactivating panels, global hotkeys, focus capture).

## Features

- Background app (no Dock icon, status-bar only).
- Configurable global hotkey (default ⌘⇧V) summons a floating panel over any app,
  including fullscreen apps.
- Captures text, RTF, images, and file references; remembers which app produced
  each entry.
- fzf-style fuzzy search with word-boundary, consecutive-match, and camelCase bonuses.
- ⏎ pastes with original formatting; ⇧⏎ pastes as plain text; ⌘P pins;
  ⌘⌫ deletes; Esc dismisses.
- ⌘T opens a **transform picker** over the selected text entry — pretty/minify
  JSON, Base64 / URL en-decode, case conversions (UPPER / lower / Title /
  camel / snake / kebab), strip ANSI / HTML, extract URLs / emails. Fuzzy-
  search transforms by name, ⏎ applies and pastes.
- SQLite-backed persistence (GRDB), with image blobs on disk addressed by SHA-256.
- Configurable retention (max count, max age) with automatic hourly sweeps.
- Respects the `nspasteboard.org` concealed/transient convention — password
  managers marking their entries this way are ignored.
- Optional "restore previous clipboard after paste" so history isn't disturbed by
  its own use.

## Build

Requirements:

- macOS 14 (Sonoma) or newer
- Xcode 15 or newer
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- An Apple Developer Team ID (free tier is fine for local use) — without this
  you get an ad-hoc signature that macOS treats as a new app on every rebuild,
  which makes TCC (Accessibility, etc.) drift out of sync.

```bash
cd ClipHistory
# Put your Team ID into the signing config (first time only).
$EDITOR Config/Signing.xcconfig                 # fill DEVELOPMENT_TEAM = ABCD123456
xcodegen generate
open ClipHistory.xcodeproj
```

Your Team ID is the 10-character string shown at Xcode → Settings → Accounts,
or at developer.apple.com/account → Membership.

`Config/Signing.xcconfig` is gitignored — it's your local override of
`Signing.xcconfig.example`. Once filled in it persists across `xcodegen`
regenerations.

Hit ⌘R in Xcode. Swift Package Manager will resolve the two dependencies
(`KeyboardShortcuts`, `GRDB.swift`) on the first build.

Building from the command line:

```bash
cd ClipHistory
xcodegen generate
xcodebuild -project ClipHistory.xcodeproj -scheme ClipHistory \
           -configuration Debug -destination 'platform=macOS' build
```

### Migrating from an ad-hoc-signed dev build

If you'd been running an ad-hoc-signed build before setting up a real team ID,
macOS's TCC database still has the old binary hash on file. After your first
properly-signed build:

1. Open System Settings → Privacy & Security → Accessibility.
2. Remove any existing ClipHistory entry (minus button).
3. Run the new build and trigger a paste; macOS will re-add it.
4. Toggle it on.

You only need to do this once — subsequent signed rebuilds reuse the same
identity and TCC remembers the grant.

## Permissions

- **Accessibility** — required so the app can post a synthetic ⌘V into the
  previously focused app after you pick an entry. On first launch the system
  will prompt; if you dismiss it, grant access in
  System Settings → Privacy & Security → Accessibility.

The app is **not** sandboxed. A clipboard manager needs to observe the pasteboard,
post HID events globally, and access arbitrary file URLs in paste entries —
none of which play nicely with the App Sandbox for a personal tool.

## Data location

- Database: `~/Library/Application Support/ClipHistory/history.sqlite`
- Image blobs: `~/Library/Application Support/ClipHistory/blobs/<sha256>.png`

Delete both to fully reset the app.

## Layout

```
ClipHistory/
├── project.yml                         # xcodegen spec
├── ClipHistory.xcodeproj               # generated
└── ClipHistory/
    ├── App/                            # @main, AppDelegate, status bar
    ├── Panel/                          # NSPanel shell + SwiftUI content
    ├── Clipboard/                      # watcher / reader / writer / filter
    ├── Model/                          # ClipEntry, EntryKind, SourceApp
    ├── Storage/                        # GRDB database + repository + blob store
    ├── Search/                         # FuzzyMatcher
    ├── Settings/                       # SwiftUI settings window + Preferences
    ├── Util/                           # AX permission, SHA-256, hotkey names
    ├── Info.plist                      # generated (LSUIElement=true)
    └── ClipHistory.entitlements        # generated (sandbox off)
```

## Not in v1

iCloud sync, snippet expansion, OCR, per-app paste rules. The data model has
room to grow in these directions; no need to build them yet.
