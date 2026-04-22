import Foundation

// MARK: - JSON

struct PrettyJSONTransform: TextTransform {
    let id = "json.pretty"
    let displayName = "Pretty JSON"

    func isApplicable(to text: String) -> Bool {
        parse(text) != nil
    }

    func apply(to text: String) -> String? {
        guard let obj = parse(text) else { return nil }
        let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private func parse(_ s: String) -> Any? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

struct MinifyJSONTransform: TextTransform {
    let id = "json.minify"
    let displayName = "Minify JSON"

    func isApplicable(to text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    func apply(to text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.withoutEscapingSlashes]
              )
        else { return nil }
        return String(data: out, encoding: .utf8)
    }
}

// MARK: - JWT

struct DecodeJWTTransform: TextTransform {
    let id = "jwt.decode"
    let displayName = "Decode JWT"

    /// `header.payload.signature`, each a base64url-encoded segment.
    private static let shape = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#,
        options: []
    )

    func isApplicable(to text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(t.startIndex..., in: t)
        guard Self.shape.firstMatch(in: t, range: range) != nil else { return false }
        // Structural match isn't enough — lots of three-dotted base64 tokens
        // aren't JWTs. Require the header to decode to JSON with a plausible
        // shape (a `typ` or `alg` field is the convention).
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let header = Self.decodeJSON(String(parts[0])) as? [String: Any] else {
            return false
        }
        return header["typ"] != nil || header["alg"] != nil
    }

    func apply(to text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        guard let header = Self.decodeJSON(String(parts[0])),
              let payload = Self.decodeJSON(String(parts[1])),
              let headerJSON = Self.prettyJSON(header),
              let payloadJSON = Self.prettyJSON(payload) else {
            return nil
        }

        // Signature is opaque bytes — not worth stringifying. Surface it as
        // "<N bytes>" so the reader can see it exists without noise.
        let sigBytes = Self.base64URLDecode(String(parts[2]))?.count ?? 0

        return """
        // header
        \(headerJSON)

        // payload
        \(payloadJSON)

        // signature: \(sigBytes) bytes
        """
    }

    // MARK: - Helpers

