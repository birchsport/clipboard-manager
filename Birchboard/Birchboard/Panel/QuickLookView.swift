import SwiftUI
import AppKit

/// Full-panel overlay that shows a large preview of the selected entry. Triggered
/// by ⌘Y and dismissed by ⌘Y / Esc. Up/Down in the underlying browse mode still
/// move the selection, so the overlay live-updates as the user navigates.
struct QuickLookView: View {
    let entry: ClipEntry?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(24)
            .shadow(radius: 20)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let size = sizeString {
                Text(size)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("⌘Y or Esc to close")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var title: String {
        guard let entry else { return "Preview" }
        if let name = entry.source?.name {
            return "From \(name)"
        }
        return "Preview"
    }

    /// Shown top-right: character count for text, dimensions for image, file count.
    private var sizeString: String? {
        guard let entry else { return nil }
        switch entry.kind {
        case .text(let s):
            return "\(s.count) chars · \(s.components(separatedBy: "\n").count) lines"
        case .rtf(_, let plain):
            return "\(plain.count) chars"
        case .image(_, let w, let h, _):
            return "\(w) × \(h)"
        case .fileURLs(let urls):
            return "\(urls.count) file\(urls.count == 1 ? "" : "s")"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let entry {
            switch entry.kind {
            case .text(let s):
                textView(s, entryID: entry.id)
            case .rtf(_, let plain):
                textView(plain, entryID: entry.id)
            case .image(let path, _, _, _):
                imageView(path)
            case .fileURLs(let urls):
                fileView(urls)
            }
        } else {
            Text("Nothing to preview")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func textView(_ s: String, entryID: Int64) -> some View {
        // If the payload parses as structured data, default the Quick Look
        // overlay to a collapsible tree — much easier to skim than flat
        // JSON. Plain / non-structured text still gets the highlighted
        // flat preview.
        if let tree = structuredTree(for: s, entryID: entryID) {
            TreeView(root: tree)
        } else {
            ScrollView {
                CodeHighlighter.styledText(s, entryID: entryID)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }

    /// Return a parsed tree for JSON / YAML payloads; nil otherwise. We
    /// lean on `LanguageDetector` to pick the format so the heuristics
    /// stay in one place.
    private func structuredTree(for text: String, entryID: Int64) -> TreeNode? {
        switch LanguageDetector.detect(text, cacheKey: "ql-\(entryID)") {
        case .json: return StructuredTreeBuilder.fromJSON(text)
        case .yaml: return StructuredTreeBuilder.fromYAML(text)
        default:    return nil
        }
    }

    private func imageView(_ url: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            } else {
                Text("Image unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fileView(_ urls: [URL]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(urls, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(url.path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}
