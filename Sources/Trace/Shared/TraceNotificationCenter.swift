import Foundation
import UserNotifications

enum TraceNotificationCenter {
    static func requestIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func showSaved(fileURL: URL, folderName: String, enabled: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "캡처 저장 완료"
        content.body = "\(folderName) 폴더에 저장됨"
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func showDeliveryCompleted(appName: String, enabled: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "전달 완료"
        content.body = "\(appName)에 붙여넣기 이벤트를 보냈습니다."
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func showDeliveryFailed(appName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "전달 실패"
        content.body = "\(appName): \(message)"
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func showFailure(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Trace"
        content.body = message
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
