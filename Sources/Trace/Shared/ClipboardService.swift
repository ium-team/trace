import AppKit
import Foundation

enum ClipboardService {
    static func copy(image: NSImage) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects([image]) {
            throw TraceError.pasteboardFailed
        }
    }

    static func copyImageFile(at url: URL) throws {
        guard let image = NSImage(contentsOf: url) else {
            throw TraceError.pasteboardFailed
        }
        try copy(image: image)
    }
}
