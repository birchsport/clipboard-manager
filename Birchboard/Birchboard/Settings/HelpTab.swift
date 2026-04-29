import SwiftUI

/// A built-in reference inside Settings — keyboard shortcuts, feature
/// summaries, and snippet-placeholder cheat sheet. Mirrors the top of
/// FEATURES.md; if something here drifts out of date, FEATURES.md is
/// the canonical source.
struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overview
                Divider()
                shortcuts
                Divider()
                capture
                browsing
                multiSelect
                previews
                obfuscation
                transforms
                snippets
                actions
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var overview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Birchboard")
                .font(.system(size: 16, weight: .semibold))
            Text("A clipboard history manager that runs as a background menu-bar agent. Hit the global hotkey anywhere to summon a floating panel over any app, pick an entry, paste.")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Keyboard shortcuts")
            Text("With the panel open:")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            ForEach(HelpTab.shortcutRows, id: \.0) { row in
                shortcutRow(key: row.0, action: row.1)
            }
        }
    }

    private static let shortcutRows: [(String, String)] = [
        ("⌘⇧V",       "Open / close the panel"),
        ("↑ / ↓",      "Navigate entries"),
        ("⏎",          "Paste selected entry, or batch when multi-select is active"),
        ("⇧⏎",         "Paste as plain text"),
        ("⌘1 – ⌘9",    "Quick-paste Nth visible entry (ignores multi-select)"),
        ("⇧⌘1 – ⇧⌘9",  "Quick-paste Nth as plain text"),
        ("⇧Space",     "Add / remove the selected row from a multi-paste batch"),
        ("⇧↑ / ⇧↓",    "Extend the batch contiguously"),
        ("⌘-click",    "Toggle a row in the batch (mouse equivalent of ⇧Space)"),
        ("⌘T",         "Transform picker"),
        ("⌘S",         "Snippet picker"),
        ("⌘K",         "Action picker"),
        ("⌘Y",         "Quick Look preview overlay"),
        ("⌘P",         "Pin / unpin selected"),
        ("⌘O",         "Obfuscate / un-obfuscate selected (hides content for screen-share)"),
        ("⌘R",         "Rename obfuscated entry's nickname"),
        ("⌘⌫",         "Delete selected"),
        ("Esc",        "Close overlay, or dismiss panel"),
    ]

    private var capture: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Capture")
            bullet("Text, RTF, images, and file references are all captured.")
            bullet("Each entry shows the app it was copied from.")
            bullet("Ignore list (Privacy tab) skips capture while password managers are frontmost.")
            bullet("Apps using the `org.nspasteboard.ConcealedType` / `TransientType` convention are respected silently.")
        }
    }

    private var browsing: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Browsing")
            bullet("fzf-style fuzzy search: word-boundary, consecutive-match, and camelCase bonuses.")
            bullet("Type `image` to find image entries, `file` for file references, or image dimensions like `400x300`.")
            bullet("⌘1 – ⌘9 quick-paste the Nth visible row; the hint chip is shown inline on the first nine rows.")
            bullet("Rows detected as code (17 languages) show a language chip next to the source app.")
            bullet("⌘P to pin, ⌘⌫ to delete, Esc to dismiss.")
        }
    }

    private var multiSelect: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Multi-paste")
            Text("Gather several entries and paste them together with a configurable delimiter. Useful for stitching IDs, URLs, names, or scratch values that piled up across a session.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
            bullet("⇧Space toggles the focused row in the batch — a numbered chip and accent bar mark the selected rows.")
            bullet("⇧↑ / ⇧↓ extends the batch contiguously, like Finder. ⌘-click is the mouse equivalent of ⇧Space.")
            bullet("⏎ pastes the batch joined by the delimiter (default newline). The original ⏎ behaviour for a single row is unchanged when the batch is empty.")
            bullet("⌘1 – ⌘9 still pastes that single row directly, ignoring an active batch.")
            bullet("Delimiter is configurable in Settings → General → Multi-select. Use \\n for newline, \\t for tab.")
            bullet("Image and obfuscated rows beep on toggle — the first has no plain-text payload, the second would leak its value through concatenation.")
            bullet("The batch resets every time the panel opens.")
        }
    }

    private var previews: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Previews")
            bullet("The right-side pane renders text with syntax highlighting when a language is detected.")
            bullet("⌘Y opens a full-panel Quick Look overlay for the selected entry.")
            bullet("For JSON, YAML, or XML entries, Quick Look shows a collapsible tree instead of flat text. Click any `{ … keys }` / `[ … items ]` / `<tag>` row to expand or collapse; each subtree toggles independently.")
        }
    }

    private var obfuscation: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("⌘O — Obfuscate (screen-share safety)")
            Text("Pin a password or other secret you paste daily, then mark it obfuscated. Birchboard hides the content everywhere — list, preview pane, Quick Look — but the real value still pastes when you hit ⏎.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
            bullet("⌘O on a text entry hides it. Toggle again to reveal.")
            bullet("Optional nickname (e.g. `aws-prod`) shown in place of the value — set on first toggle, edit later with ⌘R.")
            bullet("Search hits the nickname only — typing the underlying value won't filter to it.")
            bullet("Transforms / actions / Quick Look are blocked while obfuscated, so the payload is never lexed or rendered.")
            bullet("Obfuscated rows are exempt from retention sweeps (just like pinned).")
        }
    }

    private var transforms: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("⌘T — Transform picker")
            Text("Replace the clipboard payload before pasting. Inapplicable transforms are hidden automatically.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
            bullet("JSON — pretty-print / minify.")
            bullet("JSON ↔ YAML — auto-direction.")
            bullet("JWT decode (header + payload pretty-printed).")
            bullet("Unix time ↔ ISO 8601 (auto-direction; 10- or 13-digit input).")
            bullet("SHA-256 / SHA-1 / MD5.")
            bullet("Number bases — dec / hex / bin simultaneously.")
            bullet("Query string ↔ JSON.")
            bullet("Base64 encode / decode, URL encode / decode.")
            bullet("Case — UPPER / lower / Title / camel / snake / kebab.")
            bullet("Trim whitespace (whole-string, per-line trailing, or per-line both ends).")
            bullet("Strip ANSI escape codes / HTML tags.")
            bullet("Extract all URLs or all email addresses from free text.")
        }
    }

    private var snippets: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("⌘S — Snippets")
            Text("User-authored canned text. Manage them in the Snippets tab.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Placeholders expand at paste time:")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            placeholderRow("{clipboard}", "Current pasteboard text.")
            placeholderRow("{date}", "Today in `yyyy-MM-dd`.")
            placeholderRow("{date:FMT}", "Today formatted with any DateFormatter pattern.")
            placeholderRow("{time}", "Now in `HH:mm:ss`.")
            placeholderRow("{time:FMT}", "Now formatted with any DateFormatter pattern.")
            placeholderRow("{uuid}", "A fresh UUID.")
            placeholderRow("{newline} / {tab}", "Literal `\\n` / `\\t`.")
            placeholderRow("{{ / }}", "Literal braces.")
            Text("Unknown tokens pass through unchanged.")
                .foregroundStyle(.tertiary)
                .font(.system(size: 10))
                .padding(.top, 2)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("⌘K — Actions")
            Text("Type-specific shortcuts for the selected entry. Only applicable actions are shown.")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
            bullet("URL → Open in Browser, Paste as Markdown link.")
            bullet("File(s) → Reveal in Finder, Open.")
            bullet("Email → Compose Mail to…")
            bullet("Phone → Call with FaceTime.")
            bullet("Hex color → Paste as `rgb()`, Paste as `hsl()`.")
        }
    }

    // MARK: - Reusable row builders

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.top, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutRow(key: String, action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
            Text(action)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func placeholderRow(_ token: String, _ meaning: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(token)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 130, alignment: .leading)
            Text(meaning)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
