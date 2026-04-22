import SwiftUI

/// The left-column list shown when the panel is in `.actionPicker` mode.
/// Mirrors `TransformPickerView` / `SnippetPickerView` for visual continuity.
struct ActionPickerView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                if viewModel.actionMatches.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.actionMatches.enumerated()), id: \.element.id) { pair in
                                row(for: pair.element, index: pair.offset)
                                    .id(pair.element.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.actionSelectedIndex) { _, new in
                        guard viewModel.actionMatches.indices.contains(new) else { return }
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(viewModel.actionMatches[new].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))
            Text("Action")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            Text("⏎ run · Esc cancel")
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
            Text("No matches")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            Text("Try a different search, or press Esc.")
                .foregroundStyle(.tertiary)
                .font(.system(size: 10))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(for action: any EntryAction, index: Int) -> some View {
        let selected = index == viewModel.actionSelectedIndex
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(action.displayName)
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.applyAction(action)
        }
        .simultaneousGesture(TapGesture().onEnded {
            viewModel.actionSelectedIndex = index
        })
    }
}
