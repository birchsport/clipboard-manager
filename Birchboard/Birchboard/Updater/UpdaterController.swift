import Foundation
import Sparkle
import Combine

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app
/// can stay oblivious to Sparkle types. Owns the live updater, exposes a
/// manual-check entry point for the menu bar, and surfaces
/// `canCheckForUpdates` / `automaticallyChecksForUpdates` as `@Published`
/// properties for SwiftUI bindings.
///
/// The feed URL, public key, interval, and default check-on-launch are all
/// in Info.plist (see `project.yml`), so Sparkle picks them up on first
/// run without needing programmatic configuration.
@MainActor
final class UpdaterController: NSObject, ObservableObject {

    let controller: SPUStandardUpdaterController

    /// Mirrors the updater's `canCheckForUpdates`; used to disable the
    /// Check-now button while a check is in flight.
    @Published private(set) var canCheck: Bool = true

    /// Mirrors the updater's `automaticallyChecksForUpdates` as a
    /// two-way-bindable property for the Settings toggle.
    @Published var automaticallyChecks: Bool {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    override init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        super.init()

        // Mirror the updater's KVO-compliant flags into our @Published
        // versions so SwiftUI re-renders on change.
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &cancellables)
    }

    /// Manually trigger an update check. Sparkle puts up its standard UI —
    /// "up to date" dialog if nothing new, or the update prompt if there is.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// The timestamp of the last check Sparkle performed, or nil if it
    /// hasn't run since install. Shown in the Updates section of Settings.
    var lastCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    /// Convenience for the Settings footer.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
