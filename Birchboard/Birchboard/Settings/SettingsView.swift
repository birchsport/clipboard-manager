import SwiftUI
import KeyboardShortcuts
import ServiceManagement

/// Settings window. Three tabs: General, Hotkey, Privacy. Accessed from the status
/// bar menu or ⌘,.
struct SettingsView: View {
    @EnvironmentObject var services: Services

    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            HotkeyTab().tabItem { Label("Hotkey", systemImage: "command") }
            SnippetsTab().tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            PrivacyTab().tabItem { Label("Privacy", systemImage: "lock") }
            HelpTab().tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(width: 620, height: 480)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var preferences: Preferences
    @EnvironmentObject var updater: UpdaterController
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { newValue in
                        if applyLaunchAtLogin(newValue) {
                            preferences.launchAtLogin = newValue
                        }
                    }
                ))
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Retention") {
                Stepper(value: $preferences.retentionCount, in: 50...10000, step: 50) {
                    Text("Keep at most \(preferences.retentionCount) entries")
                }
                Stepper(value: $preferences.retentionDays, in: 1...365) {
                    Text("Discard after \(preferences.retentionDays) days")
                }
            }
            Section("Paste behaviour") {
                Toggle("Restore clipboard after paste",
                       isOn: $preferences.restoreClipboardAfterPaste)
            }
            Section("Multi-select") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Delimiter between entries")
                        Spacer()
                        TextField("", text: $preferences.multiSelectDelimiter)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 120)
                    }
                    Text("Parses as: \(parsedDelimiterDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Select multiple entries with ⇧Space (or ⌘-click) and press ⏎ to paste them joined by this string. Use \\n for newline, \\t for tab, \\\\ for backslash.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Panel opacity")
                        Spacer()
                        Text("\(Int(preferences.panelOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $preferences.panelOpacity, in: 0.3...1.0)
                }
            }
            Section("Easter Eggs") {
                Toggle("Predictive Paste", isOn: $preferences.predictivePasteEnabled)
                Text("Pastes a random silly quote when the Predictive Paste hotkey fires. Configure the hotkey in the Hotkey tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Automatically check for updates",
                       isOn: $updater.automaticallyChecks)
                Text("Check interval: every 24 hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                    Spacer()
                }
                Text(updatesFooter)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Friendly description of the multi-select delimiter as it'll be parsed
    /// at paste time. Empty string and pure whitespace get explicit labels so
    /// the user isn't staring at a blank field wondering whether anything will
    /// happen.
    private var parsedDelimiterDescription: String {
        let raw = preferences.multiSelectDelimiter
        if raw.isEmpty { return "empty (entries concatenated)" }
        let parsed = PanelController.parseDelimiter(raw)
        switch parsed {
        case "\n": return "newline"
        case "\t": return "tab"
        case "\n\n": return "blank line"
        case " ": return "space"
        case "": return "empty (entries concatenated)"
        default:
            // Show the literal characters in quotes; replace common whitespace
            // with visible escapes so what the user sees matches what they'll
            // get on paste.
            let visible = parsed
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "“\(visible)”"
        }
    }

    private var updatesFooter: String {
        let version = "Current version \(updater.currentVersion)"
        guard let last = updater.lastCheckDate else {
            return "\(version) · never checked"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(version) · last checked \(formatter.localizedString(for: last, relativeTo: Date()))"
    }

    /// Returns true iff the change was accepted by SMAppService. Unsigned dev builds
    /// will typically fail here — we surface the error inline rather than silently
    /// flipping the toggle.
    private func applyLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
            return true
        } catch {
            launchAtLoginError = "Couldn't update login item: \(error.localizedDescription)"
            return false
        }
    }
}

private struct HotkeyTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle clipboard panel:", name: .togglePanel)
            KeyboardShortcuts.Recorder("Predictive Paste:", name: .predictivePaste)
        }
        .padding()
    }
}

private struct PrivacyTab: View {
    @EnvironmentObject var services: Services
    @EnvironmentObject var preferences: Preferences
    @State private var confirm: ConfirmKind?

    enum ConfirmKind: Identifiable {
        case all, unpinned
        var id: Int { self == .all ? 0 : 1 }
    }

