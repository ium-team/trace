import AppKit
import Foundation

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case copyOnly
    case deliverToApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copyOnly:
            "기본 캡처"
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
            "드래그한 영역을 설정에 따라 저장하거나 자동 복사합니다."
        case (.fullScreen, .copyOnly):
            "현재 디스플레이 전체를 설정에 따라 저장하거나 자동 복사합니다."
        case (.area, .deliverToApp):
            "드래그한 영역을 캡처한 뒤 전달할 앱을 선택합니다."
        case (.fullScreen, .deliverToApp):
            "현재 디스플레이 전체를 캡처한 뒤 전달할 앱을 선택합니다."
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
    var title: String?
    var filePath: String
    var thumbnailPath: String?
    var createdAt: Date
    var width: Int
    var height: Int
    var captureMode: CaptureMode
    var deliveredAppName: String?
    var deliveryState: DeliveryState
    var isPinned: Bool
    var isBookmarked: Bool

    var displayTitle: String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        }
        return title
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case filePath
        case thumbnailPath
        case createdAt
        case width
        case height
        case captureMode
        case deliveredAppName
        case deliveryState
        case isPinned
        case isBookmarked
    }

    init(
        id: String,
        title: String? = nil,
        filePath: String,
        thumbnailPath: String?,
        createdAt: Date,
        width: Int,
        height: Int,
        captureMode: CaptureMode,
        deliveredAppName: String?,
        deliveryState: DeliveryState,
        isPinned: Bool = false,
        isBookmarked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.captureMode = captureMode
        self.deliveredAppName = deliveredAppName
        self.deliveryState = deliveryState
        self.isPinned = isPinned
        self.isBookmarked = isBookmarked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        filePath = try container.decode(String.self, forKey: .filePath)
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        captureMode = try container.decode(CaptureMode.self, forKey: .captureMode)
        deliveredAppName = try container.decodeIfPresent(String.self, forKey: .deliveredAppName)
        deliveryState = try container.decode(DeliveryState.self, forKey: .deliveryState)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
    }
}

struct CaptureMetadata: Codable {
    var captures: [CaptureItem]

    static let empty = CaptureMetadata(captures: [])
}

