import Foundation

/// The list of actions shown in the ⌘K picker, filtered by applicability to
/// the currently-selected entry. Ordered by rough expected frequency — the
/// picker is searchable so order only matters for the no-query default view.
enum ActionRegistry {
    static let all: [any EntryAction] = [
        OpenURLAction(),
        CopyURLAsMarkdownAction(),
        RevealInFinderAction(),
        OpenFileAction(),
        ComposeEmailAction(),
        CallPhoneAction(),
        CopyHexAsRGBAction(),
        CopyHexAsHSLAction(),
    ]

    /// Actions that make sense for `entry`.
    static func applicable(to entry: ClipEntry) -> [any EntryAction] {
        all.filter { $0.isApplicable(to: entry) }
    }
}
