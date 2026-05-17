import AppKit
import Foundation

@MainActor
final class SystemCaptureController {
    private enum ProcessResult: Sendable {
        case captured(String)
        case cancelled
        case failed(String)
    }

    private var activeTask: Task<Void, Never>?

    func start(completion: @escaping (Result<CaptureResult, Error>) -> Void) {
        guard activeTask == nil else { return }

        let tempURL = Self.temporaryCaptureURL()
        activeTask = Task { [weak self] in
            let processResult = await Self.runScreencapture(outputURL: tempURL)
            guard !Task.isCancelled else { return }

            let result = Self.makeCaptureResult(from: processResult)
            completion(result)
            self?.activeTask = nil
        }
    }

    private static func temporaryCaptureURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Trace", isDirectory: true)
            .appendingPathComponent("Capture-\(UUID().uuidString).png")
    }

    private static func runScreencapture(outputURL: URL) async -> ProcessResult {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: outputURL.path) {
                    try fileManager.removeItem(at: outputURL)
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-s", "-x", "-t", "png", outputURL.path]

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    try? fileManager.removeItem(at: outputURL)
                    return .cancelled
                }

                guard fileManager.fileExists(atPath: outputURL.path) else {
                    return .cancelled
                }

                let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
                let fileSize = attributes[.size] as? NSNumber
                guard (fileSize?.intValue ?? 0) > 0 else {
                    try? fileManager.removeItem(at: outputURL)
                    return .cancelled
                }

                return .captured(outputURL.path)
            } catch {
                try? fileManager.removeItem(at: outputURL)
                return .failed(error.localizedDescription)
            }
        }.value
    }

    private static func makeCaptureResult(from processResult: ProcessResult) -> Result<CaptureResult, Error> {
        switch processResult {
        case .captured(let path):
            let url = URL(fileURLWithPath: path)
            guard let image = NSImage(contentsOf: url) else {
                try? FileManager.default.removeItem(at: url)
                return .failure(TraceError.captureFailedReason("macOS 기본 캡처 결과 파일을 읽지 못했습니다."))
            }
            return .success(CaptureResult(image: image, sourceURL: url))
        case .cancelled:
            return .failure(TraceError.captureCancelled)
        case .failed(let message):
            return .failure(TraceError.captureFailedReason("macOS 기본 캡처 도구 실행에 실패했습니다. \(message)"))
        }
    }
}
