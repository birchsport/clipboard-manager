import Foundation
import SwiftUI
import Splash

/// Produces an `AttributedString` with token colours applied for the given
/// source language. Swift goes through Splash (best-in-class coverage);
/// other languages use a small regex-rule-based tokeniser that's good
/// enough for the clipboard-preview use case — keywords, strings, numbers,
/// comments, and structural punctuation.
///
/// Namespaced `CodeHighlighter` to avoid colliding with Splash's
/// `SyntaxHighlighter` type.
enum CodeHighlighter {

    /// Palette tuned to look decent against the panel's thick-material
    /// background without being garish. Keep these in sync across rule
    /// sets below.
    enum Palette {
        static let keyword = SwiftUI.Color(red: 0.80, green: 0.40, blue: 0.60)   // pink
        static let string  = SwiftUI.Color(red: 0.55, green: 0.70, blue: 0.30)   // olive
        static let number  = SwiftUI.Color(red: 0.75, green: 0.50, blue: 0.20)   // amber
        static let comment = SwiftUI.Color(red: 0.55, green: 0.55, blue: 0.55)   // grey
        static let type    = SwiftUI.Color(red: 0.35, green: 0.60, blue: 0.80)   // blue
        static let key     = SwiftUI.Color(red: 0.35, green: 0.60, blue: 0.80)   // blue (json/yaml keys)
        static let literal = SwiftUI.Color(red: 0.45, green: 0.35, blue: 0.70)   // purple (true/false/null)
    }

    static func highlight(_ text: String, as language: DetectedLanguage) -> AttributedString {
        if language == .swift {
            return highlightSwift(text)
        }
        return highlightGeneric(text, rules: rules(for: language))
    }

    /// Convenience for call sites that render a preview `Text` view. Runs
    /// detection, highlights if we recognise the language, and returns a
    /// monospaced `Text`. Falls back to plain monospaced for unknown
    /// content.
    static func styledText(_ text: String, entryID: Int64, fontSize: CGFloat = 13) -> Text {
        if let language = LanguageDetector.detect(text, cacheKey: "preview-\(entryID)") {
            return Text(highlight(text, as: language))
                .font(.system(size: fontSize, design: .monospaced))
        }
        return Text(text)
            .font(.system(size: fontSize, design: .monospaced))
    }

    // MARK: - Swift via Splash

