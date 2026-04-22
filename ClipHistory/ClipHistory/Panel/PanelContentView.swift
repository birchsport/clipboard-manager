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
                Image(systemName: isTransformMode ? "wand.and.stars" : "magnifyingglass")
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
                    } else {
                        EntryListView(viewModel: viewModel)
                    }
                }
                .frame(width: 320)

                Divider()

                // The preview always shows the currently-selected browse entry. In
                // transform mode that's the source we'll transform, which is
                // useful context while the user picks.
                EntryPreviewView(entry: previewEntry)
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

    private var searchPlaceholder: String {
        isTransformMode ? "Filter transforms…" : "Search clipboard…"
    }

    /// Route the single TextField to either browse query or transform query
    /// depending on mode.
    private var searchTextBinding: Binding<String> {
        Binding(
            get: {
                isTransformMode ? viewModel.transformQuery : viewModel.query
            },
            set: { newValue in
                if isTransformMode {
                    viewModel.transformQuery = newValue
                } else {
                    viewModel.query = newValue
                }
            }
        )
    }

    /// In transform mode, show the source entry in the preview so the user can
    /// see what they're transforming.
    private var previewEntry: ClipEntry? {
        if case .transformPicker(let source, _) = viewModel.mode {
            return source
        }
        return viewModel.selectedEntry
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
        EntryRow(entry: entry, isSelected: selected, shortcutHint: shortcut)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                viewModel.actions.paste(entry, asPlainText: false)
            }
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

    var body: some View {
        HStack(spacing: 8) {
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
                    if let src = entry.source?.name {
                        Text(src)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                    }
                    Spacer(minLength: 0)
                    Text(relativeTime(from: entry.createdAt))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 10))
                }
            }
            if let shortcutHint {
                shortcutBadge(shortcutHint)
            }
        }
        .padding(.vertical, 2)
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
        switch entry.kind {
        case .text(let s):
            ScrollView {
                Text(s)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .rtf(_, let plain):
            ScrollView {
                Text(plain)
                    .font(.system(.body, design: .monospaced))
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
