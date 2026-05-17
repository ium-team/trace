import AppKit
import Carbon
import Foundation

@MainActor
final class DeliveryService {
    func runningApps() -> [AppDestination] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != ownPID &&
                app.activationPolicy == .regular &&
                !(app.localizedName ?? "").isEmpty
            }
            .map { app in
                AppDestination(
                    bundleIdentifier: app.bundleIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                    icon: app.icon ?? NSImage(size: NSSize(width: 32, height: 32)),
                    isActive: app.isActive,
                    application: app
                )
            }
            .sorted {
                if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func deliver(to destination: AppDestination) async throws {
        guard PermissionService.hasAccessibilityPermission else {
            throw TraceError.accessibilityRequired
        }

        guard !destination.application.isTerminated else {
            throw TraceError.deliveryFailed("대상 앱이 이미 종료되었습니다.")
        }

        let activated = destination.application.activate(options: [.activateAllWindows])
        guard activated else {
            throw TraceError.deliveryFailed("\(destination.name)을 활성화하지 못했습니다.")
        }

        try await Task.sleep(for: .milliseconds(250))
        guard sendPasteCommand() else {
            throw TraceError.deliveryFailed("붙여넣기 이벤트를 보내지 못했습니다.")
        }
    }

    private func sendPasteCommand() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
