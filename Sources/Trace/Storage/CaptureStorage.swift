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

    var pinnedCaptures: [CaptureItem] {
        captures.filter(\.isPinned)
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
        try save(image: image, pixelWidth: Int(image.size.width), pixelHeight: Int(image.size.height), mode: mode, date: date)
    }

    func save(capture: CaptureResult, mode: CaptureMode, date: Date = Date()) throws -> SavedCapture {
        try save(
            image: capture.image,
            pixelWidth: capture.pixelWidth,
            pixelHeight: capture.pixelHeight,
            mode: mode,
            date: date
        )
    }

    private func save(
        image: NSImage,
        pixelWidth: Int,
        pixelHeight: Int,
        mode: CaptureMode,
        date: Date
    ) throws -> SavedCapture {
        let rootURL = settingsStore.rootURL
        let folderName = TraceDateFormatters.folder.string(from: date)
        let capturesDirectory = rootURL.appendingPathComponent("captures").appendingPathComponent(folderName)
        let thumbnailsDirectory = rootURL.appendingPathComponent("thumbnails").appendingPathComponent(folderName)

        try fileManager.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)

        let baseName = makeBaseName(date: date)
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
            width: pixelWidth,
            height: pixelHeight,
            captureMode: mode,
            deliveredAppName: nil,
            deliveryState: mode == .copyOnly ? .none : .skipped
        )

        var nextMetadata = metadata
        nextMetadata.captures.append(item)
        try writeMetadata(nextMetadata)
        metadata = nextMetadata
        return SavedCapture(item: item, fileURL: imageURL, thumbnailURL: thumbnailURL)
    }

    func updateDelivery(itemID: String, appName: String?, state: DeliveryState) {
        var nextMetadata = metadata
        guard let index = nextMetadata.captures.firstIndex(where: { $0.id == itemID }) else { return }
        nextMetadata.captures[index].deliveredAppName = appName
        nextMetadata.captures[index].deliveryState = state
        guard (try? writeMetadata(nextMetadata)) != nil else { return }
        metadata = nextMetadata
    }

    func capture(withID itemID: String) -> CaptureItem? {
        metadata.captures.first { $0.id == itemID }
    }

    func rename(itemID: String, to proposedName: String) throws {
        var nextMetadata = metadata
        guard let index = nextMetadata.captures.firstIndex(where: { $0.id == itemID }) else { return }
        let cleanName = sanitizedFileBaseName(proposedName)
        guard !cleanName.isEmpty else {
            throw TraceError.invalidCaptureName
        }

        let rootURL = settingsStore.rootURL
        let originalImageURL = absoluteURL(for: nextMetadata.captures[index].filePath)
        let targetImageURL = uniqueURL(
            directory: originalImageURL.deletingLastPathComponent(),
            baseName: cleanName,
            extension: originalImageURL.pathExtension.isEmpty ? "png" : originalImageURL.pathExtension,
            excluding: originalImageURL
        )

        if originalImageURL.standardizedFileURL != targetImageURL.standardizedFileURL,
           fileManager.fileExists(atPath: originalImageURL.path) {
            try fileManager.moveItem(at: originalImageURL, to: targetImageURL)
            nextMetadata.captures[index].filePath = targetImageURL.relativePath(from: rootURL)
        }

        if let thumbnailPath = nextMetadata.captures[index].thumbnailPath {
            let originalThumbnailURL = absoluteURL(for: thumbnailPath)
            if fileManager.fileExists(atPath: originalThumbnailURL.path) {
                let targetThumbnailURL = uniqueURL(
                    directory: originalThumbnailURL.deletingLastPathComponent(),
                    baseName: targetImageURL.deletingPathExtension().lastPathComponent,
                    extension: originalThumbnailURL.pathExtension.isEmpty ? "jpg" : originalThumbnailURL.pathExtension,
                    excluding: originalThumbnailURL
                )
                if originalThumbnailURL.standardizedFileURL != targetThumbnailURL.standardizedFileURL {
                    try? fileManager.moveItem(at: originalThumbnailURL, to: targetThumbnailURL)
                    if fileManager.fileExists(atPath: targetThumbnailURL.path) {
                        nextMetadata.captures[index].thumbnailPath = targetThumbnailURL.relativePath(from: rootURL)
                    }
                }
            }
        }

        nextMetadata.captures[index].title = cleanName
        try writeMetadata(nextMetadata)
        metadata = nextMetadata
    }

    func delete(itemID: String) throws {
        var nextMetadata = metadata
        guard let index = nextMetadata.captures.firstIndex(where: { $0.id == itemID }) else { return }
        let item = nextMetadata.captures[index]

        let imageURL = absoluteURL(for: item.filePath)
        if fileManager.fileExists(atPath: imageURL.path) {
            try fileManager.removeItem(at: imageURL)
        }

        if let thumbnailPath = item.thumbnailPath {
            let thumbnailURL = absoluteURL(for: thumbnailPath)
            if fileManager.fileExists(atPath: thumbnailURL.path) {
                try? fileManager.removeItem(at: thumbnailURL)
            }
        }

        nextMetadata.captures.remove(at: index)
        try writeMetadata(nextMetadata)
        metadata = nextMetadata
    }

    func delete(itemIDs: [String]) throws {
        let uniqueIDs = Set(itemIDs)
        guard !uniqueIDs.isEmpty else { return }
        for itemID in uniqueIDs {
            try delete(itemID: itemID)
        }
    }

    func setPinned(_ isPinned: Bool, itemID: String) {
        var nextMetadata = metadata
        guard let index = nextMetadata.captures.firstIndex(where: { $0.id == itemID }) else { return }
        nextMetadata.captures[index].isPinned = isPinned
        guard (try? writeMetadata(nextMetadata)) != nil else { return }
        metadata = nextMetadata
    }

    func setPinned(_ isPinned: Bool, itemIDs: [String]) {
        let ids = Set(itemIDs)
        guard !ids.isEmpty else { return }
        var nextMetadata = metadata
        var changed = false
        for index in nextMetadata.captures.indices where ids.contains(nextMetadata.captures[index].id) {
            nextMetadata.captures[index].isPinned = isPinned
            changed = true
        }
        guard changed else { return }
        guard (try? writeMetadata(nextMetadata)) != nil else { return }
        metadata = nextMetadata
    }

    func setBookmarked(_ isBookmarked: Bool, itemID: String) {
        var nextMetadata = metadata
        guard let index = nextMetadata.captures.firstIndex(where: { $0.id == itemID }) else { return }
        nextMetadata.captures[index].isBookmarked = isBookmarked
        guard (try? writeMetadata(nextMetadata)) != nil else { return }
        metadata = nextMetadata
    }

    func setBookmarked(_ isBookmarked: Bool, itemIDs: [String]) {
        let ids = Set(itemIDs)
        guard !ids.isEmpty else { return }
        var nextMetadata = metadata
        var changed = false
        for index in nextMetadata.captures.indices where ids.contains(nextMetadata.captures[index].id) {
            nextMetadata.captures[index].isBookmarked = isBookmarked
            changed = true
        }
        guard changed else { return }
        guard (try? writeMetadata(nextMetadata)) != nil else { return }
        metadata = nextMetadata
    }

    func applyNamingRuleToAllCaptures() throws {
        var nextMetadata = metadata
        let orderedIndices = nextMetadata.captures.indices.sorted {
            nextMetadata.captures[$0].createdAt < nextMetadata.captures[$1].createdAt
        }

        struct RenamePlan {
            let index: Int
            let baseName: String
        }

        let plans: [RenamePlan] = orderedIndices.enumerated().map { offset, index in
            let item = nextMetadata.captures[index]
            let baseName: String
            switch settingsStore.settings.fileNameRule {
            case .dateTime:
                baseName = formatter(for: settingsStore.settings.dateFileNameFormat).string(from: item.createdAt)
            case .sequence:
                baseName = sequenceBaseName(offset: offset, style: settingsStore.settings.sequenceStyle)
            }
            return RenamePlan(index: index, baseName: baseName)
        }

        let rootURL = settingsStore.rootURL
        let tempSuffix = UUID().uuidString
        var tempImageURLs: [Int: URL] = [:]
        var tempThumbnailURLs: [Int: URL] = [:]

        for plan in plans {
            let item = nextMetadata.captures[plan.index]
            let imageURL = absoluteURL(for: item.filePath)
            if fileManager.fileExists(atPath: imageURL.path) {
                let tempImageURL = uniqueURL(
                    directory: imageURL.deletingLastPathComponent(),
                    baseName: "__trace_tmp_\(tempSuffix)",
                    extension: imageURL.pathExtension.isEmpty ? "png" : imageURL.pathExtension
                )
                try fileManager.moveItem(at: imageURL, to: tempImageURL)
                tempImageURLs[plan.index] = tempImageURL
                nextMetadata.captures[plan.index].filePath = tempImageURL.relativePath(from: rootURL)
            }

            if let thumbnailPath = item.thumbnailPath {
                let thumbnailURL = absoluteURL(for: thumbnailPath)
                if fileManager.fileExists(atPath: thumbnailURL.path) {
                    let tempThumbnailURL = uniqueURL(
                        directory: thumbnailURL.deletingLastPathComponent(),
                        baseName: "__trace_tmp_thumb_\(tempSuffix)",
                        extension: thumbnailURL.pathExtension.isEmpty ? "jpg" : thumbnailURL.pathExtension
                    )
                    try fileManager.moveItem(at: thumbnailURL, to: tempThumbnailURL)
                    tempThumbnailURLs[plan.index] = tempThumbnailURL
                    nextMetadata.captures[plan.index].thumbnailPath = tempThumbnailURL.relativePath(from: rootURL)
                }
            }
        }

        for plan in plans {
            let imageExtension: String
            if let tempImageURL = tempImageURLs[plan.index] {
                imageExtension = tempImageURL.pathExtension.isEmpty ? "png" : tempImageURL.pathExtension
                let finalImageURL = uniqueURL(
                    directory: tempImageURL.deletingLastPathComponent(),
                    baseName: plan.baseName,
                    extension: imageExtension
                )
                try fileManager.moveItem(at: tempImageURL, to: finalImageURL)
                nextMetadata.captures[plan.index].filePath = finalImageURL.relativePath(from: rootURL)
            } else {
                let currentPath = nextMetadata.captures[plan.index].filePath
                imageExtension = URL(fileURLWithPath: currentPath).pathExtension.isEmpty ? "png" : URL(fileURLWithPath: currentPath).pathExtension
            }

            if let tempThumbnailURL = tempThumbnailURLs[plan.index] {
                let thumbnailExtension = tempThumbnailURL.pathExtension.isEmpty ? "jpg" : tempThumbnailURL.pathExtension
                let finalThumbnailURL = uniqueURL(
                    directory: tempThumbnailURL.deletingLastPathComponent(),
                    baseName: plan.baseName,
                    extension: thumbnailExtension
                )
                try fileManager.moveItem(at: tempThumbnailURL, to: finalThumbnailURL)
                nextMetadata.captures[plan.index].thumbnailPath = finalThumbnailURL.relativePath(from: rootURL)
            }

            nextMetadata.captures[plan.index].title = plan.baseName
        }

        try writeMetadata(nextMetadata)
        metadata = nextMetadata
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

    private func uniqueURL(
        directory: URL,
        baseName: String,
        extension fileExtension: String,
        excluding excludedURL: URL? = nil
    ) -> URL {
        var suffix = 1
        let excludedPath = excludedURL?.standardizedFileURL.path
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            let url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
            if url.standardizedFileURL.path == excludedPath || !fileManager.fileExists(atPath: url.path) {
                return url
            }
            suffix += 1
        }
    }

    private func uniqueID(baseID: String, excluding excludedID: String? = nil) -> String {
        var candidate = baseID
        var suffix = 2
        let existing = Set(metadata.captures.map(\.id).filter { $0 != excludedID })
        while existing.contains(candidate) {
            candidate = "\(baseID)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func sanitizedFileBaseName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
            .union(.newlines)
            .union(.controlCharacters)
        return name
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func makeBaseName(date: Date) -> String {
        switch settingsStore.settings.fileNameRule {
        case .dateTime:
            return formatter(for: settingsStore.settings.dateFileNameFormat).string(from: date)
        case .sequence:
            return nextSequenceBaseNameGlobal(style: settingsStore.settings.sequenceStyle)
        }
    }

    private func formatter(for format: TraceSettings.DateFileNameFormat) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format.pattern
        return formatter
    }

    private func nextSequenceBaseNameGlobal(style: TraceSettings.SequenceStyle) -> String {
        let existingNames = metadata.captures
            .map { URL(fileURLWithPath: $0.filePath).deletingPathExtension().lastPathComponent }

        switch style {
        case .numeric:
            let maxIndex = existingNames
                .compactMap { parseNumericSequence($0) }
                .max() ?? 0
            return String(format: "%03d", maxIndex + 1)
        case .koreanAlphabet:
            let letters = ["가", "나", "다", "라", "마", "바", "사", "아", "자", "차", "카", "타", "파", "하"]
            let maxOffset = existingNames
                .compactMap { parseKoreanSequence($0, letters: letters) }
                .max() ?? -1
            let nextOffset = maxOffset + 1
            let letterIndex = nextOffset % letters.count
            let cycle = (nextOffset / letters.count) + 1
            let letter = letters[letterIndex]
            return cycle == 1 ? letter : "\(letter)\(cycle)"
        }
    }

    private func parseNumericSequence(_ value: String) -> Int? {
        guard value.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        return Int(value)
    }

    private func parseKoreanSequence(_ value: String, letters: [String]) -> Int? {
        guard let letter = letters.first(where: { value.hasPrefix($0) }) else {
            return nil
        }
        let suffix = String(value.dropFirst(letter.count))
        let cycle = suffix.isEmpty ? 1 : Int(suffix)
        guard let cycle, cycle >= 1, let letterIndex = letters.firstIndex(of: letter) else {
            return nil
        }
        return (cycle - 1) * letters.count + letterIndex
    }

    private func sequenceBaseName(offset: Int, style: TraceSettings.SequenceStyle) -> String {
        switch style {
        case .numeric:
            return String(format: "%03d", offset + 1)
        case .koreanAlphabet:
            let letters = ["가", "나", "다", "라", "마", "바", "사", "아", "자", "차", "카", "타", "파", "하"]
            let letterIndex = offset % letters.count
            let cycle = (offset / letters.count) + 1
            let letter = letters[letterIndex]
            return cycle == 1 ? letter : "\(letter)\(cycle)"
        }
    }

    private func writeMetadata() throws {
        try writeMetadata(metadata)
    }

    private func writeMetadata(_ metadata: CaptureMetadata) throws {
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
