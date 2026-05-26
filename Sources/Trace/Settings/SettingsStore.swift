import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private static let selectedSaveDirectoryKey = "Trace.selectedSaveDirectory"

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private(set) var settings: TraceSettings
    @ObservationIgnored var onUpdate: ((TraceSettings) -> Void)?

    init(fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.settings = Self.load(fileManager: fileManager, userDefaults: userDefaults)
    }

    init(settings: TraceSettings, fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.settings = settings
    }

    var rootURL: URL {
        URL(fileURLWithPath: settings.saveDirectory).standardizedFileURL
    }

    func update(_ newSettings: TraceSettings) {
        var normalized = newSettings
        normalized.globalShortcut = normalized.basicCaptureShortcut
        settings = normalized
        save()
        onUpdate?(normalized)
    }

    func save() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.trace.encode(settings)
            try AtomicFileWriter.write(data, to: Self.settingsURL(rootURL: rootURL))
            userDefaults.set(settings.saveDirectory, forKey: Self.selectedSaveDirectoryKey)
        } catch {
            NSLog("Trace settings save failed: \(error.localizedDescription)")
        }
    }

    private static func load(fileManager: FileManager, userDefaults: UserDefaults) -> TraceSettings {
        let defaultRoot = URL(fileURLWithPath: TraceSettings.defaultSaveDirectory)
        let selectedRoot = userDefaults.string(forKey: selectedSaveDirectoryKey)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        let candidateURLs = [selectedRoot, defaultRoot]
            .compactMap { $0 }
            .map { settingsURL(rootURL: $0) }

        for url in candidateURLs {
            if let data = try? Data(contentsOf: url),
               let settings = try? JSONDecoder.trace.decode(TraceSettings.self, from: data) {
                return settings
            }
        }

        let defaults = TraceSettings.defaults
        try? fileManager.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.trace.encode(defaults) {
            try? AtomicFileWriter.write(data, to: settingsURL(rootURL: defaultRoot))
        }
        return defaults
    }

    private static func settingsURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent("settings.json")
    }
}

extension JSONEncoder {
    static var trace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var trace: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum AtomicFileWriter {
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }
}
