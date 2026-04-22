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
