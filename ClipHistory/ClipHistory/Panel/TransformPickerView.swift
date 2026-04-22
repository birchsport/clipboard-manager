import SwiftUI

/// The list shown in the left column while the panel is in `.transformPicker`
/// mode. Structurally mirrors `EntryListView` so the visual weight doesn't shift
/// when switching modes.
struct TransformPickerView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                if viewModel.transformMatches.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.transformMatches.enumerated()), id: \.element.id) { pair in
                                row(for: pair.element, index: pair.offset)
                                    .id(pair.element.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.transformSelectedIndex) { _, new in
                        guard viewModel.transformMatches.indices.contains(new) else { return }
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(viewModel.transformMatches[new].id, anchor: .center)
                        }
                    }
                }
                if let error = viewModel.transformError {
                    errorBar(error)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))
            Text("Transform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            Text("⏎ apply · Esc cancel")
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
            Text("No transforms match")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            Text("Try a different search, or press Esc to cancel.")
                .foregroundStyle(.tertiary)
                .font(.system(size: 10))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 10))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    @ViewBuilder
    private func row(for transform: any TextTransform, index: Int) -> some View {
        let selected = index == viewModel.transformSelectedIndex
        HStack(spacing: 8) {
            Image(systemName: icon(for: transform.id))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(transform.displayName)
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
            viewModel.applyTransform(transform)
        }
        .simultaneousGesture(TapGesture().onEnded {
            viewModel.transformSelectedIndex = index
        })
    }

    /// Quick visual cue per transform family. Not meant to be exhaustive — falls
    /// back to a generic wand.
    private func icon(for id: String) -> String {
        switch id {
        case let s where s.hasPrefix("json."):    return "curlybraces"
        case let s where s.hasPrefix("base64."):  return "number"
        case let s where s.hasPrefix("url."):     return "link"
        case let s where s.hasPrefix("case."):    return "textformat"
        case let s where s.hasPrefix("strip."):   return "scissors"
        case let s where s.hasPrefix("extract."): return "list.bullet"
        default:                                  return "wand.and.stars"
        }
    }
}