    private static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }

    private static func decodeJSON(_ segment: String) -> Any? {
        guard let data = base64URLDecode(segment) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func prettyJSON(_ obj: Any) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Base64

struct Base64EncodeTransform: TextTransform {
    let id = "base64.encode"
    let displayName = "Base64 encode"

    func apply(to text: String) -> String? {
        text.data(using: .utf8)?.base64EncodedString()
    }
}

struct Base64DecodeTransform: TextTransform {
    let id = "base64.decode"
    let displayName = "Base64 decode"

    func isApplicable(to text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        // Cheap sanity: alphabet + length multiple of 4 after padding.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        return t.unicodeScalars.allSatisfy(allowed.contains)
    }

    func apply(to text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept both standard and URL-safe base64.
        var padded = t.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

// MARK: - URL encoding

struct URLEncodeTransform: TextTransform {
    let id = "url.encode"
    let displayName = "URL encode"

    /// RFC 3986 unreserved set. Everything else is percent-encoded — including
    /// `&`, `=`, `+`, `?`, `/`, space. Matches `encodeURIComponent` behaviour.
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    func apply(to text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: Self.allowed)
    }
}

struct URLDecodeTransform: TextTransform {
    let id = "url.decode"
    let displayName = "URL decode"

    func isApplicable(to text: String) -> Bool {
        text.contains("%") && text.removingPercentEncoding != nil
    }

    func apply(to text: String) -> String? {
        text.removingPercentEncoding
    }
}

// MARK: - Case

struct UpperCaseTransform: TextTransform {
    let id = "case.upper"
    let displayName = "UPPERCASE"
    func apply(to text: String) -> String? { text.uppercased() }
}

struct LowerCaseTransform: TextTransform {
    let id = "case.lower"
    let displayName = "lowercase"
    func apply(to text: String) -> String? { text.lowercased() }
}

struct TitleCaseTransform: TextTransform {
    let id = "case.title"
    let displayName = "Title Case"
    func apply(to text: String) -> String? { text.capitalized }
}

struct CamelCaseTransform: TextTransform {
    let id = "case.camel"
    let displayName = "camelCase"

    func apply(to text: String) -> String? {
        let parts = tokens(from: text)
        guard let first = parts.first else { return nil }
        let rest = parts.dropFirst().map { $0.capitalized }
        return ([first.lowercased()] + rest).joined()
    }
}

struct SnakeCaseTransform: TextTransform {
    let id = "case.snake"
    let displayName = "snake_case"

    func apply(to text: String) -> String? {
        let parts = tokens(from: text)
        guard !parts.isEmpty else { return nil }
        return parts.map { $0.lowercased() }.joined(separator: "_")
    }
}

struct KebabCaseTransform: TextTransform {
    let id = "case.kebab"
    let displayName = "kebab-case"

    func apply(to text: String) -> String? {
        let parts = tokens(from: text)
        guard !parts.isEmpty else { return nil }
        return parts.map { $0.lowercased() }.joined(separator: "-")
    }
}

/// Split identifier-ish text into words. Handles space/underscore/hyphen/dot
/// separators plus camelCase transitions.
private func tokens(from text: String) -> [String] {
    var out: [String] = []
    var current = ""
    let boundary: Set<Character> = [" ", "_", "-", ".", "/", "\t", "\n"]

    func flush() {
        if !current.isEmpty { out.append(current); current = "" }
    }

    var prev: Character?
    for ch in text {
        if boundary.contains(ch) {
            flush()
        } else if let p = prev, p.isLowercase, ch.isUppercase {
            flush()
            current.append(ch)
        } else if let p = prev, p.isLetter, ch.isNumber {
            flush()
            current.append(ch)
        } else if let p = prev, p.isNumber, ch.isLetter {
            flush()
            current.append(ch)
        } else {
            current.append(ch)
        }
        prev = ch
    }
    flush()
    return out.filter { !$0.isEmpty }
}

// MARK: - Stripping

struct StripANSITransform: TextTransform {
    let id = "strip.ansi"
    let displayName = "Strip ANSI escape codes"

    private static let regex = try! NSRegularExpression(
        pattern: "\u{001B}\\[[0-9;]*[A-Za-z]",
        options: []
    )

    func isApplicable(to text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return Self.regex.firstMatch(in: text, options: [], range: range) != nil
    }

    func apply(to text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        return Self.regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: ""
        )
    }
}

struct StripHTMLTransform: TextTransform {
    let id = "strip.html"
    let displayName = "Strip HTML"

    private static let regex = try! NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )

    func isApplicable(to text: String) -> Bool {
        text.contains("<") && text.contains(">")
    }

    func apply(to text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        let noTags = Self.regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: ""
        )
        // Collapse the entity noise we're most likely to hit.
        return noTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
    }
}

// MARK: - Extraction

struct ExtractURLsTransform: TextTransform {
    let id = "extract.urls"
    let displayName = "Extract URLs"

    private static let detector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    func isApplicable(to text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return Self.detector.firstMatch(in: text, options: [], range: range) != nil
    }

    func apply(to text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        var urls: [String] = []
        Self.detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let url = match?.url?.absoluteString {
                urls.append(url)
            }
        }
        return urls.isEmpty ? nil : urls.joined(separator: "\n")
    }
}

struct ExtractEmailsTransform: TextTransform {
    let id = "extract.emails"
    let displayName = "Extract email addresses"

    // Loose but practical. Not RFC 5322 — nothing is.
    private static let regex = try! NSRegularExpression(
        pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
        options: []
    )

    func isApplicable(to text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return Self.regex.firstMatch(in: text, options: [], range: range) != nil
    }

    func apply(to text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        var emails: [String] = []
        Self.regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let r = match?.range, let swiftRange = Range(r, in: text) {
                emails.append(String(text[swiftRange]))
            }
        }
        // De-dup while preserving order.
        var seen = Set<String>()
        let unique = emails.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: "\n")
    }
}
