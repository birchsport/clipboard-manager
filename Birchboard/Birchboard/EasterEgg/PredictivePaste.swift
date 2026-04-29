import AppKit

/// Hardcoded bank of silly quotes for the Predictive Paste easter egg.
/// A mix of Chuck-Norris-style folk meme jokes (Birchboard / SWE flavoured) and
/// original silly one-liners. Extend freely; ordering is irrelevant.
enum PredictivePasteQuotes {
    static let all: [String] = [
        // Chuck-Norris-style folk format, Birchboard/SWE flavoured
        "Chuck Norris doesn't use a clipboard manager. The clipboard manager uses Chuck Norris.",
        "Chuck Norris's clipboard has only one entry, and it's correct.",
        "Chuck Norris pinned an entry. The entry was honored.",
        "Chuck Norris obfuscated his password. The password obfuscated itself out of respect.",
        "Chuck Norris doesn't paste. Things appear where he points.",
        "Chuck Norris's clipboard never overflows. Other clipboards politely retain.",

        // Programmer / SWE classics
        "My code doesn't have bugs. It develops random unintended features.",
        "I don't always test my code, but when I do, I do it in production.",
        "There are 10 kinds of people: those who understand binary and those who don't.",
        "It works on my machine. Ship my machine.",
        "Hofstadter's Law: It always takes longer than you expect, even when you take into account Hofstadter's Law.",
        "In theory there is no difference between theory and practice. In practice, there is.",
        "99 little bugs in the code, 99 little bugs. Take one down, patch it around, 117 little bugs in the code.",
        "A SQL query walks into a bar, walks up to two tables and asks: 'Mind if I join you?'",
        "To understand recursion, see: 'To understand recursion'.",
        "There are two hard things in computer science: cache invalidation, naming things, and off-by-one errors.",
        "Programming is 10% writing code and 90% staring at the code you wrote yesterday wondering what you were thinking.",
        "Real programmers count from 0.",
        "Walking on water and developing software from a specification are easy if both are frozen.",
        "My favorite design pattern is the singleton. It's a great way to introduce global state and pretend you didn't.",
        "Documentation is like a good joke. If you have to explain it, it's not very good.",
        "Premature optimization is the root of all evil. Mature optimization is the root of all consultancies.",
        "The cheapest, fastest, and most reliable components are those that aren't there.",
        "I would have written a shorter program, but I didn't have the time.",
        "Computers are useless. They can only give you answers.",
        "The best thing about a boolean is even if you are wrong, you are only off by a bit.",
        "There is no patch for human stupidity, but there is one scheduled for next sprint.",
        "My code passes all tests. I just haven't written the tests yet.",
        "git push --force is a love language.",
        "Weeks of coding can save hours of planning.",
        "Any sufficiently advanced bug is indistinguishable from a feature.",
        "The two states of every program: not yet shipped, and obsolete.",

        // Birchboard self-aware
        "The clipboard remembers what you forget. Birchboard remembers that the clipboard remembers.",
        "Have you tried turning the clipboard off and on again?",
        "This quote was randomly selected from a hardcoded array.",
        "Predictive Paste predicted you'd press that hotkey. (It was a guess.)",
    ]

    static func random() -> String {
        all.randomElement() ?? "(silence)"
    }
}

/// Predictive Paste — a silly easter egg that pastes a random quote into the
/// frontmost app when the user's configured hotkey fires. No panel, no history
/// pollution. Reuses the same low-level helpers as the normal paste flow.
@MainActor
enum PredictivePaste {
    /// Capture the frontmost app, write a random quote to the pasteboard, then
    /// post ⌘V. The clipboard write is marked self-produced so
    /// `ClipboardWatcher` does not ingest the quote into history.
    static func fire(preferences: Preferences) {
        let target = NSWorkspace.shared.frontmostApplication

        let snapshot = preferences.restoreClipboardAfterPaste
            ? ClipboardWriter.snapshot()
            : nil

        let quote = PredictivePasteQuotes.random()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(quote, forType: .string)
        ClipboardWatcher.markSelfProduced(changeCount: pb.changeCount)

        target?.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ClipboardWriter.synthesizeCmdV()
        }

        if let snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                ClipboardWriter.restore(snapshot)
            }
        }
    }
}
