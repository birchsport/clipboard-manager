import Foundation

/// The set of source languages we detect and expose as row chips / syntax
/// highlighter hints. Kept small on purpose — adding a case means handling
/// it in both detection (below) and highlighting (`SyntaxHighlighter`).
enum DetectedLanguage: String, Hashable, CaseIterable {
    case json
    case yaml
    case xml
    case html
    case markdown
    case swift
    case javascript
    case typescript
    case python
    case java
    case go
    case sql
    case shell
    case dockerfile
    case css
    case ruby
    case rust

    /// Short uppercase label shown in the row chip.
    var chipLabel: String {
        switch self {
        case .json:       return "JSON"
        case .yaml:       return "YAML"
        case .xml:        return "XML"
        case .html:       return "HTML"
        case .markdown:   return "MD"
        case .swift:      return "Swift"
        case .javascript: return "JS"
        case .typescript: return "TS"
        case .python:     return "Python"
        case .java:       return "Java"
        case .go:         return "Go"
        case .sql:        return "SQL"
        case .shell:      return "Shell"
        case .dockerfile: return "Docker"
        case .css:        return "CSS"
        case .ruby:       return "Ruby"
        case .rust:       return "Rust"
        }
    }
}

/// Heuristic language sniffer. Intentionally fast and tolerant: uses
/// signature tokens and `JSONSerialization` / `YAMLDecoder`-free checks so
/// it can run on every visible row without hitting the main thread. Wrong
/// answers are OK — the fallback is no chip and plain monospaced preview.
enum LanguageDetector {
    /// Minimum length to bother detecting; short strings give too many
    /// false positives (e.g. "foo: bar" looks YAML-ish).
    private static let minLength = 16

    /// Thread-safe LRU cache. Detection is cheap but pattern compilation
    /// isn't free; caching by the entry's content hash avoids re-running
    /// the checks when the same entry scrolls in and out of view.
    private static let cache = Cache()

    static func detect(_ text: String, cacheKey: String? = nil) -> DetectedLanguage? {
        if let cacheKey, let hit = cache.get(cacheKey) { return hit.value }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return nil }