    var body: some View {
        Form {
            Section("History") {
                Button("Clear unpinned entries…") { confirm = .unpinned }
                Button("Clear all history…", role: .destructive) { confirm = .all }
            }
            Section("Backup") {
                BackupSection(repository: services.repository)
            }
            Section("Ignored apps") {
                IgnoredAppsSection(preferences: preferences)
            }
            Section("Accessibility") {
                Text(AccessibilityPermission.isTrusted
                     ? "Accessibility access is granted."
                     : "Accessibility access is required to paste into the previous app.")
                if !AccessibilityPermission.isTrusted {
                    Button("Open System Settings") {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(item: $confirm) { kind in
            switch kind {
            case .all:
                return Alert(title: Text("Clear all history?"),
                             message: Text("This cannot be undone. Pinned entries will also be removed."),
                             primaryButton: .destructive(Text("Clear")) {
                                 try? services.repository.clearAll()
                             },
                             secondaryButton: .cancel())
            case .unpinned:
                return Alert(title: Text("Clear unpinned entries?"),
                             message: Text("Pinned entries will be kept."),
                             primaryButton: .destructive(Text("Clear")) {
                                 try? services.repository.clearUnpinned()
                             },
                             secondaryButton: .cancel())
            }
        }
    }
}

/// Manages the bundle-ID allowlist that `ClipboardWatcher` consults on every
/// poll. When one of these apps is frontmost we skip capture entirely.
private struct IgnoredAppsSection: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard activity is not captured while these apps are frontmost.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if preferences.ignoredAppBundleIDs.isEmpty {
                Text("No apps are currently ignored.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(preferences.ignoredAppBundleIDs, id: \.self) { bundleID in
                        IgnoredAppRow(
                            bundleID: bundleID,
                            onRemove: { remove(bundleID: bundleID) }
                        )
                        if bundleID != preferences.ignoredAppBundleIDs.last {
                            Divider()
                        }
                    }
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }

            HStack(spacing: 8) {
                Button {
                    addAppFromPicker()
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                Spacer()
                Button("Reset to defaults") {
                    preferences.resetIgnoredAppsToDefaults()
                }
                .disabled(preferences.ignoredAppBundleIDs == Preferences.defaultIgnoredAppBundleIDs)
            }
        }
        .padding(.vertical, 4)
    }

    private func remove(bundleID: String) {
        preferences.ignoredAppBundleIDs.removeAll { $0 == bundleID }
    }

    /// Open an NSOpenPanel scoped to apps, then extract the bundle identifier
    /// from whatever the user picks.
    private func addAppFromPicker() {
        let panel = NSOpenPanel()
        panel.title = "Pick an app to ignore"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            NSLog("Birchboard: couldn't read bundle ID from \(url.path)")
            return
        }
        if !preferences.ignoredAppBundleIDs.contains(bundleID) {
            preferences.ignoredAppBundleIDs.append(bundleID)
        }
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 12))
                Text(bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from ignore list")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private var displayName: String {
        if let url = appURL {
            if let bundle = Bundle(url: url),
               let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                       ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                return name
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID  // app isn't installed — show the raw ID
    }

    @ViewBuilder
    private var icon: some View {
        if let url = appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tertiary)
        }
    }
}

/// Export / import buttons. Writes the full history as a single JSON file
/// (images inlined as base64). Reads the same shape back, dedup-merging on
/// `dedup_hash` so re-importing the same file is a no-op.
private struct BackupSection: View {
    let repository: EntryRepository
    @State private var status: Status = .idle
    @State private var isWorking = false

    enum Status: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export bundles every entry (including images) into a single .json file. Import merges — duplicates are skipped by content hash.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    runExport()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking)

                Button {
                    runImport()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                Spacer()
            }

            switch status {
            case .idle:
                EmptyView()
            case .success(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.title = "Export Birchboard history"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultExportFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        status = .idle
        Task.detached(priority: .userInitiated) {
            do {
                let archive = try repository.exportArchive()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(archive)
                try data.write(to: url, options: [.atomic])
                await MainActor.run {
                    status = .success("Exported \(archive.entries.count) entries to \(url.lastPathComponent).")
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    status = .failure("Export failed: \(error.localizedDescription)")
                    isWorking = false
                }
            }
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.title = "Import Birchboard history"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        status = .idle
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let archive = try decoder.decode(HistoryArchive.self, from: data)
                guard archive.version == HistoryArchive.currentVersion else {
                    throw NSError(domain: "Birchboard", code: 1, userInfo: [
                        NSLocalizedDescriptionKey:
                            "Archive version \(archive.version) isn't supported (expected \(HistoryArchive.currentVersion))."
                    ])
                }
                let summary = try repository.importArchive(archive)
                await MainActor.run {
                    let msg = "Imported \(summary.imported) entries"
                        + (summary.skippedDuplicates > 0
                            ? " (\(summary.skippedDuplicates) duplicates skipped)."
                            : ".")
                    status = .success(msg)
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    status = .failure("Import failed: \(error.localizedDescription)")
                    isWorking = false
                }
            }
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Birchboard-\(formatter.string(from: Date())).json"
    }
}
