import Foundation
import SwiftUI

/// User-facing preferences, persisted via `UserDefaults`. Exposed as an
/// `ObservableObject` so SwiftUI views can bind directly.
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let retentionCount = "retentionCount"
        static let retentionDays = "retentionDays"
        static let restoreClipboardAfterPaste = "restoreClipboardAfterPaste"
        static let launchAtLogin = "launchAtLogin"
        static let panelOpacity = "panelOpacity"
        static let ignoredAppBundleIDs = "ignoredAppBundleIDs"
    }

    /// Password managers and similar apps we don't want to capture clipboards
    /// from by default. Users can edit the list in Settings → Privacy.
    static let defaultIgnoredAppBundleIDs: [String] = [
        "com.1password.1password",       // 1Password 8
        "com.agilebits.onepassword7",    // 1Password 7
        "com.bitwarden.desktop",         // Bitwarden
        "com.apple.keychainaccess",      // Keychain Access
        "com.apple.Passwords",           // Apple Passwords (macOS 15+)
        "com.lastpass.LastPass",         // LastPass
        "org.keepassxc.keepassxc",       // KeePassXC
    ]

    @Published var retentionCount: Int {
        didSet { defaults.set(retentionCount, forKey: Keys.retentionCount) }
    }

    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }

    @Published var restoreClipboardAfterPaste: Bool {
        didSet { defaults.set(restoreClipboardAfterPaste, forKey: Keys.restoreClipboardAfterPaste) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// Panel alpha, 0.3–1.0. 1.0 = fully opaque, lower = more transparent.
    @Published var panelOpacity: Double {
        didSet { defaults.set(panelOpacity, forKey: Keys.panelOpacity) }
    }

    /// Bundle identifiers of apps whose clipboard activity we should not
    /// record. `ClipboardWatcher` consults this on every poll.
    @Published var ignoredAppBundleIDs: [String] {
        didSet { defaults.set(ignoredAppBundleIDs, forKey: Keys.ignoredAppBundleIDs) }
    }

    init() {
        self.retentionCount = (defaults.object(forKey: Keys.retentionCount) as? Int) ?? 1000
        self.retentionDays = (defaults.object(forKey: Keys.retentionDays) as? Int) ?? 90
        self.restoreClipboardAfterPaste = defaults.bool(forKey: Keys.restoreClipboardAfterPaste)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.panelOpacity = (defaults.object(forKey: Keys.panelOpacity) as? Double) ?? 0.85
        // On first launch, seed with the sensible defaults. Subsequent launches
        // honour whatever the user has set (including empty list).
        self.ignoredAppBundleIDs = (defaults.object(forKey: Keys.ignoredAppBundleIDs) as? [String])
            ?? Self.defaultIgnoredAppBundleIDs
    }

    func resetIgnoredAppsToDefaults() {
        ignoredAppBundleIDs = Self.defaultIgnoredAppBundleIDs
    }
}
