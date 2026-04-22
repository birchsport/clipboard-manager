import AppKit

/// Writes an entry back to the general pasteboard and — after a short delay so the
/// target app is actually frontmost — posts a synthetic ⌘V. The caller is responsible
/// for restoring focus to the previously frontmost app before invoking `paste`.
enum ClipboardWriter {
    /// Synchronously writes `entry` to the general pasteboard.
    /// Optionally returns the clipboard contents as a snapshot the caller can restore.
    @discardableResult
    static func write(_ entry: ClipEntry, asPlainText: Bool) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch entry.kind {
        case .text(let s):
            pb.setString(s, forType: .string)

        case .rtf(let data, let plain):
            if asPlainText {
                pb.setString(plain, forType: .string)
            } else {
                pb.setData(data, forType: .rtf)
                pb.setString(plain, forType: .string)
            }

        case .image(let blobPath, _, _, _):
            if let data = try? Data(contentsOf: blobPath),
               let image = NSImage(data: data) {
                pb.writeObjects([image])
            }

        case .fileURLs(let urls):
            pb.writeObjects(urls as [NSURL])
        }

        let changeCount = pb.changeCount
        ClipboardWatcher.markSelfProduced(changeCount: changeCount)
        return changeCount
    }

    /// Captures the current pasteboard so we can restore it after pasting.
    static func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    /// Restores a pasteboard snapshot captured by `snapshot()`.
    static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pb.writeObjects(items)
            ClipboardWatcher.markSelfProduced(changeCount: pb.changeCount)
        }
    }

    /// Posts ⌘V. Requires Accessibility permission. We use the annotated session
    /// tap rather than the HID tap because some apps (Electron, some Qt apps) filter
    /// events that appear to come from the raw HID layer but accept them at the
    /// session layer.
    static func synthesizeCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vkV: CGKeyCode = 0x09
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vkV, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vkV, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
