import KeyboardShortcuts

/// Named global shortcuts. Adding a new hotkey = new static here.
extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel",
                                  default: .init(.v, modifiers: [.command, .shift]))

    static let predictivePaste = Self("predictivePaste",
                                      default: .init(.p, modifiers: [.control, .option, .command]))
}
