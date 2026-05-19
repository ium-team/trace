import AppKit
import XCTest
@testable import Trace

@MainActor
final class CaptureStorageTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try await super.tearDown()
    }

    func testSaveCreatesDatedFoldersAndMetadata() throws {
        let storage = makeStorage()
        let date = ISO8601DateFormatter().date(from: "2026-05-17T14:32:08+09:00")!

        let saved = try storage.save(image: testImage(), mode: .copyOnly, date: date)

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.fileURL.path))
        XCTAssertEqual(saved.fileURL.lastPathComponent, "2026-05-17_14-32-08.png")
        XCTAssertEqual(saved.item.filePath, "captures/2026-05-17/2026-05-17_14-32-08.png")
        XCTAssertEqual(saved.item.deliveryState, .none)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("metadata.json").path))
    }

    func testFilenameCollisionAddsSuffix() throws {
        let storage = makeStorage()
        let date = ISO8601DateFormatter().date(from: "2026-05-17T14:32:08+09:00")!

        let first = try storage.save(image: testImage(), mode: .copyOnly, date: date)
        let second = try storage.save(image: testImage(), mode: .copyOnly, date: date)

        XCTAssertEqual(first.fileURL.lastPathComponent, "2026-05-17_14-32-08.png")
        XCTAssertEqual(second.fileURL.lastPathComponent, "2026-05-17_14-32-08-2.png")
        XCTAssertEqual(storage.captures.count, 2)
    }

    func testNumericSequenceFilenamesArePadded() throws {
        let settings = TraceSettings(
            saveDirectory: temporaryRoot.path,
            globalShortcut: "command+shift+2",
            defaultCaptureMode: .copyOnly,
            fileNameRule: .sequence,
            sequenceStyle: .numeric
        )
        let storage = CaptureStorage(settingsStore: SettingsStore(settings: settings))
        let firstDate = ISO8601DateFormatter().date(from: "2026-05-17T14:32:08+09:00")!
        let secondDate = ISO8601DateFormatter().date(from: "2026-05-18T09:02:01+09:00")!

        let first = try storage.save(image: testImage(), mode: .copyOnly, date: firstDate)
        let second = try storage.save(image: testImage(), mode: .copyOnly, date: secondDate)

        XCTAssertEqual(first.fileURL.lastPathComponent, "001.png")
        XCTAssertEqual(second.fileURL.lastPathComponent, "002.png")
    }

    func testBatchPinBookmarkDelete() throws {
        let storage = makeStorage()
        let first = try storage.save(image: testImage(), mode: .copyOnly)
        let second = try storage.save(image: testImage(), mode: .copyOnly)

        storage.setPinned(true, itemIDs: [first.item.id, second.item.id])
        storage.setBookmarked(true, itemIDs: [first.item.id, second.item.id])

        XCTAssertEqual(storage.pinnedCaptures.count, 2)
        XCTAssertTrue(storage.capture(withID: first.item.id)?.isBookmarked == true)
        XCTAssertTrue(storage.capture(withID: second.item.id)?.isBookmarked == true)

        try storage.delete(itemIDs: [first.item.id, second.item.id])
        XCTAssertTrue(storage.captures.isEmpty)
    }

    func testCorruptMetadataIsRecoveredAsEmpty() throws {
        let metadataURL = temporaryRoot.appendingPathComponent("metadata.json")
        try "not-json".data(using: .utf8)!.write(to: metadataURL)

        let storage = makeStorage()

        XCTAssertEqual(storage.captures.count, 0)
        let backups = try FileManager.default.contentsOfDirectory(atPath: temporaryRoot.path)
            .filter { $0.hasPrefix("metadata-corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testRenameMovesCaptureAndUpdatesMetadata() throws {
        let storage = makeStorage()
        let date = ISO8601DateFormatter().date(from: "2026-05-17T14:32:08+09:00")!
        let saved = try storage.save(image: testImage(), mode: .copyOnly, date: date)

        try storage.rename(itemID: saved.item.id, to: "Edited Capture")

        let item = try XCTUnwrap(storage.capture(withID: saved.item.id))
        XCTAssertEqual(item.title, "Edited Capture")
        XCTAssertEqual(item.filePath, "captures/2026-05-17/Edited Capture.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(item.filePath).path))
    }

    func testDeleteRemovesFilesAndMetadata() throws {
        let storage = makeStorage()
        let saved = try storage.save(image: testImage(), mode: .copyOnly)

        try storage.delete(itemID: saved.item.id)

        XCTAssertNil(storage.capture(withID: saved.item.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.fileURL.path))
    }

    func testPinnedAndBookmarkedArePersisted() throws {
        let storage = makeStorage()
        let saved = try storage.save(image: testImage(), mode: .copyOnly)

        storage.setPinned(true, itemID: saved.item.id)
        storage.setBookmarked(true, itemID: saved.item.id)

        let item = try XCTUnwrap(storage.capture(withID: saved.item.id))
        XCTAssertTrue(item.isPinned)
        XCTAssertTrue(item.isBookmarked)
        XCTAssertEqual(storage.pinnedCaptures.map(\.id), [saved.item.id])
    }

    private func makeStorage() -> CaptureStorage {
        let settings = TraceSettings(
            saveDirectory: temporaryRoot.path,
            globalShortcut: "command+shift+2",
            defaultCaptureMode: .copyOnly
        )
        let store = SettingsStore(settings: settings)
        return CaptureStorage(settingsStore: store)
    }

    private func testImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 80, height: 40))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 80, height: 40).fill()
        image.unlockFocus()
        return image
    }
}
