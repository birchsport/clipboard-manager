import AppKit
import Foundation

// MARK: - Text classification helpers

/// Utilities shared by actions that need to decide whether a text payload is
/// a URL / email / hex color / phone number. "Pure" matches only: the entire
/// trimmed string must be of the expected type, not merely contain one.
private enum Classifier {
    static func trimmed(_ entry: ClipEntry) -> String? {
        let text: String
        switch entry.kind {
        case .text(let s):              text = s
        case .rtf(_, let plain):        text = plain
        case .image, .fileURLs:         return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func url(_ entry: ClipEntry) -> URL? {
        guard let s = trimmed(entry) else { return nil }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return nil }
        // Accept common schemes so "mailto:foo" etc. work; cheaper than a
        // full-scheme allow-list.
        return ["http", "https", "ftp", "file", "mailto", "ssh", "sftp"]
            .contains(scheme) ? url : nil
    }

    private static let emailRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$",
            options: []
        )
    }()

    static func email(_ entry: ClipEntry) -> String? {
        guard let s = trimmed(entry) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        return emailRegex.firstMatch(in: s, range: range) != nil ? s : nil
    }

    private static let hexColorRegex: NSRegularExpression = {
        // #RGB, #RRGGBB, #RRGGBBAA, with optional leading/trailing whitespace.
        try! NSRegularExpression(
            pattern: "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$",
            options: []
        )
    }()

    static func hexColor(_ entry: ClipEntry) -> (r: Int, g: Int, b: Int, a: Double)? {
        guard let s = trimmed(entry) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard hexColorRegex.firstMatch(in: s, range: range) != nil else { return nil }

        var hex = String(s.dropFirst())
        // Normalise #RGB → #RRGGBB.
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }

        // Parse 2-char segments.
        func segment(_ start: Int) -> Int? {
            let lo = hex.index(hex.startIndex, offsetBy: start)
            let hi = hex.index(lo, offsetBy: 2)
            return Int(hex[lo..<hi], radix: 16)
        }

        guard let r = segment(0), let g = segment(2), let b = segment(4) else {
            return nil
        }
        let a: Double = (hex.count == 8)
            ? (Double(segment(6) ?? 255) / 255.0)
            : 1.0
        return (r, g, b, a)
    }

    private static let phoneDetector: NSDataDetector = {
        try! NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    }()

    static func phone(_ entry: ClipEntry) -> String? {
        guard let s = trimmed(entry) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let match = phoneDetector.firstMatch(in: s, range: range),
              match.range == range,
              let phone = match.phoneNumber else {
            return nil
        }
        return phone
    }
}

// MARK: - URL

struct OpenURLAction: EntryAction {
    let id = "url.open"
    let displayName = "Open in Browser"
    let systemImage = "safari"

    func isApplicable(to entry: ClipEntry) -> Bool {
        Classifier.url(entry) != nil
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard let url = Classifier.url(entry) else {
            context.dismiss()
            return
        }
        NSWorkspace.shared.open(url)
        context.dismiss()
    }
}

struct CopyURLAsMarkdownAction: EntryAction {
    let id = "url.markdown"
    let displayName = "Paste as Markdown link"
    let systemImage = "link"

    func isApplicable(to entry: ClipEntry) -> Bool {
        Classifier.url(entry) != nil
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard let url = Classifier.url(entry) else {
            context.dismiss()
            return
        }
        // Title defaults to host so the snippet reads sensibly without
        // network access. Users who want the page title can fetch separately.
        let title = url.host ?? url.absoluteString
        context.paste("[\(title)](\(url.absoluteString))")
    }
}

// MARK: - File

struct RevealInFinderAction: EntryAction {
    let id = "file.reveal"
    let displayName = "Reveal in Finder"
    let systemImage = "folder"

