import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum PermissionService {
    static var currentAppIdentityDescription: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "번들 ID 없음"
        let bundlePath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? "실행 파일 경로 없음"
        return """
        현재 실행 중인 앱:
        번들 ID: \(bundleIdentifier)
        앱 경로: \(bundlePath)
        실행 파일: \(executablePath)
        """
    }

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func openSettingsPane(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
