import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class CaptureStorage {
    private let fileManager: FileManager
    private let settingsStore: SettingsStore
    private(set) var metadata: CaptureMetadata

    init(settingsStore: SettingsStore, fileManager: FileManager = .default) {
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.metadata = Self.loadMetadata(rootURL: settingsStore.rootURL, fileManager: fileManager)
    }

    var captures: [CaptureItem] {
        metadata.captures.sorted { $0.createdAt > $1.createdAt }
    }

    func reload() {
        metadata = Self.loadMetadata(rootURL: settingsStore.rootURL, fileManager: fileManager)
    }

    func absoluteURL(for relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }
        return settingsStore.rootURL.appendingPathComponent(relativePath)
    }

    func save(image: NSImage, mode: CaptureMode, date: Date = Date()) throws -> SavedCapture {
        let rootURL = settingsStore.rootURL
        let folderName = TraceDateFormatters.folder.string(from: date)
        let capturesDirectory = rootURL.appendingPathComponent("captures").appendingPathComponent(folderName)
        let thumbnailsDirectory = rootURL.appendingPathComponent("thumbnails").appendingPathComponent(folderName)

        try fileManager.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)

        let baseName = TraceDateFormatters.filename.string(from: date)
        let imageURL = uniqueURL(directory: capturesDirectory, baseName: baseName, extension: "png")
        let id = imageURL.deletingPathExtension().lastPathComponent

        guard let pngData = image.pngData() else {
            throw TraceError.imageEncodingFailed
        }
        try pngData.write(to: imageURL, options: .atomic)

        var thumbnailURL: URL?
        if let thumbnailData = image.thumbnail(maxPixelSize: 360).jpegData(compression: 0.78) {
            let candidate = thumbnailsDirectory.appendingPathComponent(id).appendingPathExtension("jpg")
            try? thumbnailData.write(to: candidate, options: .atomic)
            if fileManager.fileExists(atPath: candidate.path) {
                thumbnailURL = candidate
            }
        }

        let item = CaptureItem(
            id: uniqueID(baseID: id),
            filePath: imageURL.relativePath(from: rootURL),
            thumbnailPath: thumbnailURL?.relativePath(from: rootURL),
            createdAt: date,
            width: Int(image.size.width),
            height: Int(image.size.height),
            captureMode: mode,
            deliveredAppName: nil,
            deliveryState: mode == .copyOnly ? .none : .skipped
        )

        metadata.captures.append(item)
        try writeMetadata()
        return SavedCapture(item: item, fileURL: imageURL, thumbnailURL: thumbnailURL)
    }

    func updateDelivery(itemID: String, appName: String?, state: DeliveryState) {
        guard let index = metadata.captures.firstIndex(where: { $0.id == itemID }) else { return }
        metadata.captures[index].deliveredAppName = appName
        metadata.captures[index].deliveryState = state
        try? writeMetadata()
    }

    func fileExists(for item: CaptureItem) -> Bool {
        fileManager.fileExists(atPath: absoluteURL(for: item.filePath).path)
    }

    func groupedByDay() -> [(String, [CaptureItem])] {
        let grouped = Dictionary(grouping: captures) { item in
            TraceDateFormatters.folder.string(from: item.createdAt)
        }
        return grouped
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.0 > $1.0 }
    }

    private func uniqueURL(directory: URL, baseName: String, extension fileExtension: String) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            let url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            suffix += 1
        }
    }

    private func uniqueID(baseID: String) -> String {
        var candidate = baseID
        var suffix = 2
        let existing = Set(metadata.captures.map(\.id))
        while existing.contains(candidate) {
            candidate = "\(baseID)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func writeMetadata() throws {
        let data = try JSONEncoder.trace.encode(metadata)
        try AtomicFileWriter.write(data, to: metadataURL(rootURL: settingsStore.rootURL))
    }

    private static func loadMetadata(rootURL: URL, fileManager: FileManager) -> CaptureMetadata {
        let url = metadataURL(rootURL: rootURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.trace.decode(CaptureMetadata.self, from: data)
        } catch {
            let backup = rootURL.appendingPathComponent("metadata-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.copyItem(at: url, to: backup)
            return .empty
        }
    }

    private func metadataURL(rootURL: URL) -> URL {
        Self.metadataURL(rootURL: rootURL)
    }

    private static func metadataURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent("metadata.json")
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func jpegData(compression: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }

    func thumbnail(maxPixelSize: CGFloat) -> NSImage {
        let ratio = min(maxPixelSize / max(size.width, size.height), 1)
        let targetSize = NSSize(width: max(1, size.width * ratio), height: max(1, size.height * ratio))
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        return thumbnail
    }
}
