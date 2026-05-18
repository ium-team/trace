import AppKit
import SwiftUI

@MainActor
final class AppController {
    private let settingsStore = SettingsStore()
    private lazy var storage = CaptureStorage(settingsStore: settingsStore)
    private let captureController = CaptureOverlayController()
    private let deliveryService = DeliveryService()
    private let hotKeyManager = HotKeyManager()

    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var destinationWindow: NSWindow?

    func start() {
        settingsStore.save()
        TraceNotificationCenter.configure()
        TraceNotificationCenter.requestIfNeeded(enabled: true)
        configureStatusItem()
        registerHotKeys()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Trace"
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let startCaptureItem = NSMenuItem(title: "캡처 시작", action: #selector(startCaptureFromMenu), keyEquivalent: "")
        startCaptureItem.target = self
        menu.addItem(startCaptureItem)

        let cancelCaptureItem = NSMenuItem(title: "캡처 취소", action: #selector(cancelCaptureFromMenu), keyEquivalent: "")
        cancelCaptureItem.target = self
        menu.addItem(cancelCaptureItem)

        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "히스토리 열기", action: #selector(openHistoryFromMenu), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "설정 열기", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    private func registerHotKeys() {
        hotKeyManager.register(copyAction: { [weak self] in
            Task { @MainActor in self?.startInteractiveCapture(defaultPlan: .areaCopy) }
        }, deliverAction: { [weak self] in
            Task { @MainActor in self?.startInteractiveCapture(defaultPlan: .areaDelivery) }
        })
    }

    @objc private func startCaptureFromMenu() {
        let defaultPlan = settingsStore.settings.defaultCaptureMode == .deliverToApp ? CapturePlan.areaDelivery : .areaCopy
        startInteractiveCapture(defaultPlan: defaultPlan)
    }

    @objc private func cancelCaptureFromMenu() {
        captureController.forceCancelActiveOverlay()
    }

    @objc private func openHistoryFromMenu() {
        openHistory()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    func startInteractiveCapture(defaultPlan: CapturePlan? = nil) {
        let plan = defaultPlan ?? CapturePlan(mode: settingsStore.settings.defaultCaptureMode, scope: .area)
        guard PermissionService.hasScreenRecordingPermission else {
            guard PermissionService.requestScreenRecordingPermission() else {
                return
            }

            performInteractiveCapture(defaultPlan: plan)
            return
        }

        performInteractiveCapture(defaultPlan: plan)
    }

    private func performInteractiveCapture(defaultPlan: CapturePlan) {
        captureController.start(defaultPlan: defaultPlan) { [weak self] result in
            Task { @MainActor in
                await self?.handleInteractiveCaptureResult(result)
            }
        }
    }

    private func handleInteractiveCaptureResult(_ result: Result<InteractiveCaptureResult, Error>) async {
        switch result {
        case .success(let interactiveResult):
            await handleCaptureResult(.success(interactiveResult.capture), mode: interactiveResult.plan.mode)
        case .failure(let error):
            await handleCaptureResult(.failure(error), mode: settingsStore.settings.defaultCaptureMode)
        }
    }

    private func handleCaptureResult(_ result: Result<CaptureResult, Error>, mode: CaptureMode) async {
        switch result {
        case .success(let capture):
            do {
                let saved = try storage.save(capture: capture, mode: mode)
                try ClipboardService.copy(image: capture.image)
                TraceNotificationCenter.showSaved(
                    fileURL: saved.fileURL,
                    folderName: TraceDateFormatters.folder.string(from: saved.item.createdAt),
                    enabled: true
                )

                if mode == .deliverToApp {
                    guard prepareAccessibilityForDelivery(saved: saved) else {
                        return
                    }
                    presentDestinationPicker(for: saved)
                } else {
                    openHistory()
                }
            } catch {
                showError(error.localizedDescription)
            }
        case .failure(let error):
            if case TraceError.captureCancelled = error {
                return
            }
            showError(error.localizedDescription)
        }
    }

    private func presentDestinationPicker(for saved: SavedCapture) {
        let destinations = deliveryService.runningApps()
        let view = DestinationPickerView(
            destinations: destinations,
            onSkip: { [weak self] in
                self?.storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .skipped)
                self?.destinationWindow?.close()
                self?.openHistory()
            },
            onSelect: { [weak self] destination in
                Task { @MainActor in
                    await self?.deliver(saved: saved, to: destination)
                }
            }
        )

        destinationWindow = makeWindow(title: "전달 대상 선택", size: NSSize(width: 420, height: 520), rootView: view)
        showWindow(destinationWindow, minimumSize: NSSize(width: 420, height: 520))
    }

    private func prepareAccessibilityForDelivery(saved: SavedCapture) -> Bool {
        guard !PermissionService.hasAccessibilityPermission else {
            return true
        }

        PermissionService.requestAccessibilityPermission()
        storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .failed)
        showPermissionAlert(
            message: "손쉬운 사용 권한이 필요합니다.",
            info: "앱으로 자동 전달하려면 Trace가 대상 앱을 활성화하고 붙여넣기 이벤트를 보낼 수 있어야 합니다. 권한을 허용한 뒤 다시 앱 전달 캡처를 시작하세요.",
            openAction: PermissionService.openAccessibilitySettings
        )
        openHistory()
        return false
    }

    private func deliver(saved: SavedCapture, to destination: AppDestination) async {
        destinationWindow?.close()
        do {
            try await deliveryService.deliver(to: destination)
            storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .delivered)
            TraceNotificationCenter.showDeliveryCompleted(
                appName: destination.name,
                enabled: true
            )
        } catch {
            storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .failed)
            if case TraceError.accessibilityRequired = error {
                PermissionService.requestAccessibilityPermission()
            } else {
                TraceNotificationCenter.showDeliveryFailed(
                    appName: destination.name,
                    message: error.localizedDescription,
                    enabled: true
                )
            }
            openHistory()
        }
    }

    private func openHistory() {
        storage.reload()
        let view = HistoryView(storage: storage)
        if historyWindow == nil {
            historyWindow = makeWindow(title: "Trace 히스토리", size: NSSize(width: 1080, height: 720), rootView: view)
        } else {
            historyWindow?.contentViewController = NSHostingController(rootView: view)
        }
        showWindow(historyWindow, minimumSize: NSSize(width: 900, height: 620))
    }

    private func openSettings() {
        let view = SettingsView(settingsStore: settingsStore)
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Trace 설정", size: NSSize(width: 680, height: 520), rootView: view)
        } else {
            settingsWindow?.contentViewController = NSHostingController(rootView: view)
        }
        showWindow(settingsWindow, minimumSize: NSSize(width: 620, height: 480))
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = size
        window.contentMinSize = size
        window.setContentSize(size)
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
    }

    private func showWindow(_ window: NSWindow?, minimumSize: NSSize) {
        guard let window else { return }
        window.minSize = minimumSize
        window.contentMinSize = minimumSize

        let contentSize = window.contentLayoutRect.size
        if contentSize.width < minimumSize.width || contentSize.height < minimumSize.height {
            window.setContentSize(
                NSSize(
                    width: max(contentSize.width, minimumSize.width),
                    height: max(contentSize.height, minimumSize.height)
                )
            )
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPermissionAlert(message: String, info: String, openAction: () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        if alert.runModal() == .alertFirstButtonReturn {
            openAction()
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Trace 오류"
        alert.informativeText = message
        alert.runModal()
        TraceNotificationCenter.showFailure(message, enabled: true)
    }
}
