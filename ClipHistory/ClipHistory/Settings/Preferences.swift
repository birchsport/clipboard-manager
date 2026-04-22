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
    }

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

    init() {
        self.retentionCount = (defaults.object(forKey: Keys.retentionCount) as? Int) ?? 1000
        self.retentionDays = (defaults.object(forKey: Keys.retentionDays) as? Int) ?? 90
        self.restoreClipboardAfterPaste = defaults.bool(forKey: Keys.restoreClipboardAfterPaste)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.panelOpacity = (defaults.object(forKey: Keys.panelOpacity) as? Double) ?? 0.85
    }
}
