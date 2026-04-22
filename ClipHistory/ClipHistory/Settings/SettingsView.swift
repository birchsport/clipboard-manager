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
        }
        .frame(width: 620, height: 420)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var preferences: Preferences
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
        }
        .formStyle(.grouped)
        .padding()
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
            NSLog("ClipHistory: couldn't read bundle ID from \(url.path)")
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