        let result = detectInner(trimmed)
        if let cacheKey { cache.put(cacheKey, value: result) }
        return result
    }

    private static func detectInner(_ text: String) -> DetectedLanguage? {
        // Order matters — more specific signatures first. Java is checked
        // ahead of JS/TS/Python because it shares the `class` and `import`
        // keywords but has its own higher-confidence tells (`public class`,
        // `System.out.println`, `package com.foo;`).
        if looksLikeJSON(text)       { return .json }
        if looksLikeDockerfile(text) { return .dockerfile }
        if looksLikeHTML(text)       { return .html }
        if looksLikeXML(text)        { return .xml }
        if looksLikeMarkdown(text)   { return .markdown }
        if looksLikeSwift(text)      { return .swift }
        if looksLikeJava(text)       { return .java }
        if looksLikeTypeScript(text) { return .typescript }
        if looksLikeJavaScript(text) { return .javascript }
        if looksLikePython(text)     { return .python }
        if looksLikeGo(text)         { return .go }
        if looksLikeRust(text)       { return .rust }
        if looksLikeRuby(text)       { return .ruby }
        if looksLikeSQL(text)        { return .sql }
        if looksLikeShell(text)      { return .shell }
        if looksLikeCSS(text)        { return .css }
        if looksLikeYAML(text)       { return .yaml }
        return nil
    }

    // MARK: - Structural formats

    private static func looksLikeJSON(_ s: String) -> Bool {
        guard let first = s.first, first == "{" || first == "[" else { return false }
        guard let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    private static func looksLikeYAML(_ s: String) -> Bool {
        // YAML is slippery — lots of plain text parses as valid YAML. Require
        // at least one structural marker: `key:` at line start, `- item` at
        // line start, or a `---` document separator.
        let lines = s.split(separator: "\n")
        guard lines.count >= 2 else { return false }
        let colonLine = #"^[A-Za-z_][\w-]*\s*:\s"#
        let listLine  = #"^\s*-\s"#
        let anchor = #"^---\s*$"#
        let all = s.range(of: anchor, options: .regularExpression) != nil
               || lines.contains(where: { $0.range(of: colonLine, options: .regularExpression) != nil })
               || lines.contains(where: { $0.range(of: listLine, options: .regularExpression) != nil })
        return all
    }

    private static func looksLikeXML(_ s: String) -> Bool {
        s.hasPrefix("<?xml") ||
        (s.first == "<" && s.range(of: #"<[A-Za-z_][^>]*>"#, options: .regularExpression) != nil
                        && s.contains("</"))
    }

    private static func looksLikeHTML(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("<!doctype html") ||
               lower.contains("<html") ||
               (lower.contains("</") &&
                (lower.contains("<div") || lower.contains("<span") ||
                 lower.contains("<p>") || lower.contains("<body") ||
                 lower.contains("<head") || lower.contains("<script") ||
                 lower.contains("<a ") || lower.contains("<li>")))
    }

    private static func looksLikeMarkdown(_ s: String) -> Bool {
        // Need more than one markdown-ish signal to reduce false positives
        // on plain text with an occasional `#`.
        var signals = 0
        if s.range(of: #"(^|\n)#{1,6} "#, options: .regularExpression) != nil { signals += 1 }
        if s.range(of: #"```"#, options: []) != nil { signals += 1 }
        if s.range(of: #"(^|\n)(\* |- |\d+\. )"#, options: .regularExpression) != nil { signals += 1 }
        if s.range(of: #"\[[^\]]+\]\([^)]+\)"#, options: .regularExpression) != nil { signals += 1 }
        if s.range(of: #"(?:^|[^*])\*\*[^*\n]+\*\*"#, options: .regularExpression) != nil { signals += 1 }
        return signals >= 2
    }

    // MARK: - Programming languages

    private static func looksLikeSwift(_ s: String) -> Bool {
        contains(s, any: [#"\bimport Foundation\b"#, #"\bimport SwiftUI\b"#,
                          #"\bimport UIKit\b"#, #"\bimport AppKit\b"#]) ||
        containsAll(s, all: [#"\bfunc\s+\w+"#, #"\{"#], minHits: 1) &&
            contains(s, any: [#"\blet\s+\w+"#, #"\bvar\s+\w+"#, #"\b@\w+"#, #"->\s*\w+"#])
    }

    private static func looksLikeJavaScript(_ s: String) -> Bool {
        contains(s, any: [#"\bconst\s+\w+\s*="#, #"\blet\s+\w+\s*="#,
                          #"\bfunction\s+\w+"#, #"\brequire\(['\"]"#,
                          #"\bmodule\.exports"#, #"=>\s*\{"#, #"console\.log"#])
    }

    private static func looksLikeTypeScript(_ s: String) -> Bool {
        contains(s, any: [#"\binterface\s+\w+\s*\{"#, #":\s*(string|number|boolean)(\[\])?"#,
                          #"\bimport\s+.*from\s+['\"]"#, #"\benum\s+\w+\s*\{"#,
                          #"<[A-Z]\w*(,\s*[A-Z]\w*)*>"#]) &&
            contains(s, any: [#"\bconst\b"#, #"\blet\b"#, #"\bfunction\b"#, #":\s"#])
    }

    private static func looksLikePython(_ s: String) -> Bool {
        // High-confidence single signals — these are Python-specific.
        if s.hasPrefix("#!/usr/bin/env python") { return true }
        if s.contains("if __name__") { return true }
        if s.range(of: #"(?m)^from\s+\w+(\.\w+)*\s+import\b"#, options: .regularExpression) != nil {
            return true
        }

        // Lower-confidence signals: need ≥2 to qualify. `class Foo` and
        // `import X` on their own also match Java and TS, so neither
        // counts here.
        var signals = 0
        if s.range(of: #"(?m)^def\s+\w+\("#, options: .regularExpression) != nil { signals += 1 }
        // Python `class Foo:` (trailing colon, no braces) — unlike Java.
        if s.range(of: #"(?m)^\s*class\s+\w+[^{}\n]*:\s*$"#, options: .regularExpression) != nil {
            signals += 1
        }
        // `self.` in a method, or `(self,` / `(self)` as first arg.
        if s.range(of: #"\b\(self[,\)]"#, options: .regularExpression) != nil ||
           s.range(of: #"(?m)^\s+self\."#, options: .regularExpression) != nil {
            signals += 1
        }
        // Colon-terminated control flow (Python's block syntax).
        if s.range(of: #"(?m)^\s*(if|elif|else|while|for|try|except|finally|with)\b[^{}\n]*:\s*$"#,
                   options: .regularExpression) != nil {
            signals += 1
        }
        // Triple-quoted strings.
        if s.contains(#"""""#) || s.contains("'''") { signals += 1 }

        return signals >= 2
    }

    private static func looksLikeJava(_ s: String) -> Bool {
        // High-confidence single signals.
        if s.range(of: #"\b(public|private|protected)\s+(abstract\s+|final\s+|static\s+)*class\s+\w+"#,
                   options: .regularExpression) != nil { return true }
        if s.contains("public static void main") { return true }
        if s.range(of: #"(?m)^package\s+[\w.]+;\s*$"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"(?m)^import\s+(java|javax|com|org)\.[\w.]+;\s*$"#,
                   options: .regularExpression) != nil { return true }
        if s.contains("System.out.println") || s.contains("System.err.println") { return true }

        // Medium-confidence: need ≥2 to qualify.
        var signals = 0
        if s.range(of: #"@[A-Z]\w+"#, options: .regularExpression) != nil { signals += 1 }
        if s.range(of: #"\b(extends|implements)\s+[A-Z]\w*"#, options: .regularExpression) != nil { signals += 1 }
        // A declaration like `public static ReturnType name(` is very Java-ish.
        if s.range(of: #"(?m)^\s*(public|private|protected)\s+(static\s+|final\s+)*\w[\w<>\[\]]*\s+\w+\s*\("#,
                   options: .regularExpression) != nil { signals += 1 }
        if s.contains("String[] args") || s.contains("throws Exception") { signals += 1 }
        // Semicolon-terminated lines are a strong Java (and Java-family) hint —
        // Python doesn't use them.
        if s.range(of: #";\s*\n"#, options: .regularExpression) != nil &&
           s.range(of: #"\b(new|void|int|long|double|float|boolean|byte|char|short)\b"#,
                   options: .regularExpression) != nil {
            signals += 1
        }

        return signals >= 2
    }

    private static func looksLikeGo(_ s: String) -> Bool {
        contains(s, any: [#"(?m)^package\s+\w+"#, #"(?m)^import\s+\("#,
                          #"\bfunc\s+\w+\s*\("#, #":=\s"#,
                          #"\bfmt\.(Print|Sprint|Errorf)"#])
    }

    private static func looksLikeRust(_ s: String) -> Bool {
        contains(s, any: [#"\bfn\s+\w+\s*\("#, #"\blet\s+mut\s"#,
                          #"\bimpl\s+\w+"#, #"\buse\s+\w+::"#,
                          #"\bstruct\s+\w+\s*\{"#, #"\benum\s+\w+\s*\{"#,
                          #"println!\("#])
    }

    private static func looksLikeRuby(_ s: String) -> Bool {
        s.hasPrefix("#!/usr/bin/env ruby") ||
        contains(s, any: [#"(?m)^\s*def\s+\w+"#, #"\bend\s*$"#,
                          #"\brequire\s+['\"]"#, #"(?m)^class\s+\w+\s*<"#,
                          #"\bputs\s+"#, #"@@?\w+"#])
    }

    private static func looksLikeSQL(_ s: String) -> Bool {
        let upper = s.uppercased()
        let hits = ["SELECT ", "INSERT INTO", "UPDATE ", "DELETE FROM",
                    "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "WITH ",
                    "JOIN ", "WHERE ", "GROUP BY", "ORDER BY"]
        let count = hits.reduce(0) { $0 + (upper.contains($1) ? 1 : 0) }
        return count >= 2 || (count == 1 && upper.contains("FROM"))
    }

    private static func looksLikeShell(_ s: String) -> Bool {
        s.hasPrefix("#!/bin/bash") || s.hasPrefix("#!/bin/sh") ||
        s.hasPrefix("#!/usr/bin/env bash") || s.hasPrefix("#!/usr/bin/env sh") ||
        contains(s, any: [#"(?m)^\s*export\s+\w+="#, #"(?m)^\s*if\s+\[\[?"#,
                          #"\$\(\w+"#, #"\becho\s+"#, #"\bsudo\s+"#])
    }

    private static func looksLikeDockerfile(_ s: String) -> Bool {
        // Directives anchored to line start, case-insensitive.
        let directives = [#"(?mi)^FROM\s+\S+"#, #"(?mi)^RUN\s+"#,
                          #"(?mi)^COPY\s+"#, #"(?mi)^WORKDIR\s+"#,
                          #"(?mi)^ENTRYPOINT\s+"#, #"(?mi)^CMD\s+"#,
                          #"(?mi)^EXPOSE\s+\d+"#]
        let hits = directives.reduce(0) {
            $0 + (s.range(of: $1, options: .regularExpression) != nil ? 1 : 0)
        }
        return hits >= 2
    }

    private static func looksLikeCSS(_ s: String) -> Bool {
        s.range(of: #"[.#]?[A-Za-z_-][\w-]*\s*\{[^}]*:[^}]*;[^}]*\}"#,
                options: .regularExpression) != nil
    }

    // MARK: - Matcher helpers

    private static func contains(_ text: String, any patterns: [String]) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func containsAll(_ text: String, all patterns: [String], minHits: Int) -> Bool {
        let hits = patterns.reduce(0) {
            $0 + (text.range(of: $1, options: .regularExpression) != nil ? 1 : 0)
        }
        return hits >= minHits
    }
}

/// Tiny thread-safe LRU. Keeps ~256 recent detections.
private final class Cache: @unchecked Sendable {
    struct Entry { let value: DetectedLanguage?; let inserted: Date }
    private var store: [String: Entry] = [:]
    private let lock = NSLock()
    private let capacity = 256

    func get(_ key: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }

    func put(_ key: String, value: DetectedLanguage?) {
        lock.lock(); defer { lock.unlock() }
        store[key] = Entry(value: value, inserted: Date())
        if store.count > capacity {
            // Simple oldest-first eviction — not true LRU but cheap.
            let oldest = store.min { $0.value.inserted < $1.value.inserted }
            if let k = oldest?.key { store.removeValue(forKey: k) }
        }
    }
}