    private static let swiftHighlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: splashTheme))

    private static var splashTheme: Theme {
        Theme(
            font: Splash.Font(size: 13),
            plainTextColor: .labelColor,
            tokenColors: [
                .keyword:      nsColor(Palette.keyword),
                .string:       nsColor(Palette.string),
                .type:         nsColor(Palette.type),
                .call:         nsColor(Palette.type),
                .number:       nsColor(Palette.number),
                .comment:      nsColor(Palette.comment),
                .property:     .labelColor,
                .dotAccess:    .labelColor,
                .preprocessing: nsColor(Palette.keyword),
            ],
            backgroundColor: .clear
        )
    }

    private static func highlightSwift(_ text: String) -> AttributedString {
        let ns = swiftHighlighter.highlight(text)
        return AttributedString(ns)
    }

    // MARK: - Generic regex-based highlighting

    struct Rule {
        let pattern: NSRegularExpression
        let color: SwiftUI.Color
    }

    private static func highlightGeneric(_ text: String, rules: [Rule]) -> AttributedString {
        var attr = AttributedString(text)
        // Apply rules in order; later rules win on overlaps (they're last-
        // applied so their colour sticks). Usually rules are disjoint.
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for rule in rules {
            rule.pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let r = match?.range, r.location != NSNotFound else { return }
                guard let swiftRange = Range(r, in: text),
                      let attrRange = Range(swiftRange, in: attr) else { return }
                attr[attrRange].foregroundColor = rule.color
            }
        }
        return attr
    }

    // MARK: - Per-language rule sets

    private static func rules(for language: DetectedLanguage) -> [Rule] {
        switch language {
        case .json:       return jsonRules
        case .yaml:       return yamlRules
        case .xml, .html: return xmlRules
        case .javascript, .typescript: return jsRules
        case .python:     return pythonRules
        case .go:         return goRules
        case .rust:       return rustRules
        case .ruby:       return rubyRules
        case .sql:        return sqlRules
        case .shell:      return shellRules
        case .dockerfile: return dockerfileRules
        case .markdown:   return markdownRules
        case .css:        return cssRules
        case .swift:      return []  // handled by Splash
        }
    }

    // MARK: Rule definitions

    private static let jsonRules: [Rule] = [
        rule(#""[^"\\]*(?:\\.[^"\\]*)*"\s*:"#, color: Palette.key),                   // "key":
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),                    // "string"
        rule(#"\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, color: Palette.number),        // numbers
        rule(#"\b(true|false|null)\b"#, color: Palette.literal),                      // literals
    ]

    private static let yamlRules: [Rule] = [
        rule(#"(?m)^\s*#.*$"#, color: Palette.comment),                               // # comments
        rule(#"(?m)^([\s-]*)([A-Za-z_][\w-]*)\s*:"#, color: Palette.key),             // key:
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(#"'[^']*'"#, color: Palette.string),
        rule(#"\b\d+(?:\.\d+)?\b"#, color: Palette.number),
        rule(#"\b(true|false|null|yes|no|on|off)\b"#, color: Palette.literal),
    ]

    private static let xmlRules: [Rule] = [
        rule(#"<!--[\s\S]*?-->"#, color: Palette.comment),
        rule(#"<\?[^?]+\?>"#, color: Palette.comment),
        rule(#"<\/?[A-Za-z_][\w:-]*"#, color: Palette.keyword),                       // tag opens
        rule(#"\s[A-Za-z_][\w:-]*(?==)"#, color: Palette.key),                        // attribute names
        rule(#""[^"]*""#, color: Palette.string),
        rule(#"'[^']*'"#, color: Palette.string),
    ]

    private static let jsKeywords = #"\b(var|let|const|function|return|if|else|for|while|do|switch|case|break|continue|class|extends|new|this|super|import|export|from|as|default|async|await|yield|try|catch|finally|throw|typeof|instanceof|in|of|void|delete|null|undefined|true|false|interface|type|enum|public|private|protected|readonly|static)\b"#
    private static let jsRules: [Rule] = [
        rule(#"//.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#"/\*[\s\S]*?\*/"#, color: Palette.comment),
        rule(#"`[^`]*`"#, color: Palette.string),
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, color: Palette.string),
        rule(jsKeywords, color: Palette.keyword),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let pythonKeywords = #"\b(def|class|if|elif|else|for|while|return|import|from|as|with|try|except|finally|raise|yield|lambda|pass|break|continue|global|nonlocal|in|is|not|and|or|True|False|None|async|await|self)\b"#
    private static let pythonRules: [Rule] = [
        rule(#"#.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#"""([^"\\]|\\.)*""""#, color: Palette.string),                          // """..."""
        rule(#""[^"\\\n]*(?:\\.[^"\\\n]*)*""#, color: Palette.string),
        rule(#"'[^'\\\n]*(?:\\.[^'\\\n]*)*'"#, color: Palette.string),
        rule(pythonKeywords, color: Palette.keyword),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let goKeywords = #"\b(package|import|func|return|if|else|for|range|switch|case|default|break|continue|go|defer|chan|select|type|struct|interface|map|var|const|nil|true|false)\b"#
    private static let goRules: [Rule] = [
        rule(#"//.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#"/\*[\s\S]*?\*/"#, color: Palette.comment),
        rule(#"`[^`]*`"#, color: Palette.string),
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(goKeywords, color: Palette.keyword),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let rustKeywords = #"\b(fn|let|mut|pub|use|mod|crate|self|Self|struct|enum|impl|trait|for|while|loop|if|else|match|return|break|continue|in|ref|move|async|await|dyn|as|where|type|const|static|unsafe|true|false|Some|None|Ok|Err)\b"#
    private static let rustRules: [Rule] = [
        rule(#"//.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#"/\*[\s\S]*?\*/"#, color: Palette.comment),
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(rustKeywords, color: Palette.keyword),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let rubyKeywords = #"\b(def|end|class|module|if|elsif|else|unless|case|when|while|until|do|return|yield|begin|rescue|ensure|raise|nil|true|false|self|require|require_relative|include|extend|attr_reader|attr_writer|attr_accessor)\b"#
    private static let rubyRules: [Rule] = [
        rule(#"#.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, color: Palette.string),
        rule(#":\w+"#, color: Palette.literal),                                       // :symbol
        rule(rubyKeywords, color: Palette.keyword),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let sqlKeywords = #"(?i)\b(SELECT|FROM|WHERE|AND|OR|NOT|NULL|IS|IN|LIKE|BETWEEN|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|JOIN|LEFT|RIGHT|INNER|OUTER|FULL|ON|AS|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|UNION|ALL|WITH|DISTINCT|CASE|WHEN|THEN|ELSE|END|CAST|RETURNING)\b"#
    private static let sqlRules: [Rule] = [
        rule(#"--.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#"/\*[\s\S]*?\*/"#, color: Palette.comment),
        rule(#"'[^'\\]*(?:\\.[^'\\]*)*'"#, color: Palette.string),
        rule(sqlKeywords, color: Palette.keyword),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let shellKeywords = #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|break|continue|exit|export|readonly|local|declare|typeset|source|alias|unalias|set|unset|shift|eval|exec)\b"#
    private static let shellRules: [Rule] = [
        rule(#"#.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(#"'[^']*'"#, color: Palette.string),
        rule(#"\$\{?\w+\}?"#, color: Palette.key),
        rule(shellKeywords, color: Palette.keyword),
    ]

    private static let dockerfileDirectives = #"(?mi)^(FROM|RUN|COPY|ADD|CMD|ENTRYPOINT|ENV|EXPOSE|VOLUME|USER|WORKDIR|ARG|LABEL|SHELL|STOPSIGNAL|HEALTHCHECK|ONBUILD|MAINTAINER)\b"#
    private static let dockerfileRules: [Rule] = [
        rule(#"#.*$"#, color: Palette.comment, options: [NSRegularExpression.Options.anchorsMatchLines]),
        rule(dockerfileDirectives, color: Palette.keyword),
        rule(#""[^"\\]*(?:\\.[^"\\]*)*""#, color: Palette.string),
        rule(#"\b-?\d+(?:\.\d+)?\b"#, color: Palette.number),
    ]

    private static let markdownRules: [Rule] = [
        rule(#"(?m)^#{1,6}\s.*$"#, color: Palette.keyword),                           // headings
        rule(#"```[\s\S]*?```"#, color: Palette.string),                              // fenced code
        rule(#"`[^`\n]+`"#, color: Palette.string),                                    // inline code
        rule(#"\*\*[^*\n]+\*\*"#, color: Palette.keyword),                            // **bold**
        rule(#"\[[^\]]+\]\([^)]+\)"#, color: Palette.type),                           // links
        rule(#"(?m)^[\s]*[-*+]\s"#, color: Palette.literal),                           // list markers
    ]

    private static let cssRules: [Rule] = [
        rule(#"/\*[\s\S]*?\*/"#, color: Palette.comment),
        rule(#"[.#]?[A-Za-z_-][\w-]*(?=\s*\{)"#, color: Palette.type),                // selectors
        rule(#"\b[A-Za-z-]+(?=\s*:)"#, color: Palette.key),                            // property names
        rule(#""[^"]*""#, color: Palette.string),
        rule(#"'[^']*'"#, color: Palette.string),
        rule(#"#[0-9A-Fa-f]{3,8}\b"#, color: Palette.literal),                        // hex colours
        rule(#"\b-?\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms)?\b"#, color: Palette.number),
    ]

    // MARK: - Helpers

    private static func rule(_ pattern: String,
                             color: SwiftUI.Color,
                             options: NSRegularExpression.Options = []) -> Rule {
        // Built-ins are hand-authored and trusted; a compilation failure is
        // a programming error and would surface loudly during development.
        let re = try! NSRegularExpression(pattern: pattern, options: options)
        return Rule(pattern: re, color: color)
    }

    /// Splash's `Color` on AppKit is `NSColor`.
    private static func nsColor(_ c: SwiftUI.Color) -> NSColor {
        NSColor(c)
    }
}
