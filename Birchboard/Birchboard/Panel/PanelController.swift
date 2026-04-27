import AppKit
import SwiftUI
import Combine

/// Orchestrates the lifecycle of the clipboard panel: remembers which app was frontmost
/// before we opened, shows/hides the panel, and drives the paste sequence.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let services: Services
    private var panel: ClipboardPanel?
    private var hostingView: NSHostingView<PanelContentView>?
    private var previousApp: NSRunningApplication?
    private var localEventMonitor: Any?
    private var opacityCancellable: AnyCancellable?

    /// Published to the content view so it can bubble actions back up (paste etc).
    let actions: PanelActions

    init(services: Services) {
        self.services = services
        self.actions = PanelActions()
        super.init()
        self.actions.controller = self

        // Live-apply panel opacity as the user drags the slider in Settings.
        opacityCancellable = services.preferences.$panelOpacity
            .sink { [weak self] value in
                self?.panel?.alphaValue = CGFloat(value)
            }
    }

    // MARK: - Show / hide / toggle

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Capture the frontmost app BEFORE we order-front the panel.
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = ensurePanel()
        centerOnActiveScreen(panel)
        panel.alphaValue = CGFloat(services.preferences.panelOpacity)

        installEventMonitor()
        panel.orderFrontRegardless()
        panel.makeKey()
        // Deliberately NOT calling NSApp.activate — we want to stay a background agent.

        // Reset the view state (selection + query + refreshed list).
        hostingView?.rootView.viewModel.refresh()
        hostingView?.rootView.viewModel.focusSearchField()
    }

    func hide() {
        removeEventMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Paste flow

    /// Writes `entry` to the pasteboard, restores focus to `previousApp`, and posts ⌘V.
    /// If `restoreClipboardAfterPaste` is enabled we snapshot first and restore ~500ms
    /// after the keystroke.
    ///
    /// Activation order matters on macOS 14+: we activate the target BEFORE ordering
    /// our panel out, so WindowServer has a stable frontmost when the panel goes
    /// away. We do NOT gate this on `AXIsProcessTrusted()` — that API is unreliable
    /// for ad-hoc-signed dev builds. If permission is genuinely missing the
    /// `CGEvent.post` is a silent no-op and the user can ⌘V manually.
    func paste(_ entry: ClipEntry, asPlainText: Bool) {
        let prefs = services.preferences
        let snapshot: [[NSPasteboard.PasteboardType: Data]]? =
            prefs.restoreClipboardAfterPaste ? ClipboardWriter.snapshot() : nil

        ClipboardWriter.write(entry, asPlainText: asPlainText)

        let target = previousApp

        // 1. Hand activation back to the target while our panel is still up.
        //    (`.activateIgnoringOtherApps` is a no-op on macOS 14+; empty options
        //    use the new cooperative activation.)
        target?.activate(options: [])

        // 2. Dismiss the panel.
        hide()

        // 3. Give WindowServer time to finish the activation before injecting ⌘V.
        //    Empirically 120 ms is enough on macOS 14; shorter is flaky with
        //    apps that bring up windows on activate (e.g. Xcode, Slack).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            ClipboardWriter.synthesizeCmdV()
        }

        if let snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                ClipboardWriter.restore(snapshot)
            }
        }
    }

    func togglePin(_ entry: ClipEntry) {
        try? services.repository.togglePin(id: entry.id)
    }

    func toggleObfuscation(_ entry: ClipEntry) {
        try? services.repository.toggleObfuscation(id: entry.id)
    }

    func setObfuscationNickname(_ entry: ClipEntry, _ nickname: String?) {
        try? services.repository.setObfuscationNickname(id: entry.id, nickname)
    }

    func delete(_ entry: ClipEntry) {
        try? services.repository.delete(id: entry.id)
    }

    // MARK: - Internals

    private func ensurePanel() -> ClipboardPanel {
        if let panel { return panel }
        let rect = NSRect(x: 0, y: 0, width: 720, height: 460)
        let panel = ClipboardPanel(contentRect: rect)
        panel.delegate = self

        let view = PanelContentView(viewModel: PanelViewModel(services: services,
                                                              actions: actions))
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = host
        self.hostingView = host
        self.panel = panel
        return panel
    }

    private func centerOnActiveScreen(_ panel: ClipboardPanel) {
        let screen = NSScreen.screenUnderCursor() ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    /// Local monitor that intercepts arrow keys / enter / esc / ⌘P / ⌘⌫ while the
    /// panel is key. Non-handled events flow through to the text field.
    private func installEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else {
                return event
            }
            if self.hostingView?.rootView.viewModel.handle(event: event) == true {
                return nil
            }
            return event
        }
    }

    private func removeEventMonitor() {
        if let m = localEventMonitor {
            NSEvent.removeMonitor(m)
            localEventMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking outside the panel resigns key — dismiss.
        hide()
    }
}

/// Thin action surface the SwiftUI content view calls into. The controller is set
/// after init to break the retain cycle between panel and view model.
@MainActor
final class PanelActions: ObservableObject {
    weak var controller: PanelController?

    func paste(_ entry: ClipEntry, asPlainText: Bool) {
        controller?.paste(entry, asPlainText: asPlainText)
    }

    func dismiss() { controller?.hide() }
    func togglePin(_ entry: ClipEntry) { controller?.togglePin(entry) }
    func toggleObfuscation(_ entry: ClipEntry) { controller?.toggleObfuscation(entry) }
    func setObfuscationNickname(_ entry: ClipEntry, _ nickname: String?) {
        controller?.setObfuscationNickname(entry, nickname)
    }
    func delete(_ entry: ClipEntry) { controller?.delete(entry) }
}

private extension NSScreen {
    /// Screen containing the mouse cursor, or nil if none matched.
    static func screenUnderCursor() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }
}
