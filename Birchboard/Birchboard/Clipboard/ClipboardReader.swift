import AppKit

/// Extracts the richest representation available from `NSPasteboard.general` and turns
/// it into an `EntryKind`. The order below matters: file URLs win over images, which
/// win over RTF, which wins over plain strings.
struct ClipboardReader {
    let blobStore: BlobStore

    func read(pasteboard: NSPasteboard = .general) -> EntryKind? {
        // Skip anything flagged sensitive by the source app.
        if SensitiveContentFilter.isConcealed(pasteboard) { return nil }

        // 1. File URLs (may be multiple).
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty,
           urls.allSatisfy({ $0.isFileURL }) {
            return .fileURLs(urls)
        }

        // 2. Images (TIFF covers PNG/JPEG/etc. after conversion).
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            if let rep = NSBitmapImageRep(data: imageData) {
                let pngData = rep.representation(using: .png, properties: [:]) ?? imageData
                let hash = ImageHash.sha256Hex(of: pngData)
                do {
                    let path = try blobStore.store(data: pngData, hash: hash, ext: "png")
                    return .image(blobPath: path,
                                  width: rep.pixelsWide,
                                  height: rep.pixelsHigh,
                                  hash: hash)
                } catch {
                    NSLog("Birchboard: failed to persist image blob: \(error)")
                    // Fall through to text if image storage fails.
                }
            }
        }

        // 3. Rich text. Keep a plaintext projection for search.
        if let rtfData = pasteboard.data(forType: .rtf) {
            let plain = pasteboard.string(forType: .string)
                ?? Self.plainText(fromRTF: rtfData)
                ?? ""
            return .rtf(rtfData, plainText: plain)
        }

        // 4. Plain text.
        if let s = pasteboard.string(forType: .string), !s.isEmpty {
            return .text(s)
        }

        return nil
    }

    private static func plainText(fromRTF data: Data) -> String? {
        guard let attr = try? NSAttributedString(data: data,
                                                 options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil) else {
            return nil
        }
        return attr.string
    }
}
