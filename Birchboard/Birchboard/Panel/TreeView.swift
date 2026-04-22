import SwiftUI

/// Renders a `TreeNode` as a recursive, collapsible outline. Used by the
/// Quick Look overlay when the selected entry is structured (JSON / YAML).
/// Each branch has its own `@State` expansion, so toggling one subtree
/// doesn't disturb siblings.
struct TreeView: View {
    let root: TreeNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NodeView(node: root, depth: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NodeView: View {
    let node: TreeNode
    let depth: Int

    @State private var isExpanded: Bool = true

    var body: some View {
        switch node {
        case .leaf(_, let label, let value):
            leafRow(label: label, value: value)

        case .branch(_, let label, let kind, let children):
            branchRow(label: label, kind: kind, children: children)
        }
    }

    // MARK: - Leaf

    private func leafRow(label: String?, value: TreeNode.TreeValue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 16pt slot so leaf text lines up with the label of a branch
            // that has a disclosure chevron in the same column.
            Color.clear.frame(width: 16, height: 1)
            if let label {
                labelText(label)
                Text(":")
                    .foregroundStyle(.secondary)
            }
            valueText(value)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private func valueText(_ value: TreeNode.TreeValue) -> some View {
        switch value {
        case .string(let s):
            return Text("\"\(s)\"")
                .foregroundStyle(CodeHighlighter.Palette.string)
                .font(.system(size: 12, design: .monospaced))
        case .number(let n):
            return Text(n)
                .foregroundStyle(CodeHighlighter.Palette.number)
                .font(.system(size: 12, design: .monospaced))
        case .bool(let b):
            return Text(b ? "true" : "false")
                .foregroundStyle(CodeHighlighter.Palette.literal)
                .font(.system(size: 12, design: .monospaced))
        case .null:
            return Text("null")
                .foregroundStyle(CodeHighlighter.Palette.literal)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    // MARK: - Branch

    @ViewBuilder
    private func branchRow(label: String?,
                           kind: TreeNode.BranchKind,
                           children: [TreeNode]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.08)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 12)
            }
            .buttonStyle(.plain)

            if let label {
                labelText(label)
                Text(":")
                    .foregroundStyle(.secondary)
            }

            Text(summary(for: kind, count: children.count))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.08)) { isExpanded.toggle() }
        }

        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    NodeView(node: child, depth: depth + 1)
                }
            }
            .padding(.leading, 16) // indent width matches the chevron slot
        }
    }

    // MARK: - Helpers

    /// How a node's label is rendered depends on a leading sigil:
    /// - `[0]`  — JSON/YAML array index (tertiary, no quotes)
    /// - `<tag>` — XML element name (type colour, no quotes)
    /// - `@attr` — XML attribute name (key colour, no quotes)
    /// - `#text` — XML text node marker (tertiary italic)
    /// - anything else — JSON/YAML object key (quoted, key colour)
    @ViewBuilder
    private func labelText(_ label: String) -> some View {
        if label.hasPrefix("[") && label.hasSuffix("]") {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
        } else if label.hasPrefix("<") && label.hasSuffix(">") {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CodeHighlighter.Palette.type)
        } else if label.hasPrefix("@") {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CodeHighlighter.Palette.key)
        } else if label == "#text" {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
                .italic()
        } else {
            Text("\"\(label)\"")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CodeHighlighter.Palette.key)
        }
    }

    private func summary(for kind: TreeNode.BranchKind, count: Int) -> String {
        let noun = count == 1 ? "item" : "items"
        switch kind {
        case .object: return count == 0 ? "{}" : "{ \(count) \(count == 1 ? "key" : "keys") }"
        case .array:  return count == 0 ? "[]" : "[ \(count) \(noun) ]"
        }
    }
}
