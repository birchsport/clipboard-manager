import Foundation
import CryptoKit
import Yams

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

// MARK: - JSON ↔ YAML

/// Picks direction automatically: JSON input → YAML output, YAML input →
/// JSON output. Single entry in the picker instead of two.
struct JSONYAMLTransform: TextTransform {
    let id = "json.yaml"
    let displayName = "JSON ↔ YAML"

    func isApplicable(to text: String) -> Bool {
        parsesAsJSON(text) || parsesAsYAML(text)
    }

    func apply(to text: String) -> String? {
        if parsesAsJSON(text) {
            // JSON → YAML
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return nil
            }
            // Yams can dump Any, but we round-trip through its native types to
            // keep number/bool/null distinctions. JSONSerialization's output
            // types map cleanly onto Yams.
            return try? Yams.dump(object: obj)
        } else if parsesAsYAML(text) {
            // YAML → JSON
            guard let obj = try? Yams.load(yaml: text) else { return nil }
            guard let data = try? JSONSerialization.data(
                withJSONObject: obj as Any,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func parsesAsJSON(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[" else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    private func parsesAsYAML(_ s: String) -> Bool {
        guard let obj = try? Yams.load(yaml: s) else { return false }
        // A bare string is valid YAML but not interesting to us — require a
        // structured value (dict or array) to count.
        return obj is [String: Any] || obj is [Any]
    }
}

// MARK: - Unix timestamp ↔ ISO 8601

struct UnixTimestampTransform: TextTransform {
    let id = "time.unix"
    let displayName = "Unix time ↔ ISO 8601"

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func isApplicable(to text: String) -> Bool {
        parseUnix(text) != nil || parseISO(text) != nil
    }

    func apply(to text: String) -> String? {
        if let date = parseUnix(text) {
            return Self.iso8601NoMs.string(from: date)
        }
        if let date = parseISO(text) {
            return String(Int(date.timeIntervalSince1970))
        }
        return nil
    }

    /// Accept a 10-digit second timestamp or a 13-digit millisecond timestamp.
    private func parseUnix(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.allSatisfy({ $0.isNumber }) else { return nil }
        switch t.count {
        case 10:
            guard let seconds = Double(t) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        case 13:
            guard let millis = Double(t) else { return nil }
            return Date(timeIntervalSince1970: millis / 1000)
        default:
            return nil
        }
    }

    private func parseISO(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.iso8601.date(from: t) ?? Self.iso8601NoMs.date(from: t)
    }
}

// MARK: - Hashes

private func hexDigest<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined()
}

struct SHA256Transform: TextTransform {
    let id = "hash.sha256"
    let displayName = "SHA-256"
    func apply(to text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return hexDigest(SHA256.hash(data: data))
    }
}

struct SHA1Transform: TextTransform {
    let id = "hash.sha1"
    let displayName = "SHA-1"
    func apply(to text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return hexDigest(Insecure.SHA1.hash(data: data))
    }
}

struct MD5Transform: TextTransform {
    let id = "hash.md5"
    let displayName = "MD5"
    func apply(to text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return hexDigest(Insecure.MD5.hash(data: data))
    }
}

// MARK: - Number base conversions

/// Detects an integer in decimal / hex (with `0x`) / binary (with `0b`)
/// form and converts it to the other two bases. Output format:
/// `dec: N\nhex: 0x…\nbin: 0b…`.
struct NumberBaseTransform: TextTransform {
    let id = "num.base"
    let displayName = "Number bases (dec / hex / bin)"

    func isApplicable(to text: String) -> Bool {
        parse(text) != nil
    }

    func apply(to text: String) -> String? {
        guard let n = parse(text) else { return nil }
        let dec = String(n, radix: 10)
        let hex = "0x" + String(n, radix: 16, uppercase: false)
        let bin = "0b" + String(n, radix: 2)
        return """
        dec: \(dec)
        hex: \(hex)
        bin: \(bin)
        """
    }

    private func parse(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("0x") || t.hasPrefix("0X") {
            return Int(t.dropFirst(2), radix: 16)
        }
        if t.hasPrefix("0b") || t.hasPrefix("0B") {
            return Int(t.dropFirst(2), radix: 2)
        }
        // Require the whole string to be digits (optionally leading `-`).
        let body = t.hasPrefix("-") ? String(t.dropFirst()) : t
        guard !body.isEmpty, body.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(t)
    }
}

// MARK: - Query string ↔ JSON

/// `foo=1&bar=hello%20world` ↔ pretty JSON object. Direction picked
/// automatically.
struct QueryStringJSONTransform: TextTransform {
    let id = "queryString.json"
    let displayName = "Query string ↔ JSON"

    func isApplicable(to text: String) -> Bool {
        parsesAsQuery(text) || parsesAsFlatJSON(text)
    }

    func apply(to text: String) -> String? {
        if let dict = parseQuery(text) {
            // query → JSON
            guard let data = try? JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        if let flat = parseFlatJSON(text) {
            // JSON → query
            return flat
                .sorted { $0.key < $1.key }
                .compactMap { key, value -> String? in
                    let encodedKey = key.addingPercentEncoding(
                        withAllowedCharacters: allowedQueryChars
                    ) ?? key
                    let encodedVal = value.addingPercentEncoding(
                        withAllowedCharacters: allowedQueryChars
                    ) ?? value
                    return "\(encodedKey)=\(encodedVal)"
                }
                .joined(separator: "&")
        }
        return nil
    }

    private var allowedQueryChars: CharacterSet {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }

    private func parsesAsQuery(_ s: String) -> Bool { parseQuery(s) != nil }

    private func parseQuery(_ s: String) -> [String: String]? {
        let body = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?"))
        guard body.contains("="), !body.contains("\n") else { return nil }
        var dict: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1,
                                   omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            if key.isEmpty { return nil }
            dict[key] = value
        }
        return dict.isEmpty ? nil : dict
    }

    private func parsesAsFlatJSON(_ s: String) -> Bool { parseFlatJSON(s) != nil }

    /// Only flat string-keyed, string-value JSON converts cleanly — nested
    /// values don't have a sensible query-string representation.
    private func parseFlatJSON(_ s: String) -> [String: String]? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else { return nil }
        var flat: [String: String] = [:]
        for (k, v) in dict {
            switch v {
            case let s as String: flat[k] = s
            case let n as NSNumber: flat[k] = n.stringValue
            case is NSNull: flat[k] = ""
            default: return nil
            }
        }
        return flat
    }
}