    func isApplicable(to entry: ClipEntry) -> Bool {
        if case .fileURLs(let urls) = entry.kind, !urls.isEmpty { return true }
        return false
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard case .fileURLs(let urls) = entry.kind, !urls.isEmpty else {
            context.dismiss()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        context.dismiss()
    }
}

struct OpenFileAction: EntryAction {
    let id = "file.open"
    let displayName = "Open"
    let systemImage = "arrow.up.right.square"

    func isApplicable(to entry: ClipEntry) -> Bool {
        if case .fileURLs(let urls) = entry.kind, !urls.isEmpty { return true }
        return false
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard case .fileURLs(let urls) = entry.kind else {
            context.dismiss()
            return
        }
        for url in urls {
            NSWorkspace.shared.open(url)
        }
        context.dismiss()
    }
}

// MARK: - Email

struct ComposeEmailAction: EntryAction {
    let id = "email.compose"
    let displayName = "Compose Mail to…"
    let systemImage = "envelope"

    func isApplicable(to entry: ClipEntry) -> Bool {
        Classifier.email(entry) != nil
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard let email = Classifier.email(entry),
              let url = URL(string: "mailto:\(email)") else {
            context.dismiss()
            return
        }
        NSWorkspace.shared.open(url)
        context.dismiss()
    }
}

// MARK: - Phone

struct CallPhoneAction: EntryAction {
    let id = "phone.call"
    let displayName = "Call with FaceTime"
    let systemImage = "phone"

    func isApplicable(to entry: ClipEntry) -> Bool {
        Classifier.phone(entry) != nil
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard let phone = Classifier.phone(entry),
              let url = URL(string: "facetime://\(phone)") else {
            context.dismiss()
            return
        }
        NSWorkspace.shared.open(url)
        context.dismiss()
    }
}

// MARK: - Hex color

struct CopyHexAsRGBAction: EntryAction {
    let id = "color.rgb"
    let displayName = "Paste as rgb()"
    let systemImage = "paintpalette"

    func isApplicable(to entry: ClipEntry) -> Bool {
        Classifier.hexColor(entry) != nil
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard let c = Classifier.hexColor(entry) else {
            context.dismiss()
            return
        }
        let out: String
        if c.a < 1.0 {
            out = String(format: "rgba(%d, %d, %d, %.2f)", c.r, c.g, c.b, c.a)
        } else {
            out = "rgb(\(c.r), \(c.g), \(c.b))"
        }
        context.paste(out)
    }
}

struct CopyHexAsHSLAction: EntryAction {
    let id = "color.hsl"
    let displayName = "Paste as hsl()"
    let systemImage = "paintpalette"

    func isApplicable(to entry: ClipEntry) -> Bool {
        Classifier.hexColor(entry) != nil
    }

    @MainActor
    func perform(entry: ClipEntry, context: ActionContext) {
        guard let c = Classifier.hexColor(entry) else {
            context.dismiss()
            return
        }
        let (h, s, l) = rgbToHSL(r: c.r, g: c.g, b: c.b)
        let out: String
        if c.a < 1.0 {
            out = String(format: "hsla(%d, %d%%, %d%%, %.2f)", h, s, l, c.a)
        } else {
            out = "hsl(\(h), \(s)%, \(l)%)"
        }
        context.paste(out)
    }

    /// RGB (0–255) → HSL (h 0–359, s/l 0–100). Standard formula.
    private func rgbToHSL(r: Int, g: Int, b: Int) -> (h: Int, s: Int, l: Int) {
        let rN = Double(r) / 255.0
        let gN = Double(g) / 255.0
        let bN = Double(b) / 255.0
        let maxC = max(rN, gN, bN)
        let minC = min(rN, gN, bN)
        let l = (maxC + minC) / 2

        var h = 0.0
        var s = 0.0
        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC)
            if maxC == rN {
                h = (gN - bN) / d + (gN < bN ? 6.0 : 0.0)
            } else if maxC == gN {
                h = (bN - rN) / d + 2.0
            } else {
                h = (rN - gN) / d + 4.0
            }
            h *= 60.0
        }
        return (Int(h.rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }
}
