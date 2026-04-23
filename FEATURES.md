# Birchboard features

Birchboard is a native macOS clipboard history manager. It runs as a
background menu-bar agent and presents a floating panel with keyboard-first
navigation, searchable history, per-entry transforms and actions,
user-authored snippets, and syntax-highlighted previews of any code it
captures.

System requirements: macOS 14 (Sonoma) or newer. Apple Silicon or Intel.

---

## Capture

- Text, RTF, images, and file references.
- Source app metadata: the app icon + name beside each entry.
- **Ignore list** (Settings → Privacy): capture is skipped while specific
  apps are frontmost. Ships with 1Password 7/8, Bitwarden, Keychain Access,
  Apple Passwords, LastPass, and KeePassXC; user-editable via a file picker
  that reads the bundle ID from the chosen `.app`.
- **nspasteboard.org convention**: apps that mark copies as
  `ConcealedType` / `TransientType` are silently ignored regardless of the
  ignore list.
- Retention sweeps run on launch and hourly.

## Browsing

- fzf-style **fuzzy search** as you type (word-boundary, consecutive-match,
  and camelCase bonuses).
- **Type-keyword search**: `image` matches image entries, `file` matches
  file-reference entries, image dimensions (`400x300` / `400×300`) match
  too, and filename fragments match file entries without needing full paths.
- **⌘1 – ⌘9 quick-paste** the Nth visible entry. ⇧⌘N pastes plain text.
  The first nine rows show their shortcut inline so you don't have to
  memorise the positions.
