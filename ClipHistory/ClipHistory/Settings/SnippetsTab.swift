import SwiftUI

/// Settings tab for snippet CRUD. Two-column layout: list on the left, editor
/// on the right. Name and body writes flow back through `SnippetStore` which
/// persists on every change — no "save" button.
struct SnippetsTab: View {
    @EnvironmentObject var store: SnippetStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            detail
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.snippets) { snippet in
                    Text(snippet.displayName)
                        .lineLimit(1)
                        .tag(snippet.id)
                }
                .onMove { source, destination in
                    store.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 6) {
                Button {
                    let created = store.add()
                    selection = created.id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New snippet")

                Button {
                    if let id = selection {
                        let index = store.snippets.firstIndex { $0.id == id }
                        store.remove(id: id)
                        // Select a neighbour so the editor isn't blank.
                        if let index {
                            let next = min(index, store.snippets.count - 1)
                            selection = store.snippets.indices.contains(next)
                                ? store.snippets[next].id : nil
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("Delete selected snippet")

                Spacer()
            }
            .padding(6)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection,
           let snippet = store.snippet(withID: id) {
            SnippetEditor(snippet: snippet, store: store)
                .id(snippet.id) // reset @State when selection changes
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Select or create a snippet")
                .foregroundStyle(.secondary)
            Text("Press ⌘S in the panel to paste a snippet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let store: SnippetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $snippet.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .medium))
                .onChange(of: snippet.name) { _, _ in persist() }

            Text("Body")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $snippet.body)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
                .onChange(of: snippet.body) { _, _ in persist() }

            placeholderLegend

            HStack {
                Spacer()
                Text(updatedLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }

    private var placeholderLegend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Placeholders")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("{clipboard} · {date} · {date:yyyy-MM-dd} · {time} · {uuid} · {newline} · {tab}")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var updatedLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: snippet.updatedAt))"
    }

    private func persist() {
        store.update(snippet)
    }
}
