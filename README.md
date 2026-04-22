# Birchboard

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
- ⌘1–⌘9 quick-pastes the Nth visible entry without arrow-keying. ⇧ combined
  with the digit pastes as plain text.
- ⌘Y toggles a full-panel **Quick Look** preview of the selected entry
  (full-size images, larger monospaced text, file paths with icons, or —
  for JSON / YAML — a collapsible tree view with typed colouring). Arrow
  keys still navigate while the overlay is open.
- **Code-aware panel**: each text entry is sniffed for its language (JSON,
  YAML, XML, HTML, Swift, Java, JS/TS, Python, Go, Rust, Ruby, SQL, Shell,
  Dockerfile, Markdown, CSS). Detected rows show a small language chip and
  the preview + Quick Look panes render with syntax highlighting.
- Type-keyword search: typing `image` finds image entries, `file` finds
  file-reference entries, and image dimensions (`400x300` / `400×300`) match
  too — images and files aren't just "no text, unsearchable."
- ⌘T opens a **transform picker** over the selected text entry — pretty/minify
  JSON, JSON ↔ YAML, decode JWT, Unix timestamp ↔ ISO 8601, SHA-256 / SHA-1 /
  MD5, number-base conversions (dec / hex / bin), query string ↔ JSON,
  Base64 / URL en-decode, case conversions (UPPER / lower / Title / camel /
  snake / kebab), trim whitespace (whole-string, per-line trailing, or
  per-line both ends), strip ANSI / HTML, extract URLs / emails. Fuzzy-search
  transforms by name, ⏎ applies and pastes.
- ⌘S opens a **snippet picker** of user-authored canned text, managed in
  Settings → Snippets. Supports placeholders: `{clipboard}`, `{date[:FMT]}`,
  `{time[:FMT]}`, `{uuid}`, `{newline}`, `{tab}`, plus `{{` / `}}` for
  literal braces. ⏎ expands placeholders and pastes.
- ⌘K opens a **type-aware action picker** for the selected entry. Available
  actions depend on the entry type: URL → Open in Browser / Paste as Markdown
  link; files → Reveal in Finder / Open; email → Compose Mail; phone → Call
  with FaceTime; hex color → Paste as rgb() / hsl(). Inapplicable actions
  are hidden; ⏎ runs, Esc cancels.
- SQLite-backed persistence (GRDB), with image blobs on disk addressed by SHA-256.
- Configurable retention (max count, max age) with automatic hourly sweeps.
- Respects the `nspasteboard.org` concealed/transient convention — password
  managers marking their entries this way are ignored.
- **Ignored-apps list** (Settings → Privacy): capture is skipped entirely
  while the frontmost app matches. Ships with sensible defaults
  (1Password 7/8, Bitwarden, Keychain Access, Apple Passwords, LastPass,
  KeePassXC); user-editable via a file picker that reads the bundle ID
  straight from the chosen `.app`.
- **Export / Import history** (Settings → Privacy → Backup): dump every entry
  (including image bytes) into a single JSON file; import the same shape
  back. Dedup by content hash means re-importing is a no-op.
- Optional "restore previous clipboard after paste" so history isn't disturbed by
  its own use.
- **Adjustable panel opacity** (slider, 30–100%) and **launch at login** in
  Settings → General.

## Build

Requirements:

- macOS 14 (Sonoma) or newer
- Xcode 15 or newer
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- An Apple Developer Team ID (free tier is fine for local use) — without this
  you get an ad-hoc signature that macOS treats as a new app on every rebuild,
  which makes TCC (Accessibility, etc.) drift out of sync.

```bash
cd Birchboard
# Put your Team ID into the signing config (first time only).
$EDITOR Config/Signing.xcconfig                 # fill DEVELOPMENT_TEAM = ABCD123456
xcodegen generate
open Birchboard.xcodeproj
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
cd Birchboard
xcodegen generate
xcodebuild -project Birchboard.xcodeproj -scheme Birchboard \
           -configuration Debug -destination 'platform=macOS' build
```

### Migrating from an ad-hoc-signed dev build

If you'd been running an ad-hoc-signed build before setting up a real team ID,
macOS's TCC database still has the old binary hash on file. After your first
properly-signed build:

1. Open System Settings → Privacy & Security → Accessibility.
2. Remove any existing Birchboard entry (minus button).
3. Run the new build and trigger a paste; macOS will re-add it.
4. Toggle it on.

You only need to do this once — subsequent signed rebuilds reuse the same
identity and TCC remembers the grant.

## Distributing to other Macs

