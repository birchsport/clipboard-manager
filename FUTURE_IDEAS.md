# Future Ideas

Candidate features that would differentiate ClipHistory from Alfred / Raycast /
Maccy. Not a commitment — a shortlist to pull from when the itch strikes.

Ordered loosely by effort-to-impact ratio (highest first).

---

## Dev-leaning power moves

These are small, self-contained, and immediately useful for anyone who touches
code or writes in markdown.

### Transformations on paste
`⌘T` over the selected entry opens a menu of transforms that replace the
clipboard payload before `⌘V` fires:

- Pretty JSON / minify JSON
- Base64 encode / decode
- URL encode / decode
- Hex → UTF-8 and back
- Change case: UPPER / lower / Title / camelCase / snake_case / kebab-case
- Strip ANSI escape codes
- Strip RTF / HTML → plain text
- Extract URLs / emails from text

**Implementation sketch:** a `Transform` protocol with a `name`, an optional
`isApplicable(_:EntryKind)`, and `apply(_:EntryKind) -> EntryKind?`. Register
each transform in a registry; render the applicable ones in a SwiftUI menu
keyed by `⌘T`. No new dependencies.

### Template paste
`⌘⇧T` wraps the selected entry in a template before pasting:

- `[{title}]({url})` for URL entries, with title fetched in the background
- ```` ```\n{content}\n``` ```` — fenced code block (language auto-detected)
- `"{content}"` — add quotes
- `<{content}>` — wrap in angle brackets
- Custom templates stored in preferences with `{content}` as placeholder

**Implementation sketch:** small Mustache-lite with only `{content}` and
`{title}` tokens. Templates live in `UserDefaults` as a JSON blob; ships with a
few built-ins.

### Diff two entries
Select two entries with `⌘`-click (or pin-and-compare), hit `⌘D`, open a side
pane showing a unified diff. Saves a dozen manual copy/paste/diff trips per
day when comparing JSON responses, log lines, etc.

**Implementation sketch:** `CollectionDifference` on `String`'s lines for the
algorithm; render with monospaced font and red/green gutters. No deps.

### Multi-entry paste
Select multiple entries (`⌘`-click or marked), hit `⏎`: writes them all to the
clipboard joined by a configurable separator (newline, comma, tab, space), then
pastes.

---

## Content-aware intelligence

### Apple Vision OCR on image entries
Tap an image entry, hit `⌘R` ("recognize"), we run `VNRecognizeTextRequest`
against the image bytes and put the extracted text on the clipboard. On-device,
no network.

**Why it differentiates:** Alfred needs a workflow. Raycast has it but only in
their AI tier. Native Vision + ~50 LOC gives feature parity for free.

### Type-aware row actions
Each entry exposes a small contextual action menu based on detected type:

- **URL** → "Open in browser", "Copy as markdown link (fetch title)"
- **Hex color (`#RRGGBB`, `rgb(...)`)** → color swatch preview, "copy as rgb()"
  / "copy as hsl()"
- **JSON** → formatted tree preview with collapsible nodes
- **Email** → "Compose mail to…"
- **Phone number** → "Call via FaceTime / copy digits only"
- **ISO date / epoch** → "copy as local time / UTC / epoch"

**Implementation sketch:** a lightweight classifier that runs once per entry on
ingest and tags it with detected types. Display tags as chips in the row;
⌘-click or `⌘A` opens the relevant menu.

### Entropy-based secret filter
Augment the existing `nspasteboard.org` concealed-type check with a heuristic:
don't store strings that look like API keys / JWTs / private keys even when the
source app forgets to mark them sensitive.

**Heuristic:** Shannon entropy above ~3.5 bits/char on strings of length
20–120, or regex matches for known formats (JWT `xxx.yyy.zzz`, GitHub tokens,
AWS keys). Keep a preference to disable.

---

## Privacy / context

### Scoped clipboard profiles
"Work" vs "Personal" vs "Research" — each is an isolated history. Switch:

- Manually via status-bar menu or hotkey
- Automatically when the active app matches a profile's app list (e.g., Slack
  + Mail → "Work")
- Automatically by calendar / focus mode

**Implementation sketch:** new `profile_id` column on `entries`; repository
queries filter by active profile. Profile metadata in `UserDefaults`.

### Per-app exclusion list
Never capture clipboard changes while specified apps are frontmost. Default
exclusions: 1Password, Bitwarden, Keychain Access. User-editable.

**Implementation sketch:** in `ClipboardWatcher.tick`, read
`NSWorkspace.shared.frontmostApplication.bundleIdentifier` and skip capture
when it's in the exclusion set.

---

## One-of-a-kind

### Local-network sync between your own Macs (Bonjour)
Discover other ClipHistory instances on the LAN via `NWBrowser`, pair with a
QR-code-verified secret, and optionally mirror the clipboard. No cloud, no
accounts.

**Why it differentiates:** rare feature. Closest thing is 1Clipboard (cross-
device cloud) and Alfred's sync-via-Dropbox, neither of which is local-only.

**Why it's hard:** pairing UX, authenticated transport (TLS with a shared
secret, or Noise protocol), avoiding leaks (don't sync passwords, avoid
looping), conflict resolution, battery impact.

**Implementation sketch:** new `Sync/` module with `BonjourBrowser`,
`Peer`, a pairing flow (nearby device shows a 6-digit code), and selective
push (only text / only pinned / only last N).

### Clipboard journal
A searchable Markdown export of everything you copied today / this week.
Timestamps, source app, pin status. Good for notetakers retroactively
reconstructing what they were working on.

**Implementation sketch:** existing database already has everything. Add a
"Export…" action in the Privacy settings tab that writes a
date-ranged Markdown file with entries grouped by source app.

---

## Smaller nice-to-haves

- **Quick Look preview** — Space-bar on an entry opens a larger Quick Look panel
  (great for images).
- **Pin groups** — pins organized into named collections you can cycle through.
- **Clipboard "chain" replay** — record a sequence of copies, replay them into
  a target app with a small inter-paste delay (form-filling, batch entry).
- **Paste as specific format** — for RTF entries, choose "paste as RTF / HTML /
  markdown / plain".
- **Smart deduplication** — current hash-based dedup is exact-match; fuzzy
  dedup (e.g., trimming trailing whitespace variants of the same text) would
  reduce clutter.
- **Keyboard grammar for compound actions** — `⌘K` then a single letter for
  common actions: `⌘K t` transform, `⌘K d` diff, `⌘K c` chain.

---

## Explicitly not worth pursuing (for this app)

- **Cloud sync** — privacy nightmare for a local tool; if someone wants that,
  they want a different product.
- **AI-everything** — Raycast's angle. Cool for some, but it's a huge
  maintenance burden and lock-in to a vendor's API.
- **Cross-platform (Windows/Linux)** — the whole value here is deep macOS
  integration (nonactivating panel, pasteboard types, Vision, Bonjour).
- **Web clipboard** — completely different product.
