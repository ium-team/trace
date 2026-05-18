import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
protocol DeliveryAdapter {
    func supports(_ destination: AppDestination) -> Bool
    func destinations(for destination: AppDestination) -> [AppSpecificDestination]
}

@MainActor
final class DeliveryService {
    private let adapters: [any DeliveryAdapter] = [
        CmuxDeliveryAdapter()
    ]

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

    func windows(for destination: AppDestination) -> [AppWindowDestination] {
        let applicationElement = AXUIElementCreateApplication(destination.application.processIdentifier)
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &rawWindows)
        guard result == .success, let windows = rawWindows as? [AXUIElement] else {
            return []
        }

        return windows.enumerated().map { index, window in
            AppWindowDestination(
                title: windowTitle(for: window, fallbackIndex: index),
                isMain: boolAttribute(kAXMainAttribute as CFString, from: window),
                accessibilityElement: window
            )
        }
        .sorted {
            if $0.isMain != $1.isMain { return $0.isMain && !$1.isMain }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func appSpecificDestinations(for destination: AppDestination) -> [AppSpecificDestination] {
        adapters
            .filter { $0.supports(destination) }
            .flatMap { $0.destinations(for: destination) }
    }

    func deliver(to destination: AppDestination, window: AppWindowDestination?) async throws {
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

        if let window {
            focus(window)
        }

        try await Task.sleep(for: .milliseconds(250))
        guard sendPasteCommand() else {
            throw TraceError.deliveryFailed("붙여넣기 이벤트를 보내지 못했습니다.")
        }
    }

    func deliver(to destination: AppDestination, appSpecificTarget: AppSpecificDestination) async throws {
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

        try await appSpecificTarget.focus()
        try await Task.sleep(for: .milliseconds(250))
        guard sendPasteCommand() else {
            throw TraceError.deliveryFailed("붙여넣기 이벤트를 보내지 못했습니다.")
        }
    }

    private func focus(_ window: AppWindowDestination) {
        AXUIElementSetAttributeValue(window.accessibilityElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window.accessibilityElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.accessibilityElement, kAXRaiseAction as CFString)
    }

    private func windowTitle(for window: AXUIElement, fallbackIndex: Int) -> String {
        var rawTitle: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle)
        if result == .success,
           let title = rawTitle as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return "제목 없는 윈도우 \(fallbackIndex + 1)"
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        return result == .success && (rawValue as? Bool == true)
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
