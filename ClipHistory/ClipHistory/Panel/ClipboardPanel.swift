import AppKit

/// A borderless, nonactivating, floating panel. Nonactivating is critical: we don't
/// want ClipHistory to become the frontmost app when the panel opens, because we need
/// to paste into whatever the user had open. `canBecomeKey` is still true so the
/// search field can receive typing.
final class ClipboardPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable, .resizable],
                   backing: .buffered,
                   defer: false)

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .utilityWindow
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.setContentSize(NSSize(width: 720, height: 460))
        self.minSize = NSSize(width: 560, height: 360)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}
