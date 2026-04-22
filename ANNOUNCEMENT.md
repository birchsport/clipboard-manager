# Birchboard — a macOS clipboard manager

Hey — I built a clipboard history app for macOS and I'd love a few people to
try it. Download: [link to DMG].

Requires macOS 14 (Sonoma) or newer. Apple Silicon or Intel.

---

## What it is

A background clipboard manager. Hit **⌘⇧V** anywhere and a floating panel
appears over whatever you're doing (including fullscreen apps). Pick an
entry, hit ⏎, it pastes into whatever you had open a second ago — original
formatting preserved. That's the 90% case.

The other 10% is where it earns its keep:

- **Transforms** — pretty-print JSON, base64 encode/decode, convert case,
  strip ANSI codes, extract URLs — with one keystroke, on the thing you
  just copied.
- **Snippets** — canned text with placeholders (`{clipboard}`, `{date}`,
  `{uuid}`), available from the same panel.
- **Type-aware actions** — copied a URL? Open it in your browser without
  pasting. File path? Reveal in Finder. Hex color? Paste it back as `rgb()`.

---

## Features

### Capture
- Text, RTF, images, and file references.
- Remembers which app you copied from (shown next to each entry).
- **Ignore list**: skip capture while password-manager apps are frontmost.
  Ships with 1Password, Bitwarden, Keychain Access, Apple Passwords,
  LastPass, KeePassXC; editable via a file picker in Settings.
- **nspasteboard.org convention**: apps that mark copies as
  concealed/transient are silently ignored.

### Browsing
- fzf-style **fuzzy search** as you type (word-boundary / consecutive /
  camelCase bonuses).
- Arrow keys to navigate, ⏎ to paste, ⇧⏎ to paste as plain text.
- **⌘1–⌘9 quick-paste** the Nth visible entry. The first nine rows show
  their shortcut inline so you don't have to remember which is which.
- **⌘Y Quick Look** — a full-panel preview overlay: full-size images,
  larger monospaced text, file paths with icons. Arrow keys still
  navigate while it's open.
- **Pin** important entries (⌘P) so they stay on top.
- **Delete** with ⌘⌫.

### ⌘T — Transform picker
Replace the clipboard payload with one of 16 transforms before it pastes:

- **JSON** — pretty-print, minify.
- **Encoding** — Base64 encode / decode, URL encode / decode.
- **Case** — UPPER, lower, Title, camelCase, snake_case, kebab-case.
- **Strip** — ANSI escape codes, HTML tags.
- **Extract** — all URLs, all email addresses.

Fuzzy-filter transforms by name, ⏎ applies and pastes. Inapplicable
transforms (e.g. "Pretty JSON" over non-JSON text) are hidden upfront.

### ⌘S — Snippets
User-authored canned text you can paste without having copied it first.
Settings → Snippets → `+` to author them. Placeholders expand at paste time:

- `{clipboard}` — whatever's currently on the clipboard.
- `{date}` / `{date:yyyy-MM-dd}` / any `DateFormatter` template.
- `{time}` / `{time:HH:mm}`.
- `{uuid}` — a fresh one each expansion.
- `{newline}`, `{tab}`, `{{` / `}}` for literal braces.

Example snippet body: `Thanks for {clipboard} — logged at {date} {time:HH:mm}.`

### ⌘K — Type-aware actions
The picker only shows actions that make sense for the selected entry:

- **URL** → Open in Browser, Paste as Markdown link.
- **File(s)** → Reveal in Finder, Open.
- **Email** → Compose Mail to….
- **Phone** → Call with FaceTime.
- **Hex color** → Paste as `rgb()`, Paste as `hsl()`.

### Preferences
- **Retention**: cap by count and age (defaults 1000 entries / 90 days).
  Pinned entries never expire. Hourly sweeps run in the background.
- **Panel opacity**: slider, 30–100%.
- **Restore previous clipboard after paste**: optional, so using a history
  entry doesn't perturb your current copy.
- **Launch at login**.
- **Custom global hotkey** via the standard shortcut recorder.

### Privacy
- Everything is local. No cloud, no analytics, no telemetry.
- SQLite database + image blobs at `~/Library/Application Support/Birchboard/`.
  Delete that folder to fully reset.
- "Clear unpinned" / "Clear all" buttons in Settings → Privacy.
- **Export / Import**: Settings → Privacy → Backup dumps the whole history
  (including images) into a single JSON file you can move between Macs or
  stash somewhere as a backup. Re-importing is dedup-safe.

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

---

## Install

1. Download the DMG: [link].
2. Drag **Birchboard** to `/Applications`.
3. Launch. macOS will ask for **Accessibility** permission the first time
   you try to paste — it's required so the app can send ⌘V to the
   previously focused app. Grant it in System Settings → Privacy &
   Security → Accessibility.

It's a background app — no Dock icon, just a clipboard icon in the menu
bar. Right-click that for Settings / Quit.

---

## Caveats

- **macOS 14+** only. I haven't tested earlier.
- First launch prompts for Accessibility, which is legitimately needed for
  the paste-back feature — if you say no, Birchboard still collects history
  but you'll have to `⌘V` manually after selecting an entry.
- It's not sandboxed. A clipboard manager needs to watch the pasteboard,
  post HID events, and read arbitrary file URLs, which doesn't play nicely
  with the App Sandbox.

---

## Feedback

Ping me. Bug reports, feature ideas, "this shortcut collides with X",
anything. I wrote this for myself but I'd rather it work for you too.
