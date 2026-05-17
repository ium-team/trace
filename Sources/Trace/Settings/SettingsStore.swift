import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private let fileManager: FileManager
    private(set) var settings: TraceSettings

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.settings = Self.load(fileManager: fileManager)
    }

    init(settings: TraceSettings, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.settings = settings
    }

    var rootURL: URL {
        URL(fileURLWithPath: settings.saveDirectory).standardizedFileURL
    }

    func update(_ newSettings: TraceSettings) {
        settings = newSettings
        save()
    }

    func save() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.trace.encode(settings)
            try AtomicFileWriter.write(data, to: Self.settingsURL(rootURL: rootURL))
        } catch {
            NSLog("Trace settings save failed: \(error.localizedDescription)")
        }
    }

    private static func load(fileManager: FileManager) -> TraceSettings {
        let defaultRoot = URL(fileURLWithPath: TraceSettings.defaultSaveDirectory)
        let defaultURL = settingsURL(rootURL: defaultRoot)

        guard let data = try? Data(contentsOf: defaultURL),
              let settings = try? JSONDecoder.trace.decode(TraceSettings.self, from: data)
        else {
            let defaults = TraceSettings.defaults
            try? fileManager.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
            if let data = try? JSONEncoder.trace.encode(defaults) {
                try? AtomicFileWriter.write(data, to: defaultURL)
            }
            return defaults
        }

        return settings
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
