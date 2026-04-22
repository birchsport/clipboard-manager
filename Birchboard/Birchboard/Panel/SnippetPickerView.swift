import SwiftUI

/// The left-column list shown when the panel is in `.snippetPicker` mode.
/// Mirrors the shape of `EntryListView` / `TransformPickerView` for visual
/// continuity.
struct SnippetPickerView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                if viewModel.snippetMatches.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.snippetMatches.enumerated()), id: \.element.id) { pair in
                                row(for: pair.element, index: pair.offset)
                                    .id(pair.element.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.snippetSelectedIndex) { _, new in
                        guard viewModel.snippetMatches.indices.contains(new) else { return }
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(viewModel.snippetMatches[new].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))
            Text("Snippet")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            Text("⏎ paste · Esc cancel")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "text.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(noSnippetsAtAll ? "No snippets yet" : "No matches")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            Text(noSnippetsAtAll
                 ? "Add snippets in Settings → Snippets."
                 : "Try a different search, or press Esc.")
                .foregroundStyle(.tertiary)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Distinguish "user hasn't authored any" from "zero match for this query".
    private var noSnippetsAtAll: Bool {
        viewModel.snippetMatches.isEmpty &&
        viewModel.snippetQuery.isEmpty
    }

    @ViewBuilder
    private func row(for snippet: Snippet, index: Int) -> some View {
        let selected = index == viewModel.snippetSelectedIndex
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(bodyPreview(snippet.body))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.applySnippet(snippet)
        }
        .simultaneousGesture(TapGesture().onEnded {
            viewModel.snippetSelectedIndex = index
        })
    }

    private func bodyPreview(_ body: String) -> String {
        let single = body.replacingOccurrences(of: "\n", with: " ")
        if single.count <= 60 { return single }
        return String(single.prefix(60)) + "…"
    }
}
