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
            Button("Check for Updates…") {
                appDelegate.services.updater.checkForUpdates()
            }
            Button("About Birchboard") {
                showAboutPanel()
            }
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
                .environmentObject(appDelegate.services.updater)
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

    /// Show the standard macOS About panel with author / contact / tagline
    /// in the credits slot. `orderFrontStandardAboutPanel` automatically
    /// picks up `CFBundleName`, `CFBundleShortVersionString`, and
    /// `CFBundleVersion` from Info.plist; we only have to supply the
    /// credits. Email and website are NSAttributedString `.link` values so
    /// they render as clickable URLs.
    private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3

        let body = NSFont.systemFont(ofSize: 11)
        let italicDescriptor = body.fontDescriptor.withSymbolicTraits(.italic)
        let italic = NSFont(descriptor: italicDescriptor, size: 11) ?? body

        let credits = NSMutableAttributedString()

        credits.append(NSAttributedString(
            string: "by Birch\n",
            attributes: [
                .font: body,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        ))

        credits.append(NSAttributedString(
            string: "birch@birchsport.net\n",
            attributes: [
                .font: body,
                .link: URL(string: "mailto:birch@birchsport.net") as Any,
                .paragraphStyle: paragraph,
            ]
        ))

        credits.append(NSAttributedString(
            string: "https://birchsport.net\n",
            attributes: [
                .font: body,
                .link: URL(string: "https://birchsport.net") as Any,
                .paragraphStyle: paragraph,
            ]
        ))

        credits.append(NSAttributedString(
            string: "\nNo discomfort, no expansion!",
            attributes: [
                .font: italic,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        ))

        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: credits,
        ])
    }
}
