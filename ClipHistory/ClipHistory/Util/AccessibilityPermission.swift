import AppKit
import ApplicationServices

/// Accessibility access is required so we can post `⌘V` via `CGEvent.post` after
/// restoring focus to the previous app. We never call the system prompt
/// (`AXIsProcessTrustedWithOptions` with `prompt: true`) on launch, because dev
/// builds whose ad-hoc signature changes between rebuilds can end up prompting
/// the user every single time even when they've already granted access.
/// Instead we check quietly and surface our own alert at the moment we need it.
enum AccessibilityPermission {
    /// Does NOT prompt — a pure, quiet check.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Deep link to the Accessibility pane in System Settings.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Shows our own alert when we detect we can't paste. The native system prompt
    /// is flaky for unsigned apps; a custom alert with a direct link to Settings
    /// is more reliable.
    @MainActor
    static func showMissingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility access needed"
        alert.informativeText = """
            ClipHistory needs Accessibility access to paste into the previously focused app.

            Open System Settings → Privacy & Security → Accessibility, and enable ClipHistory.

            If ClipHistory is already in the list, toggle it off and back on — ad-hoc-signed dev builds can drift out of sync with macOS's permissions database between rebuilds.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
        }
    }
}
