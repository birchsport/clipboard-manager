import SwiftUI

/// App entry point. The app is a background agent (LSUIElement) with a menu-bar item
/// and a floating panel. We use `MenuBarExtra` so `SettingsLink` — the only reliable
/// way to open the `Settings` scene on macOS 14+ — is available from the menu.
@main
struct ClipHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Show Clipboard") {
                appDelegate.togglePanel()
            }
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit ClipHistory") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "doc.on.clipboard")
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.services.preferences)
                .environmentObject(appDelegate.services.snippetStore)
        }
    }
}
