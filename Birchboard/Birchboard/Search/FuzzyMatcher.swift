import Foundation

/// fzf-style matcher. Two paths:
///   1. **Substring fast path** — a contiguous case-insensitive match scores highest,
///      with extra bonuses for prefix / word-boundary starts.
///   2. **Subsequence path** — every query char must appear in order, with bonuses
///      for consecutive matches, word boundaries, camelCase transitions; gap penalty
///      and a density threshold reject matches whose characters are spread too
///      thinly across the candidate (which is what makes naive subsequence matchers
///      feel noisy).
enum FuzzyMatcher {
    private static let wordBoundaries: Set<Character> = [
        " ", "/", "-", "_", ".", ":", "\\", "\n", "\t", "(", ")", "[", "]", ",", ";", "@",
    ]

    /// Match `query` against `candidate`. Returns `nil` when no acceptable match.
    static func score(query: String, candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let cOrig = Array(candidate)
        let q = Array(query.lowercased())
        guard q.count <= cOrig.count else { return nil }
        // Character.lowercased() returns a String; take the first grapheme to keep
        // a 1:1 positional mapping with `cOrig`. Safe for our clipboard corpus.
        let cLow: [Character] = cOrig.map { $0.lowercased().first ?? $0 }

        // --- Substring fast path -------------------------------------------------
        if let start = findSubstring(needle: q, haystack: cLow) {
            var s = 2000 + q.count * 20
            if start == 0 {
                s += 500 // prefix match
            } else if wordBoundaries.contains(cLow[start - 1]) {
                s += 300 // word-boundary match
            }
            s -= start // earlier matches score higher
            return s
        }

        // --- Subsequence path ----------------------------------------------------
        var i = 0
        var score = 0
        var prevMatched = -2
        var firstMatched = -1

        for j in 0..<cLow.count {
            if i >= q.count { break }
            guard q[i] == cLow[j] else { continue }

            if firstMatched == -1 { firstMatched = j }

            var contribution = 1
            if j == prevMatched + 1 { contribution += 3 } // consecutive
            if j == 0 || wordBoundaries.contains(cLow[j - 1]) { contribution += 5 } // word boundary
            if j > 0, cOrig[j].isUppercase, cOrig[j - 1].isLowercase { contribution += 3 } // camelCase

            score += contribution
            prevMatched = j
            i += 1
        }

        guard i == q.count else { return nil }

        // --- Gap / density filtering --------------------------------------------
        let span = prevMatched - firstMatched + 1   // chars from first matched to last
        // Density threshold: the matched chars must make up a reasonable fraction of
        // the matched span. Very loose for 1-char queries, tighter as query grows.
        switch q.count {
        case 1:
            break // anything goes
        case 2:
            if span > 20 { return nil }
        case 3:
            if span > q.count * 8 { return nil }
        default:
            if span > q.count * 5 { return nil }
        }

        // Gap penalty proportional to empty space between first and last match.
        score -= (span - q.count)

        // Minimum score floor — weak spread-out matches don't clear the bar.
        if q.count >= 3, score < q.count * 2 { return nil }

        return score
    }

    private static func findSubstring(needle: [Character], haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count, !needle.isEmpty else { return nil }
        let last = haystack.count - needle.count
        outer: for start in 0...last {
            for k in 0..<needle.count where haystack[start + k] != needle[k] {
                continue outer
            }
            return start
        }
        return nil
    }

    /// Filters and sorts `entries` by fuzzy score against their `searchText`.
    /// Empty query returns the entries unchanged.
    static func filter(_ entries: [ClipEntry], query: String) -> [ClipEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return entries }

        let scored: [(entry: ClipEntry, score: Int, order: Int)] = entries.enumerated().compactMap { idx, entry in
            guard let s = score(query: trimmed, candidate: entry.searchText) else { return nil }
            return (entry, s, idx)
        }
        // Higher score first, then preserve original (time-sorted) order for ties.
        return scored
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.order < b.order
            }
            .map { $0.entry }
    }
}