- **Code-aware row chips**: any entry detected as code gets a small
  language tag next to the source-app name. 17 languages detected via
  regex heuristics: JSON, YAML, XML, HTML, Markdown, Swift, Java,
  JavaScript, TypeScript, Python, Go, Rust, Ruby, SQL, Shell, Dockerfile,
  CSS. Detection order resolves shared-keyword conflicts (Java is
  checked before Python so `class Foo { … }` doesn't falsely match).
- **Pin / unpin** entries so they stay on top (⌘P).
- **Delete** with ⌘⌫.

## Previews

- Live preview pane adjacent to the list.
- Code-aware **syntax highlighting** in the preview for any detected
  language. Swift goes through the Splash highlighter; other languages use
  a keyword/string/number/comment rule set.
- **⌘Y Quick Look overlay**: full-panel preview of the selected entry.
  Full-size images, larger monospaced text, file paths with icons. Arrow
  keys still navigate entries while the overlay is open.
- **Structured tree view**: Quick Look on a JSON, YAML, or XML entry
  renders the payload as a collapsible tree — keys, typed values (strings,
  numbers, bools, null), array indices, XML elements (`<tag>`), XML
  attributes (`@attr`), and text nodes (`#text`) all coloured
  consistently with the in-line highlighter. Click any `{ … keys }` /
  `[ … items ]` / `<tag>` row to expand or collapse. Each subtree's
  expansion state is independent. Falls back to the flat highlighted
  preview if the payload doesn't parse.

## ⌘T — Transform picker

Replace the clipboard payload with a transformed version before pasting.
Inapplicable transforms (e.g. "Pretty JSON" over non-JSON) are hidden
upfront; fuzzy-filter by name. 27 built-in transforms across the
categories below.

- **JSON** — Pretty-print, minify.
- **JSON ↔ YAML** — auto-direction.
- **JWT** — decode to pretty-printed header + payload.
- **Timestamp** — Unix time ↔ ISO 8601, auto-direction. Accepts 10-digit
  seconds or 13-digit millisecond inputs.
- **Hashes** — SHA-256, SHA-1, MD5.
- **Number bases** — prints dec / hex / bin simultaneously for a decimal,
  `0x`-prefixed, or `0b`-prefixed integer.
- **Query string ↔ JSON** — `foo=1&bar=hello%20world` ↔ flat `{"foo":"1",…}`.
- **Encoding** — Base64 encode/decode, URL encode/decode (RFC 3986
  unreserved set).
- **Case** — UPPERCASE, lowercase, Title Case, camelCase, snake_case,
  kebab-case.
- **Trim whitespace** — three variants:
  - Whole-string leading + trailing.
  - Per-line trailing only (preserves indentation).
  - Per-line leading + trailing (flattens indentation and cleans trailing
    spaces).
  Each variant only appears when it would actually change the payload.
- **Strip** — ANSI escape codes, HTML tags.
- **Extract** — all URLs, all email addresses.

## ⌘S — Snippet picker

User-authored canned text that can be pasted without copying first.
Managed in Settings → Snippets (list with add / edit / delete / reorder,
multi-line body editor).

Placeholders expand at paste time:

- `{clipboard}` — whatever's currently on the clipboard.
- `{date}` / `{date:yyyy-MM-dd}` / any `DateFormatter` template.
- `{time}` / `{time:HH:mm}`.
- `{uuid}` — fresh UUID each expansion.
- `{newline}` / `{tab}` — literal escape shortcuts.
- `{{` / `}}` — literal braces.

Example body: `Thanks for {clipboard} — logged at {date} {time:HH:mm}.`

Unknown tokens pass through unchanged (no silent deletion on typos).

## ⌘K — Type-aware actions

The picker only shows actions that apply to the selected entry's detected
type ("pure match" — the entire trimmed payload must match, not merely
contain a URL/email/etc.).

- **URL** → Open in Browser, Paste as Markdown link.
- **File(s)** → Reveal in Finder, Open.
- **Email** → Compose Mail to…
- **Phone** → Call with FaceTime.
- **Hex color** (`#RRGGBB` / `#RGB` / `#RRGGBBAA`) → Paste as `rgb()`,
  Paste as `hsl()` (handles alpha).

## Preferences (Settings → General)

- **Retention** — cap history by count and age (defaults: 1000 entries,
  90 days). Pinned entries never expire.
- **Panel opacity** — slider, 30–100%.
- **Restore previous clipboard after paste** — optional; using a history
  entry doesn't disturb your current clipboard.
- **Launch at login** — via `SMAppService`.
- **Custom global hotkey** — standard shortcut recorder (default ⌘⇧V).
- **Automatic updates** via [Sparkle](https://sparkle-project.org). Default
  24-hour background check; **Check Now** button and a toggle live in
  Settings → General → Updates. Also exposed as **Check for Updates…** in
  the menu-bar menu. Updates are EdDSA-signed and served from a GitHub
  Pages appcast.

## Privacy & storage (Settings → Privacy)

- Fully local. No cloud, no analytics, no telemetry.
- SQLite database + content-addressed image blobs at
  `~/Library/Application Support/Birchboard/`. Delete that folder to fully
  reset.
- **Clear unpinned** / **Clear all history** buttons.
- **Ignored apps list** — add / remove / reset-to-defaults.
- **Export / Import** — the full history, including image bytes, goes into
  a single JSON file via `NSSavePanel`. Import reads the same shape back;
  duplicates are detected by content hash so re-importing the same file
  is a no-op.

## Permissions

- **Accessibility** — required so Birchboard can post a synthetic ⌘V to the
  previously focused app after you pick an entry. Granted via System
  Settings → Privacy & Security → Accessibility. If declined, Birchboard
  still collects history; you can ⌘V manually after selecting an entry.
- **Sandboxing** — disabled. A clipboard manager needs to observe the
  pasteboard, post HID events globally, and access arbitrary file URLs, none
  of which play well with the App Sandbox.

---

## Keyboard cheat sheet

While the panel is open:

| Shortcut       | Action                                      |
|---------------|---------------------------------------------|
| **⌘⇧V**       | Open / close the panel                      |
| ↑ / ↓         | Navigate entries                            |
| ⏎             | Paste selected entry                        |
| ⇧⏎            | Paste as plain text                         |
| ⌘1 – ⌘9       | Quick-paste Nth visible entry               |
| ⇧⌘1 – ⇧⌘9     | Quick-paste Nth as plain text               |
| ⌘T            | Transform picker                            |
| ⌘S            | Snippet picker                              |
| ⌘K            | Action picker                               |
| ⌘Y            | Quick Look preview overlay                  |
| ⌘P            | Pin / unpin selected                        |
| ⌘⌫            | Delete selected                             |
| Esc           | Close overlay, or dismiss panel             |
