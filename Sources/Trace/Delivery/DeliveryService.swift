import AppKit
import ApplicationServices
import Carbon
import Foundation
import ScreenCaptureKit

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

    func windows(for destination: AppDestination) async -> [AppWindowDestination] {
        let visibleWindows = sessionWindows(for: destination)
        let accessibilityWindows = accessibilityWindows(for: destination)
        let thumbnails = await windowThumbnails(for: visibleWindows.map(\.windowID))

        var results = visibleWindows.map { visibleWindow in
            let accessibilityElement = visibleWindow.accessibilityElement
                ?? accessibilityWindows.first(where: { $0.title == visibleWindow.title })?.accessibilityElement
            return AppWindowDestination(
                title: visibleWindow.title,
                isMain: accessibilityElement.map {
                    boolAttribute(kAXMainAttribute as CFString, from: $0)
                } ?? false,
                accessibilityElement: accessibilityElement,
                windowID: visibleWindow.windowID,
                thumbnail: thumbnails[visibleWindow.windowID]
            )
        }

        let existingTitles = Set(results.map(\.title))
        let hiddenAccessibilityWindows = accessibilityWindows.filter { !existingTitles.contains($0.title) }
        results.append(contentsOf: hiddenAccessibilityWindows)

        return results.sorted {
            if $0.isMain != $1.isMain { return $0.isMain && !$1.isMain }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func accessibilityWindows(for destination: AppDestination) -> [AppWindowDestination] {
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
                accessibilityElement: window,
                windowID: nil,
                thumbnail: nil
            )
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
        guard let accessibilityElement = window.accessibilityElement else { return }
        AXUIElementSetAttributeValue(accessibilityElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(accessibilityElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(accessibilityElement, kAXRaiseAction as CFString)
    }

    private func sessionWindows(for destination: AppDestination) -> [VisibleWindow] {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else {
            return []
        }

        let targetPID = destination.application.processIdentifier
        return rawWindows.compactMap { rawWindow in
            guard let ownerPID = rawWindow[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == targetPID,
                  let layer = rawWindow[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowNumber = rawWindow[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = rawWindow[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let rawTitle = (rawWindow[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTitle = rawTitle?.isEmpty == false
            guard hasTitle || shouldKeepUntitledWindow(rawWindow, bounds: bounds) else {
                return nil
            }
            let title = hasTitle ? rawTitle! : "제목 없는 윈도우"

            return VisibleWindow(
                title: title,
                windowID: CGWindowID(windowNumber.uint32Value),
                accessibilityElement: isOnScreen(rawWindow)
                    ? accessibilityWindow(at: CGPoint(x: bounds.midX, y: bounds.midY))
                    : nil
            )
        }
    }

    private func windowThumbnails(for windowIDs: [CGWindowID]) async -> [CGWindowID: NSImage] {
        guard PermissionService.hasScreenRecordingPermission,
              !windowIDs.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else {
            return [:]
        }

        let windowsByID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        var thumbnails: [CGWindowID: NSImage] = [:]
        for windowID in windowIDs {
            guard let window = windowsByID[windowID],
                  let image = try? await thumbnail(for: window)
            else {
                continue
            }
            thumbnails[windowID] = image
        }
        return thumbnails
    }

    private func thumbnail(for window: SCWindow) async throws -> NSImage {
        let configuration = SCStreamConfiguration()
        configuration.width = 240
        configuration.height = 150
        configuration.scalesToFit = true
        configuration.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func isOnScreen(_ rawWindow: [String: Any]) -> Bool {
        rawWindow[kCGWindowIsOnscreen as String] as? Bool == true
    }

    private func shouldKeepUntitledWindow(_ rawWindow: [String: Any], bounds: CGRect) -> Bool {
        let alpha = rawWindow[kCGWindowAlpha as String] as? CGFloat ?? 1
        let hasUsefulSize = bounds.width >= 160 && bounds.height >= 120
        let isVisibleEnough = alpha >= 0.1
        return hasUsefulSize && isVisibleEnough
    }

    private func accessibilityWindow(at point: CGPoint) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let hitTestResult = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &element
        )
        guard hitTestResult == .success, let element else { return nil }

        var rawWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &rawWindow)
        guard windowResult == .success, let window = rawWindow else { return nil }
        return (window as! AXUIElement)
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

private struct VisibleWindow {
    var title: String
    var windowID: CGWindowID
    var accessibilityElement: AXUIElement?
}
