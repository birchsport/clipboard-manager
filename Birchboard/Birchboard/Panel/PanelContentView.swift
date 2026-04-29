import SwiftUI
import AppKit
import Combine

/// Root SwiftUI view hosted inside the clipboard panel. Contains:
///   - search field
///   - two-column split: entry list (left) + preview (right)
/// Keyboard handling is driven by the parent `PanelController`'s local event monitor,
/// which calls `viewModel.handle(event:)`.
struct PanelContentView: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar. Icon + placeholder + binding all swap on mode so the user
            // sees immediately what they're filtering.
            HStack(spacing: 8) {
                Image(systemName: searchIcon)
                    .foregroundStyle(.secondary)
                TextField(searchPlaceholder, text: searchTextBinding)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Split: list/picker on the left, preview on the right.
            HStack(spacing: 0) {
                Group {
                    if isTransformMode {
                        TransformPickerView(viewModel: viewModel)
                    } else if isSnippetMode {
                        SnippetPickerView(viewModel: viewModel)
                    } else if isActionMode {
                        ActionPickerView(viewModel: viewModel)
                    } else {
                        EntryListView(viewModel: viewModel)
                    }
                }
                .frame(width: 320)

                Divider()

                // Preview adapts to mode:
                //  • snippet: live-expanded body of the selected snippet
                //  • transform / action / browse: the source entry
                Group {
                    if isSnippetMode {
                        SnippetPreview(text: viewModel.previewForSelectedSnippet())
                    } else {
                        EntryPreviewView(entry: previewEntry)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(.thickMaterial)
        .frame(minWidth: 560, minHeight: 360)
        .overlay {
            if viewModel.isQuickLookOpen {
                QuickLookView(entry: viewModel.selectedEntry)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: viewModel.isQuickLookOpen)
        .onAppear {
            // Next runloop — otherwise SwiftUI hasn't finished attaching the field
            // and the @FocusState write is dropped.
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: viewModel.focusRequestTick) { _, _ in
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: - Mode-derived bindings

    private var isTransformMode: Bool {
        if case .transformPicker = viewModel.mode { return true }
        return false
    }

    private var isSnippetMode: Bool {
        if case .snippetPicker = viewModel.mode { return true }
        return false
    }

    private var isActionMode: Bool {
        if case .actionPicker = viewModel.mode { return true }
        return false
    }

    private var isNicknameMode: Bool {
        if case .nicknameEditor = viewModel.mode { return true }
        return false
    }

    private var searchIcon: String {
        if isTransformMode { return "wand.and.stars" }
        if isSnippetMode   { return "text.badge.plus" }
        if isActionMode    { return "bolt" }
        if isNicknameMode  { return "lock.fill" }
        return "magnifyingglass"
    }

    private var searchPlaceholder: String {
        if isTransformMode { return "Filter transforms…" }
        if isSnippetMode   { return "Find snippet…" }
        if isActionMode    { return "Filter actions…" }
        if isNicknameMode  { return "Nickname (optional) — ⏎ to save, Esc to cancel" }
        return "Search clipboard…"
    }

    /// Route the single TextField to the correct query depending on mode.
    private var searchTextBinding: Binding<String> {
        Binding(
            get: {
                if isTransformMode { return viewModel.transformQuery }
                if isSnippetMode   { return viewModel.snippetQuery }
                if isActionMode    { return viewModel.actionQuery }
                if isNicknameMode  { return viewModel.nicknameDraft }
                return viewModel.query
            },
            set: { newValue in
                if isTransformMode {
                    viewModel.transformQuery = newValue
                } else if isSnippetMode {
                    viewModel.snippetQuery = newValue
                } else if isActionMode {
                    viewModel.actionQuery = newValue
                } else if isNicknameMode {
                    viewModel.nicknameDraft = newValue
                } else {
                    viewModel.query = newValue
                }
            }
        )
    }

    /// In transform / action mode, show the source entry in the preview so the
    /// user can see what they're operating on. In nickname-editor mode show
    /// the entry being renamed with the live draft applied.
    private var previewEntry: ClipEntry? {
        if case .transformPicker(let source, _) = viewModel.mode {
            return source
        }
        if case .actionPicker(let source, _) = viewModel.mode {
            return source
        }
        if case .nicknameEditor(let entry, _) = viewModel.mode {
            // Live preview: force obfuscated rendering with the draft
            // nickname applied. The repository toggle is async via the
            // change publisher, so the captured `entry` may not yet show
            // `isObfuscated == true`; we coerce it for the preview.
            var live = entry
            if live.obfuscatedAt == nil { live.obfuscatedAt = Date() }
            let trimmed = viewModel.nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            live.obfuscationNickname = trimmed.isEmpty ? nil : trimmed
            return live
        }
        return viewModel.selectedEntry
    }
}

/// Simple monospaced text preview used for snippet expansion.
private struct SnippetPreview: View {
    let text: String?

    var body: some View {
        Group {
            if let text, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Pick a snippet to preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct EntryListView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { pair in
                        row(for: pair.element, index: pair.offset)
                            .id(pair.element.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { _, new in
                guard viewModel.entries.indices.contains(new) else { return }
                withAnimation(.linear(duration: 0.08)) {
                    proxy.scrollTo(viewModel.entries[new].id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: ClipEntry, index: Int) -> some View {
        let selected = index == viewModel.selectedIndex
        let shortcut = index < 9 ? "⌘\(index + 1)" : nil
        let batchOrder = viewModel.batchedOrder.firstIndex(of: entry.id).map { $0 + 1 }
        EntryRow(entry: entry,
                 isSelected: selected,
                 shortcutHint: shortcut,
                 batchOrder: batchOrder)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                viewModel.actions.paste(entry, asPlainText: false)
            }
            .simultaneousGesture(
                TapGesture().modifiers(.command).onEnded {
                    viewModel.selectedIndex = index
                    viewModel.toggleBatch(entryID: entry.id)
                }
            )
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.selectedIndex = index
            })
    }
}

private struct EntryRow: View {
    let entry: ClipEntry
    let isSelected: Bool
    /// Non-nil for the first nine entries — rendered as a small right-aligned
    /// badge so the ⌘N quick-select is discoverable.
    let shortcutHint: String?
    /// 1-based position in the multi-paste batch, or nil if not in the batch.
    /// When set, the right-edge badge shows this number and the row gets a
    /// leading accent bar so it reads as "selected for batch" at a glance.
    let batchOrder: Int?

    var body: some View {
        HStack(spacing: 8) {
            // Leading accent bar — visible only when this row is in the batch.
            // Always reserves the same width so non-batched rows don't shift.
            Rectangle()
                .fill(batchOrder != nil ? Color.accentColor : .clear)
                .frame(width: 2)
                .clipShape(Capsule())
            icon
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .lineLimit(2)
                    .font(.system(size: 12))
                HStack(spacing: 6) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 9))
                    }
                    if entry.isObfuscated {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 9))
                    }
                    if let src = entry.source?.name {
                        Text(src)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                    }
                    if let lang = detectedLanguage {
                        languageChip(lang)
                    }
                    Spacer(minLength: 0)
                    Text(relativeTime(from: entry.createdAt))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 10))
                }
            }
            // Batch badge takes priority over the ⌘N shortcut hint — when a
            // row is in the batch, that's the more relevant signal.
            if let batchOrder {
                batchBadge(batchOrder)
            } else if let shortcutHint {
                shortcutBadge(shortcutHint)
            }
        }
        .padding(.vertical, 2)
    }

    /// Detected language for this entry, if any — only checked for text /
    /// rtf entries since images and file URLs can't be code. Obfuscated
    /// entries skip detection entirely so the language chip doesn't leak
    /// hints about the underlying payload.
    private var detectedLanguage: DetectedLanguage? {
        if entry.isObfuscated { return nil }
        switch entry.kind {
        case .text(let s):
            return LanguageDetector.detect(s, cacheKey: "text-\(entry.id)")
        case .rtf(_, let plain):
            return LanguageDetector.detect(plain, cacheKey: "rtf-\(entry.id)")
        case .image, .fileURLs:
            return nil
        }
    }

    /// Compact uppercase chip shown next to the source-app name when we
    /// detected a language. Uses the same visual weight as the source app
    /// name so code-ish rows stay scannable without dominating the row.
    private func languageChip(_ language: DetectedLanguage) -> some View {
        Text(language.chipLabel)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
            )
    }

    /// Small right-aligned "⌘N" chip. Selected rows get a slightly stronger
    /// tint so the badge stays legible against the accent background.
    private func shortcutBadge(_ hint: String) -> some View {
        Text(hint)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected
                          ? Color.white.opacity(0.15)
                          : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    /// Numbered chip shown when the row is part of the multi-paste batch.
    /// Rendered with the accent fill so it reads distinctly from the muted
    /// `⌘N` shortcut hint.
    private func batchBadge(_ position: Int) -> some View {
        Text("\(position)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
            )
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .image:
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        case .fileURLs:
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
        case .rtf:
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
        case .text:
            if let nsimage = entry.source?.icon {
                Image(nsImage: nsimage).resizable().scaledToFit()
            } else {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewText: String {
        if entry.isObfuscated {
            let dots = "••••••••"
            if let nick = entry.obfuscationNickname, !nick.isEmpty {
                return "\(nick)  \(dots)"
            }
            return dots
        }
        switch entry.kind {
        case .image(_, let w, let h, _):
            return "Image — \(w)×\(h)"
        case .fileURLs(let urls):
            if urls.count == 1 {
                return urls[0].lastPathComponent
            }
            return "\(urls.count) files"
        default:
            let trimmed = entry.searchText.replacingOccurrences(of: "\n", with: " ")
            return trimmed.isEmpty ? "(empty)" : trimmed
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct EntryPreviewView: View {
    let entry: ClipEntry?

    var body: some View {
        ZStack {
            if let entry {
                content(for: entry)
                    .padding(14)
            } else {
                Text("No entries")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for entry: ClipEntry) -> some View {
        if entry.isObfuscated {
            obfuscatedView(for: entry)
        } else {
            payloadContent(for: entry)
        }
    }

    @ViewBuilder
    private func obfuscatedView(for entry: ClipEntry) -> some View {
        VStack(spacing: 8) {
            Spacer()
            if let nick = entry.obfuscationNickname, !nick.isEmpty {
                Text(nick)
                    .font(.system(size: 14, weight: .medium))
            } else {
                Text("(no nickname)")
                    .italic()
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
            }
            Text("••••••••")
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Hidden — ⌘O to reveal, ⌘R to rename")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func payloadContent(for entry: ClipEntry) -> some View {
        switch entry.kind {
        case .text(let s):
            ScrollView {
                Text(s)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .rtf(_, let plain):
            ScrollView {
                Text(plain)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .image(let path, let w, let h, _):
            VStack(spacing: 8) {
                if let image = NSImage(contentsOf: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Image unavailable")
                        .foregroundStyle(.secondary)
                }
                Text("\(w) × \(h)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .fileURLs(let urls):
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(urls, id: \.self) { url in
                        Text(url.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
