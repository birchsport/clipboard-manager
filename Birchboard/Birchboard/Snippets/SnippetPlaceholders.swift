import Foundation

/// Expands `{clipboard}`, `{date[:FMT]}`, `{time[:FMT]}`, `{uuid}`, `{newline}`,
/// `{tab}` tokens in a snippet body. Unknown tokens pass through unchanged so
/// users aren't punished for typos. `{{` and `}}` escape to literal braces.
enum SnippetPlaceholders {
    /// Replace every recognised `{token}` in `body`. `clipboard` is the text
    /// currently on the general pasteboard (if any) — read by the caller before
    /// we write the expanded snippet.
    static func expand(_ body: String, clipboard: String?) -> String {
        // Handle escapes first so `{{` and `}}` survive the token scan. We use
        // a placeholder unlikely to occur in user content.
        let bracedOpen = "\u{F000}"
        let bracedClose = "\u{F001}"
        var working = body
            .replacingOccurrences(of: "{{", with: bracedOpen)
            .replacingOccurrences(of: "}}", with: bracedClose)

        let pattern = #"\{([^{}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return working
        }

        // Iterate right-to-left so replacing earlier tokens doesn't shift the
        // ranges of later ones.
        let range = NSRange(working.startIndex..., in: working)
        let matches = regex.matches(in: working, range: range)
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: working),
                  let tokenRange = Range(match.range(at: 1), in: working) else {
                continue
            }
            let token = String(working[tokenRange])
            if let replacement = resolve(token: token, clipboard: clipboard) {
                working.replaceSubrange(fullRange, with: replacement)
            }
            // If `resolve` returns nil the token is unknown — leave it literal.
        }

        return working
            .replacingOccurrences(of: bracedOpen, with: "{")
            .replacingOccurrences(of: bracedClose, with: "}")
    }

    /// Returns the expansion for a token, or nil if it's not one we recognise.
    private static func resolve(token: String, clipboard: String?) -> String? {
        // Split "name:argument" (only the first colon counts so the argument
        // itself may contain colons — e.g. `date:HH:mm`).
        let parts = token.split(separator: ":", maxSplits: 1,
                                omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let arg = parts.count > 1 ? String(parts[1]) : nil

        switch name {
        case "clipboard":
            return clipboard ?? ""
        case "date":
            return formatDate(Date(), format: arg ?? "yyyy-MM-dd")
        case "time":
            return formatDate(Date(), format: arg ?? "HH:mm:ss")
        case "uuid":
            return UUID().uuidString
        case "newline":
            return "\n"
        case "tab":
            return "\t"
        default:
            return nil
        }
    }

    private static func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
