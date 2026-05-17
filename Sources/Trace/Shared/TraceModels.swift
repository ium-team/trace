import AppKit
import Foundation

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case copyOnly
    case deliverToApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copyOnly:
            "복사만 하기"
        case .deliverToApp:
            "앱으로 자동 전달"
        }
    }
}

enum CaptureScope: String, CaseIterable, Identifiable {
    case area
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area:
            "영역"
        case .fullScreen:
            "전체 화면"
        }
    }
}

struct CapturePlan: Identifiable, Hashable {
    var mode: CaptureMode
    var scope: CaptureScope

    var id: String { "\(scope.rawValue)-\(mode.rawValue)" }

    var title: String {
        switch (scope, mode) {
        case (.area, .copyOnly):
            "영역 캡처"
        case (.fullScreen, .copyOnly):
            "전체 화면 캡처"
        case (.area, .deliverToApp):
            "영역 캡처 후 앱으로 전달"
        case (.fullScreen, .deliverToApp):
            "전체 화면 캡처 후 앱으로 전달"
        }
    }

    var description: String {
        switch (scope, mode) {
        case (.area, .copyOnly):
            "드래그한 영역을 저장하고 클립보드에 복사합니다."
        case (.fullScreen, .copyOnly):
            "주 디스플레이 전체를 저장하고 클립보드에 복사합니다."
        case (.area, .deliverToApp):
            "드래그한 영역을 저장한 뒤 전달할 앱을 선택합니다."
        case (.fullScreen, .deliverToApp):
            "주 디스플레이 전체를 저장한 뒤 전달할 앱을 선택합니다."
        }
    }

    var symbolName: String {
        switch (scope, mode) {
        case (.area, .copyOnly):
            "crop"
        case (.fullScreen, .copyOnly):
            "rectangle.inset.filled"
        case (.area, .deliverToApp):
            "arrow.up.right.square"
        case (.fullScreen, .deliverToApp):
            "rectangle.portrait.and.arrow.right"
        }
    }

    static let areaCopy = CapturePlan(mode: .copyOnly, scope: .area)
    static let fullScreenCopy = CapturePlan(mode: .copyOnly, scope: .fullScreen)
    static let areaDelivery = CapturePlan(mode: .deliverToApp, scope: .area)
    static let fullScreenDelivery = CapturePlan(mode: .deliverToApp, scope: .fullScreen)

    static let all: [CapturePlan] = [
        .areaCopy,
        .fullScreenCopy,
        .areaDelivery,
        .fullScreenDelivery
    ]
}

enum DeliveryState: String, Codable, CaseIterable {
    case none
    case skipped
    case delivered
    case failed

    var title: String {
        switch self {
        case .none:
            "전달 없음"
        case .skipped:
            "건너뜀"
        case .delivered:
            "전달 완료"
        case .failed:
            "전달 실패"
        }
    }
}

struct CaptureItem: Identifiable, Codable, Hashable {
    var id: String
    var filePath: String
    var thumbnailPath: String?
    var createdAt: Date
    var width: Int
    var height: Int
    var captureMode: CaptureMode
    var deliveredAppName: String?
    var deliveryState: DeliveryState
}

struct CaptureMetadata: Codable {
    var captures: [CaptureItem]

    static let empty = CaptureMetadata(captures: [])
}

struct TraceSettings: Codable, Equatable {
    var saveDirectory: String
    var globalShortcut: String
    var defaultCaptureMode: CaptureMode
    var showSaveNotification: Bool

    static var defaultSaveDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Trace", isDirectory: true)
            .path
    }

    static let defaults = TraceSettings(
        saveDirectory: defaultSaveDirectory,
        globalShortcut: "command+shift+2",
        defaultCaptureMode: .copyOnly,
        showSaveNotification: true
    )
}

struct CaptureResult {
    var image: NSImage
    var pixelWidth: Int
    var pixelHeight: Int

    init(image: NSImage) {
        self.image = image

        if let representation = image.representations.first {
            pixelWidth = representation.pixelsWide
            pixelHeight = representation.pixelsHigh
        } else {
            pixelWidth = Int(image.size.width)
            pixelHeight = Int(image.size.height)
        }
    }
}

struct SavedCapture {
    var item: CaptureItem
    var fileURL: URL
    var thumbnailURL: URL?
}

struct AppDestination: Identifiable, Hashable {
    var id: String { bundleIdentifier ?? name }
    var bundleIdentifier: String?
    var name: String
    var icon: NSImage
    var isActive: Bool
    var application: NSRunningApplication
}

enum TraceError: LocalizedError {
    case screenRecordingRequired
    case captureCancelled
    case captureFailed
    case captureFailedReason(String)
    case imageEncodingFailed
    case pasteboardFailed
    case accessibilityRequired
    case deliveryFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingRequired:
            "화면 캡처 권한이 필요합니다."
        case .captureCancelled:
            "캡처가 취소되었습니다."
        case .captureFailed:
            "선택한 영역을 캡처하지 못했습니다."
        case .captureFailedReason(let message):
            message
        case .imageEncodingFailed:
            "이미지를 PNG로 변환하지 못했습니다."
        case .pasteboardFailed:
            "클립보드에 이미지를 복사하지 못했습니다."
        case .accessibilityRequired:
            "앱으로 자동 전달하려면 손쉬운 사용 권한이 필요합니다."
        case .deliveryFailed(let message):
            message
        case .saveFailed(let message):
            message
        }
    }
}
