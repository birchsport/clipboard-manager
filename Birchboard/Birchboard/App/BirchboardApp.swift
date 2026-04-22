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
                activateAndRaiseSettingsWindow()
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

    /// Activate the app and explicitly raise the Settings window. In macOS
    /// 14+ from a MenuBarExtra, `SettingsLink` + `NSApp.activate` can leave
    /// the window ordered behind other apps' windows — the user sees nothing
    /// happen. We schedule one runloop tick later (so the window has been
    /// created) and then `makeKeyAndOrderFront` on every non-panel window.
    /// The clipboard panel is an NSPanel, so skipping `NSPanel` instances
    /// leaves the Settings window as the only candidate.
    private func activateAndRaiseSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows
                where !(window is NSPanel)
                    && window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
