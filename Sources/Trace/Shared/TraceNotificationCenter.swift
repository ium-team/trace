import Foundation
import UserNotifications

@MainActor
final class TraceNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TraceNotificationCenter()

    static func configure() {
        UNUserNotificationCenter.current().delegate = shared
    }

    static func requestIfNeeded(enabled: Bool) {
        guard enabled else { return }
        configure()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func requestAuthorization() async -> Bool {
        configure()
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("Trace notification authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    static func showSaved(fileURL: URL, folderName: String, enabled: Bool) {
        guard enabled else { return }
        post(title: "캡처 저장 완료", body: "\(folderName) 폴더에 저장됨")
    }

    static func showDeliveryCompleted(appName: String, enabled: Bool) {
        guard enabled else { return }
        post(title: "전달 완료", body: "\(appName)에 붙여넣기 이벤트를 보냈습니다.")
    }

    static func showDeliveryFailed(appName: String, message: String, enabled: Bool) {
        guard enabled else { return }
        post(title: "전달 실패", body: "\(appName): \(message)")
    }

    static func showFailure(_ message: String, enabled: Bool) {
        guard enabled else { return }
        post(title: "Trace", body: message)
    }

    private static func post(title: String, body: String) {
        configure()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
