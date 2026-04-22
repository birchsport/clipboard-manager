import SwiftUI
import AppKit

/// App entry point. The app is a background agent (LSUIElement) with a menu-bar
/// item and a floating panel.
///
/// Note on opening Settings: `SettingsLink` *should* be the idiomatic way but
/// it's unreliable inside `MenuBarExtra` for LSUIElement apps — the window
/// either doesn't appear or opens behind other apps. Every menu-bar clipboard
/// manager I've looked at (Maccy, Rectangle, etc.) uses the manual
/// `NSApp.activate` + `showSettingsWindow:` pair instead, so we do too.
@main
struct BirchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Show Clipboard") {
                appDelegate.togglePanel()
            }
            Divider()
            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit Birchboard") {
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

    /// Bring the app forward (LSUIElement apps aren't active by default) and
    /// tell AppKit to show the Settings scene. Using the selector form is
    /// required — `showSettingsWindow:` isn't exposed as a Swift-visible API.
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
