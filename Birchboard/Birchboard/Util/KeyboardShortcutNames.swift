import KeyboardShortcuts

/// Named global shortcuts. Adding a new hotkey = new static here.
extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel",
                                  default: .init(.v, modifiers: [.command, .shift]))
}
