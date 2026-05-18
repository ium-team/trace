import AppKit
import Foundation
import UserNotifications

@MainActor
final class TraceNotificationCenter: NSObject, UNUserNotificationCenterDelegate, NSUserNotificationCenterDelegate {
    static let shared = TraceNotificationCenter()

    static func requestIfNeeded(enabled: Bool) {
        guard enabled else { return }
        UNUserNotificationCenter.current().delegate = shared
        NSUserNotificationCenter.default.delegate = shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func showSaved(fileURL: URL, folderName: String, enabled: Bool) {
        guard enabled else { return }
        show(title: "캡처 저장 완료", body: "\(folderName) 폴더에 저장됨")
    }

    static func showDeliveryCompleted(appName: String, enabled: Bool) {
        guard enabled else { return }
        show(title: "전달 완료", body: "\(appName)에 붙여넣기 이벤트를 보냈습니다.")
    }

    static func showDeliveryFailed(appName: String, message: String, enabled: Bool) {
        guard enabled else { return }
        show(title: "전달 실패", body: "\(appName): \(message)")
    }

    static func showFailure(_ message: String, enabled: Bool) {
        guard enabled else { return }
        show(title: "Trace", body: message)
    }

    private static func show(title: String, body: String) {
        NSUserNotificationCenter.default.delegate = shared

        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = nil
        NSUserNotificationCenter.default.deliver(notification)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }
}
