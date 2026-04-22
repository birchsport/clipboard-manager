import SwiftUI
import AppKit

/// App entry point. The app is a background agent (LSUIElement) with a menu-bar
/// item and a floating panel.
///
/// Opening Settings from a MenuBarExtra on macOS 14+ requires `SettingsLink` —
/// sending `showSettingsWindow:` manually is blocked with a "Please use
/// SettingsLink" runtime log. Since LSUIElement apps aren't active by default,
/// the Settings window can open *behind* other apps, making it look like
/// nothing happened. The `.simultaneousGesture` here forces `NSApp.activate`
/// at tap time so the window comes forward.
@main
struct BirchboardApp: App {
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
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
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
}
