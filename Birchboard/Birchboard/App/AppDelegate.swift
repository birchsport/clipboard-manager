import AppKit
import SwiftUI
import KeyboardShortcuts

/// Owns the panel controller, the clipboard watcher, and the shared service
/// container. The status-bar UI lives in `BirchboardApp` as a `MenuBarExtra` so we
/// can use `SettingsLink` to open the settings scene reliably on macOS 14+.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = Services()
    private(set) var panelController: PanelController?

    private var watcher: ClipboardWatcher?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Storage.
        do {
            try services.bootstrap()
        } catch {
            NSLog("Birchboard: failed to bootstrap services: \(error)")
        }

        // 2. Panel.
        let controller = PanelController(services: services)
        self.panelController = controller

        // 3. Clipboard watcher.
        let watcher = ClipboardWatcher(repository: services.repository,
                                       blobStore: services.blobStore,
                                       preferences: services.preferences)
        watcher.start()
        self.watcher = watcher

        // 4. Global hotkey.
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak controller] in
            controller?.toggle()
        }

        // 5. Retention sweep on launch and then hourly.
        services.repository.runRetentionSweep(preferences: services.preferences)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.services.repository.runRetentionSweep(preferences: self.services.preferences)
            }
        }

        // NB: we deliberately do NOT prompt for Accessibility here. See
        // AccessibilityPermission.swift for the rationale.
    }

    func togglePanel() {
        panelController?.toggle()
    }
}

/// Shared container for the app's long-lived singletons.
@MainActor
final class Services: ObservableObject {
    let preferences = Preferences()
    let snippetStore = SnippetStore()
    private(set) var database: Database!
    private(set) var repository: EntryRepository!
    private(set) var blobStore: BlobStore!

    func bootstrap() throws {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            .appendingPathComponent("Birchboard", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport,
                                                withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("history.sqlite")
        let blobsURL = appSupport.appendingPathComponent("blobs", isDirectory: true)

        self.blobStore = try BlobStore(root: blobsURL)
        self.database = try Database(url: dbURL)
        self.repository = EntryRepository(database: database, blobStore: blobStore)
    }
}
