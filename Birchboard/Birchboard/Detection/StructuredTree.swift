import Foundation
import Yams

/// In-memory tree of a structured-data payload (JSON, YAML, …) — nodes carry
/// a display label and either a leaf value or an ordered list of children.
/// Consumed by `TreeView` in the panel.
indirect enum TreeNode: Identifiable {
    /// `label` is the bracketed key or index as rendered in the tree ("foo",
    /// "[0]", etc.). The root has a nil label. `value` is the formatted
    /// string form of a leaf.
    case leaf(id: UUID, label: String?, value: TreeValue)
    case branch(id: UUID, label: String?, kind: BranchKind, children: [TreeNode])

    enum BranchKind { case object, array }

    enum TreeValue {
        case string(String)
        case number(String)
        case bool(Bool)
        case null
    }

    var id: UUID {
        switch self {
        case .leaf(let id, _, _): return id
        case .branch(let id, _, _, _): return id
        }
    }

    /// True for container nodes (objects and arrays) — the tree view shows
    /// a disclosure chevron only on these.
    var isBranch: Bool {
        if case .branch = self { return true }
        return false
    }
}

/// Parsers that turn a text payload into a `TreeNode`. Fails softly: if the
/// payload doesn't parse, returns nil and the caller falls back to the flat
/// preview.
enum StructuredTreeBuilder {

    static func fromJSON(_ text: String) -> TreeNode? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]
              ) else { return nil }
        return node(from: obj, label: nil)
    }

    static func fromYAML(_ text: String) -> TreeNode? {
        guard let obj = try? Yams.load(yaml: text) else { return nil }
        // A bare string is valid YAML but not useful as a tree — require a
        // container.
        guard obj is [String: Any] || obj is [Any] else { return nil }
        return node(from: obj, label: nil)
    }

    static func fromXML(_ text: String) -> TreeNode? {
        guard let data = text.data(using: .utf8) else { return nil }
        // `XMLDocument` is macOS-only but so are we. Options are default —
        // strict parse; if the payload isn't well-formed we fall through to
        // the flat highlighted preview.
        guard let doc = try? XMLDocument(data: data, options: []),
              let root = doc.rootElement() else {
            return nil
        }
        return xmlNode(from: root)
    }

    // MARK: - XML element → TreeNode

    /// Each element maps to either a leaf (if it has no attributes and no
    /// child elements — just text) or a branch whose children are, in
    /// order: `@attributes`, nested elements, and a `#text` leaf when the
    /// element mixes text with structured children.
    private static func xmlNode(from element: XMLElement) -> TreeNode {
        let label = "<\(element.name ?? "element")>"
        let attrs = element.attributes ?? []

        var childElements: [XMLElement] = []
        var accumulatedText = ""
        for childNode in element.children ?? [] {
            if let elem = childNode as? XMLElement {
                childElements.append(elem)
            } else if childNode.kind == .text {
                accumulatedText += childNode.stringValue ?? ""
            }
            // Comments / CDATA / processing instructions skipped in v1.
        }
        let trimmedText = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Leaf shortcut: simple `<foo>bar</foo>` or `<foo></foo>` with no
        // attributes reads cleanly as `<foo>: "bar"`.
        if attrs.isEmpty && childElements.isEmpty {
            return .leaf(id: UUID(), label: label, value: .string(trimmedText))
        }

        var children: [TreeNode] = []
        for attr in attrs {
            let attrLabel = "@\(attr.name ?? "")"
            let attrValue = attr.stringValue ?? ""
            children.append(.leaf(id: UUID(), label: attrLabel, value: .string(attrValue)))
        }
        for elem in childElements {
            children.append(xmlNode(from: elem))
        }
        if !trimmedText.isEmpty {
            children.append(.leaf(id: UUID(), label: "#text", value: .string(trimmedText)))
        }

        return .branch(id: UUID(), label: label, kind: .object, children: children)
    }

    // MARK: - Any → TreeNode

    /// Walks a Foundation/JSON/YAML value tree and emits `TreeNode`s.
    /// Object children are sorted by key for stable presentation.
    private static func node(from value: Any?, label: String?) -> TreeNode {
        switch value {
        case let dict as [String: Any]:
            let children = dict
                .sorted { $0.key < $1.key }
                .map { node(from: $0.value, label: $0.key) }
            return .branch(id: UUID(), label: label, kind: .object, children: children)

        case let arr as [Any]:
            let children = arr.enumerated().map { idx, element in
                node(from: element, label: "[\(idx)]")
            }
            return .branch(id: UUID(), label: label, kind: .array, children: children)

        case let s as String:
            return .leaf(id: UUID(), label: label, value: .string(s))

        case let b as Bool:
            // `Bool as NSNumber` and `NSNumber as Bool` cross-cast in
            // Foundation — the explicit case above catches true/false
            // coming out of Yams, which returns Swift Bools directly.
            return .leaf(id: UUID(), label: label, value: .bool(b))

        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .leaf(id: UUID(), label: label, value: .bool(n.boolValue))
            }
            if CFNumberIsFloatType(n) {
                return .leaf(id: UUID(), label: label,
                             value: .number(String(n.doubleValue)))
            }
            return .leaf(id: UUID(), label: label,
                         value: .number(String(n.int64Value)))

        case is NSNull:
            return .leaf(id: UUID(), label: label, value: .null)

        case nil:
            return .leaf(id: UUID(), label: label, value: .null)

        default:
            return .leaf(id: UUID(), label: label,
                         value: .string(String(describing: value ?? "")))
        }
    }
}
