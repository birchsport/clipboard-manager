import AppKit

/// A type-aware action the user can run against the currently-selected entry
/// from the panel's action picker (`⌘K`). Unlike transforms (which always
/// produce a pasted string), actions can be side-effecting — opening a URL,
/// revealing a file, composing an email — so each conforms drives its own
/// behaviour through an `ActionContext` rather than returning a value.
protocol EntryAction {
    /// Stable, namespaced identifier (e.g., `"url.open"`). Used for logs.
    var id: String { get }

    /// Human-facing label in the picker. Keep terse.
    var displayName: String { get }

    /// SF Symbol name rendered next to the label.
    var systemImage: String { get }

    /// Does this action make sense for `entry`? Inapplicable actions are
    /// filtered out of the picker upfront.
    func isApplicable(to entry: ClipEntry) -> Bool

    /// Run the action. Expected to dismiss the panel via `context.dismiss()`
    /// or `context.paste(_:)` before returning.
    @MainActor
    func perform(entry: ClipEntry, context: ActionContext)
}

/// Passed to each action's `perform` so it can paste, dismiss, or both without
/// having to know about `PanelActions` / `PanelController`. Keeps actions
/// honest and testable.
@MainActor
struct ActionContext {
    /// Replace the pasteboard with `text` and fire the normal paste flow
    /// (activate previous app, ⌘V). Dismisses the panel as a side effect.
    let paste: (String) -> Void

    /// Close the panel without writing to the pasteboard or pasting.
    let dismiss: () -> Void
}