To send a DMG to another Mac and have it open without Gatekeeper
complaints, the build has to be signed with a **Developer ID
Application** cert and **notarized** by Apple. Apple Development certs
(what the Debug config uses) only work on your own Mac.

### One-time setup

1. **Get a Developer ID Application cert.**
   developer.apple.com/account → Certificates → `+` → *Developer ID
   Application*. Follow the CSR prompts (Keychain Access →
   Certificate Assistant → Request a Certificate…). Double-click the
   downloaded `.cer` to install. Verify with
   `security find-identity -v -p codesigning`; you should see a
   "Developer ID Application: …" line.

2. **Generate an app-specific password** at
   appleid.apple.com → Sign-In and Security → App-Specific Passwords.

3. **Store notarytool credentials** in the keychain:

   ```sh
   xcrun notarytool store-credentials "notarytool-birchboard" \
       --apple-id "you@example.com" \
       --team-id  "YOUR_TEAM_ID" \
       --password "xxxx-xxxx-xxxx-xxxx"
   ```

   The profile name is your label; `make-dmg.sh` reads it from
   `$NOTARY_PROFILE`.

### Every release

```sh
cd Birchboard
NOTARY_PROFILE=notarytool-birchboard ./scripts/make-dmg.sh
```

`make-dmg.sh` runs `xcodegen generate`, archives the Release config
(manual Developer ID signing + hardened runtime), packages the `.app`
into a DMG, codesigns the DMG, submits to Apple's notary service with
`--wait`, staples the returned ticket, and runs `spctl --assess` to
verify Gatekeeper accepts it. The DMG lands at
`Birchboard/build/Birchboard.dmg` (around 3 MB).

If notarization fails, fetch the log with the submission ID from
the output:

```sh
xcrun notarytool log <submission-id> \
    --keychain-profile "notarytool-birchboard"
```

Most common causes: signing with Apple Development instead of
Developer ID (check `project.yml` Release override), hardened runtime
not enabled (`ENABLE_HARDENED_RUNTIME` must be `YES`, already set),
or a stale archive (delete `build/` and rerun).

### Bumping a version

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`Birchboard/project.yml`, then run `make-dmg.sh` again. The one-time
setup above is a one-time-ever affair.

## Permissions

- **Accessibility** — required so the app can post a synthetic ⌘V into the
  previously focused app after you pick an entry. On first launch the system
  will prompt; if you dismiss it, grant access in
  System Settings → Privacy & Security → Accessibility.

The app is **not** sandboxed. A clipboard manager needs to observe the pasteboard,
post HID events globally, and access arbitrary file URLs in paste entries —
none of which play nicely with the App Sandbox for a personal tool.

## Data location

- Database: `~/Library/Application Support/Birchboard/history.sqlite`
- Image blobs: `~/Library/Application Support/Birchboard/blobs/<sha256>.png`

Delete both to fully reset the app.

## Layout

```
Birchboard/
├── project.yml                         # xcodegen spec
├── Config/Signing.xcconfig*            # local Team ID override
├── scripts/make-dmg.sh                 # Release build + optional notarization
├── Birchboard.xcodeproj                # generated
└── Birchboard/
    ├── App/                            # @main, AppDelegate, status bar
    ├── Panel/                          # NSPanel shell + SwiftUI content
    ├── Clipboard/                      # watcher / reader / writer / filter
    ├── Model/                          # ClipEntry, EntryKind, SourceApp
    ├── Storage/                        # GRDB database + repository + archive
    ├── Search/                         # FuzzyMatcher
    ├── Transforms/                     # ⌘T: TextTransform + registry + built-ins
    ├── Snippets/                       # ⌘S: Snippet + store + placeholders
    ├── Actions/                        # ⌘K: EntryAction + registry + built-ins
    ├── Settings/                       # SwiftUI settings window + Preferences
    ├── Util/                           # AX permission, SHA-256, hotkey names
    ├── Info.plist                      # generated (LSUIElement=true)
    └── Birchboard.entitlements         # generated (sandbox off)
```

## Planned but not yet built

- **Auto-expanding snippets** — type a trigger (e.g. `;sig`) anywhere and
  have it expand inline, the way TextExpander / Alfred snippets work.
  Requires a global keystroke monitor (AX-trust-bound), deferred.
- **OCR on image entries** — run `VNRecognizeTextRequest` against a
  captured image and drop the text onto the clipboard.
- **iCloud / LAN sync** across your own Macs.
- **Scoped clipboard profiles** — separate histories for "work" and
  "personal", switched manually or by active app.
- **Per-app paste rules** — e.g. always paste plain into Slack.

See [`FUTURE_IDEAS.md`](FUTURE_IDEAS.md) for the full shortlist with
notes on effort and design.