struct TraceSettings: Codable, Equatable {
    enum BasicCaptureAction: String, Codable, CaseIterable, Identifiable {
        case copyAndSave
        case copyOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .copyAndSave:
                "저장"
            case .copyOnly:
                "저장 안 함"
            }
        }
    }

    enum DeliveryCaptureAction: String, Codable, CaseIterable, Identifiable {
        case copyAndDeliver
        case copySaveAndDeliver

        var id: String { rawValue }

        var title: String {
            switch self {
            case .copyAndDeliver:
                "전달"
            case .copySaveAndDeliver:
                "저장 및 전달"
            }
        }
    }

    enum DeliveryTargetMode: String, Codable, CaseIterable, Identifiable {
        case chooseEachTime
        case mostRecentApp
        case fixedApp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chooseEachTime:
                "매번 앱 선택"
            case .mostRecentApp:
                "가장 최근 사용 앱"
            case .fixedApp:
                "지정한 앱"
            }
        }
    }

    enum FixedAppWindowMode: String, Codable, CaseIterable, Identifiable {
        case mostRecentWindow
        case chooseWindow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mostRecentWindow:
                "가장 최근 사용 윈도우"
            case .chooseWindow:
                "윈도우 선택"
            }
        }
    }

    enum FileNameRule: String, Codable, CaseIterable, Identifiable {
        case dateTime
        case sequence

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateTime:
                "날짜/시간"
            case .sequence:
                "순서"
            }
        }
    }

    enum DateFileNameFormat: String, Codable, CaseIterable, Identifiable {
        case yearMonthDayHourMinuteSecond
        case yearMonthDayHourMinute
        case yearMonthDay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .yearMonthDayHourMinuteSecond:
                "YYYY-MM-DD_HH-mm-ss"
            case .yearMonthDayHourMinute:
                "YYYY-MM-DD_HH-mm"
            case .yearMonthDay:
                "YYYY-MM-DD"
            }
        }

        var pattern: String {
            switch self {
            case .yearMonthDayHourMinuteSecond:
                "yyyy-MM-dd_HH-mm-ss"
            case .yearMonthDayHourMinute:
                "yyyy-MM-dd_HH-mm"
            case .yearMonthDay:
                "yyyy-MM-dd"
            }
        }
    }

    enum SequenceStyle: String, Codable, CaseIterable, Identifiable {
        case koreanAlphabet
        case numeric

        var id: String { rawValue }

        var title: String {
            switch self {
            case .koreanAlphabet:
                "가, 나, 다"
            case .numeric:
                "001, 002, 003"
            }
        }
    }

    var saveDirectory: String
    var globalShortcut: String
    var copyToClipboardByDefault: Bool
    var basicCaptureShortcut: String
    var deliveryCaptureShortcut: String
    var basicCaptureAction: BasicCaptureAction
    var deliveryCaptureAction: DeliveryCaptureAction
    var deliveryTargetMode: DeliveryTargetMode
    var fixedDeliveryAppBundleIdentifier: String?
    var fixedDeliveryAppName: String?
    var fixedDeliveryAppWindowMode: FixedAppWindowMode
    var fileNameRule: FileNameRule
    var dateFileNameFormat: DateFileNameFormat
    var sequenceStyle: SequenceStyle

    static var defaultSaveDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Trace", isDirectory: true)
            .path
    }

    static let defaults = TraceSettings(
        saveDirectory: defaultSaveDirectory,
        globalShortcut: "command+shift+2",
        copyToClipboardByDefault: true,
        basicCaptureShortcut: "command+shift+2",
        deliveryCaptureShortcut: "command+shift+3",
        basicCaptureAction: .copyAndSave,
        deliveryCaptureAction: .copySaveAndDeliver,
        deliveryTargetMode: .chooseEachTime,
        fixedDeliveryAppBundleIdentifier: nil,
        fixedDeliveryAppName: nil,
        fixedDeliveryAppWindowMode: .mostRecentWindow,
        fileNameRule: .dateTime,
        dateFileNameFormat: .yearMonthDayHourMinuteSecond,
        sequenceStyle: .numeric
    )

    private enum CodingKeys: String, CodingKey {
        case saveDirectory
        case globalShortcut
        case copyToClipboardByDefault
        case basicCaptureShortcut
        case deliveryCaptureShortcut
        case basicCaptureAction
        case deliveryCaptureAction
        case deliveryTargetMode
        case fixedDeliveryAppBundleIdentifier
        case fixedDeliveryAppName
        case fixedDeliveryAppWindowMode
        case fileNameRule
        case dateFileNameFormat
        case sequenceStyle
    }

    init(
        saveDirectory: String,
        globalShortcut: String,
        copyToClipboardByDefault: Bool = true,
        basicCaptureShortcut: String? = nil,
        deliveryCaptureShortcut: String = "command+shift+3",
        basicCaptureAction: BasicCaptureAction = .copyAndSave,
        deliveryCaptureAction: DeliveryCaptureAction = .copySaveAndDeliver,
        deliveryTargetMode: DeliveryTargetMode = .chooseEachTime,
        fixedDeliveryAppBundleIdentifier: String? = nil,
        fixedDeliveryAppName: String? = nil,
        fixedDeliveryAppWindowMode: FixedAppWindowMode = .mostRecentWindow,
        fileNameRule: FileNameRule = .dateTime,
        dateFileNameFormat: DateFileNameFormat = .yearMonthDayHourMinuteSecond,
        sequenceStyle: SequenceStyle = .numeric
    ) {
        self.saveDirectory = saveDirectory
        self.globalShortcut = globalShortcut
        self.copyToClipboardByDefault = copyToClipboardByDefault
        self.basicCaptureShortcut = basicCaptureShortcut ?? globalShortcut
        self.deliveryCaptureShortcut = deliveryCaptureShortcut
        self.basicCaptureAction = basicCaptureAction
        self.deliveryCaptureAction = deliveryCaptureAction
        self.deliveryTargetMode = deliveryTargetMode
        self.fixedDeliveryAppBundleIdentifier = fixedDeliveryAppBundleIdentifier
        self.fixedDeliveryAppName = fixedDeliveryAppName
        self.fixedDeliveryAppWindowMode = fixedDeliveryAppWindowMode
        self.fileNameRule = fileNameRule
        self.dateFileNameFormat = dateFileNameFormat
        self.sequenceStyle = sequenceStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        saveDirectory = try container.decode(String.self, forKey: .saveDirectory)
        globalShortcut = try container.decode(String.self, forKey: .globalShortcut)
        copyToClipboardByDefault = try container.decodeIfPresent(Bool.self, forKey: .copyToClipboardByDefault) ?? true
        basicCaptureShortcut = try container.decodeIfPresent(String.self, forKey: .basicCaptureShortcut) ?? globalShortcut
        deliveryCaptureShortcut = try container.decodeIfPresent(String.self, forKey: .deliveryCaptureShortcut) ?? "command+shift+3"
        basicCaptureAction = try container.decodeIfPresent(BasicCaptureAction.self, forKey: .basicCaptureAction) ?? .copyAndSave
        deliveryCaptureAction = try container.decodeIfPresent(DeliveryCaptureAction.self, forKey: .deliveryCaptureAction) ?? .copySaveAndDeliver
        deliveryTargetMode = try container.decodeIfPresent(DeliveryTargetMode.self, forKey: .deliveryTargetMode) ?? .chooseEachTime
        fixedDeliveryAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .fixedDeliveryAppBundleIdentifier)
        fixedDeliveryAppName = try container.decodeIfPresent(String.self, forKey: .fixedDeliveryAppName)
        fixedDeliveryAppWindowMode = try container.decodeIfPresent(FixedAppWindowMode.self, forKey: .fixedDeliveryAppWindowMode) ?? .mostRecentWindow
        fileNameRule = try container.decodeIfPresent(FileNameRule.self, forKey: .fileNameRule) ?? .dateTime
        dateFileNameFormat = try container.decodeIfPresent(DateFileNameFormat.self, forKey: .dateFileNameFormat) ?? .yearMonthDayHourMinuteSecond
        sequenceStyle = try container.decodeIfPresent(SequenceStyle.self, forKey: .sequenceStyle) ?? .numeric
    }
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

struct InteractiveCaptureResult {
    var capture: CaptureResult
    var plan: CapturePlan
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

struct AppWindowDestination: Identifiable {
    let id = UUID()
    var title: String
    var isMain: Bool
    var accessibilityElement: AXUIElement?
    var windowID: CGWindowID?
    var thumbnail: NSImage?
}

struct AppSpecificDestination: Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var focus: @MainActor () async throws -> Void
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
    case invalidCaptureName

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
        case .invalidCaptureName:
            "사용할 수 있는 캡처 이름을 입력하세요."
        }
    }
}
