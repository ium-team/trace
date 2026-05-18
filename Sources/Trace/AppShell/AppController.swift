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
        settingsStore.onUpdate = { [weak self] _ in
            self?.registerHotKeys()
        }
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
        hotKeyManager.register(
            copyShortcut: settingsStore.settings.basicCaptureShortcut,
            deliveryShortcut: settingsStore.settings.deliveryCaptureShortcut,
            copyAction: { [weak self] in
                Task { @MainActor in self?.startInteractiveCapture(defaultPlan: .areaCopy) }
            },
            deliverAction: { [weak self] in
                Task { @MainActor in self?.startInteractiveCapture(defaultPlan: .areaDelivery) }
            }
        )
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
            requestScreenRecordingPermissionForCapture(defaultPlan: plan)
            return
        }

        performInteractiveCapture(defaultPlan: plan)
    }

    private func requestScreenRecordingPermissionForCapture(defaultPlan: CapturePlan) {
        _ = PermissionService.requestScreenRecordingPermission()

        guard PermissionService.hasScreenRecordingPermission else {
            presentPermissionAlert(.screenRecording) { [weak self] action in
                guard let self else { return }
                switch action {
                case .openSettings:
                    PermissionService.openScreenRecordingSettings()
                case .retry:
                    if PermissionService.hasScreenRecordingPermission {
                        self.performInteractiveCapture(defaultPlan: defaultPlan)
                    } else {
                        self.requestScreenRecordingPermissionForCapture(defaultPlan: defaultPlan)
                    }
                case .cancel:
                    break
                }
            }
            return
        }

        performInteractiveCapture(defaultPlan: defaultPlan)
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
                try ClipboardService.copy(image: capture.image)

                let saved = try saveIfNeeded(capture: capture, mode: mode)

                if mode == .deliverToApp {
                    guard prepareAccessibilityForDelivery(saved: saved) else {
                        return
                    }
                    presentDestinationPicker(for: saved)
                } else if saved != nil {
                    openHistory()
                } else {
                    TraceNotificationCenter.showCopied(enabled: true)
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

    private func saveIfNeeded(capture: CaptureResult, mode: CaptureMode) throws -> SavedCapture? {
        let shouldSave = switch mode {
        case .copyOnly:
            settingsStore.settings.basicCaptureAction == .copyAndSave
        case .deliverToApp:
            settingsStore.settings.deliveryCaptureAction == .copySaveAndDeliver
        }

        guard shouldSave else {
            return nil
        }

        let saved = try storage.save(capture: capture, mode: mode)
        TraceNotificationCenter.showSaved(
            fileURL: saved.fileURL,
            folderName: TraceDateFormatters.folder.string(from: saved.item.createdAt),
            enabled: true
        )
        return saved
    }

    private func presentDestinationPicker(for saved: SavedCapture?) {
        let destinations = deliveryService.runningApps()
        let view = DestinationPickerView(
            destinations: destinations,
            onSkip: { [weak self] in
                if let saved {
                    self?.storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .skipped)
                }
                self?.destinationWindow?.close()
                if saved != nil {
                    self?.openHistory()
                }
            },
            onSelect: { [weak self] destination in
                Task { @MainActor in
                    await self?.presentWindowPicker(for: saved, destination: destination)
                }
            }
        )

        destinationWindow = makeWindow(title: "전달 대상 선택", size: NSSize(width: 420, height: 520), rootView: view)
        showWindow(destinationWindow, minimumSize: NSSize(width: 420, height: 520))
    }

    private func presentWindowPicker(for saved: SavedCapture?, destination: AppDestination) async {
        let windows = await deliveryService.windows(for: destination)
        let appSpecificDestinations = deliveryService.appSpecificDestinations(for: destination)
        let view = WindowPickerView(
            app: destination,
            windows: windows,
            appSpecificDestinations: appSpecificDestinations,
            onBack: { [weak self] in
                self?.presentDestinationPicker(for: saved)
            },
            onSkip: { [weak self] in
                if let saved {
                    self?.storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .skipped)
                }
                self?.destinationWindow?.close()
                if saved != nil {
                    self?.openHistory()
                }
            },
            onSelectWindow: { [weak self] window in
                Task { @MainActor in
                    await self?.deliver(saved: saved, to: destination, window: window)
                }
            },
            onSelectAppSpecificDestination: { [weak self] appSpecificDestination in
                Task { @MainActor in
                    await self?.deliver(saved: saved, to: destination, appSpecificTarget: appSpecificDestination)
                }
            }
        )

        destinationWindow?.contentViewController = NSHostingController(rootView: view)
        showWindow(destinationWindow, minimumSize: NSSize(width: 420, height: 520))
    }

    private func prepareAccessibilityForDelivery(saved: SavedCapture?) -> Bool {
        guard !PermissionService.hasAccessibilityPermission else {
            return true
        }

        PermissionService.requestAccessibilityPermission()

        if PermissionService.hasAccessibilityPermission {
            return true
        }

        var canDeliver = false
        presentPermissionAlert(.accessibility) { [weak self] action in
            guard let self else { return }
            switch action {
            case .openSettings:
                PermissionService.openAccessibilitySettings()
                self.markDeliveryFailed(saved: saved)
            case .retry:
                if PermissionService.hasAccessibilityPermission {
                    canDeliver = true
                } else {
                    PermissionService.requestAccessibilityPermission()
                    self.markDeliveryFailed(saved: saved)
                }
            case .cancel:
                self.markDeliveryFailed(saved: saved)
            }
        }
        return canDeliver
    }

    private func markDeliveryFailed(saved: SavedCapture?) {
        guard let saved else { return }
        storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .failed)
        openHistory()
    }

    private func deliver(saved: SavedCapture?, to destination: AppDestination, window: AppWindowDestination) async {
        destinationWindow?.close()
        do {
            try await deliveryService.deliver(to: destination, window: window)
            if let saved {
                storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .delivered)
            }
            TraceNotificationCenter.showDeliveryCompleted(
                appName: destination.name,
                enabled: true
            )
        } catch {
            if let saved {
                storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .failed)
            }
            if case TraceError.accessibilityRequired = error {
                PermissionService.requestAccessibilityPermission()
            } else {
                TraceNotificationCenter.showDeliveryFailed(
                    appName: destination.name,
                    message: error.localizedDescription,
                    enabled: true
                )
            }
            if saved != nil {
                openHistory()
            }
        }
    }

    private func deliver(saved: SavedCapture?, to destination: AppDestination, appSpecificTarget: AppSpecificDestination) async {
        destinationWindow?.close()
        do {
            try await deliveryService.deliver(to: destination, appSpecificTarget: appSpecificTarget)
            if let saved {
                storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .delivered)
            }
            TraceNotificationCenter.showDeliveryCompleted(
                appName: destination.name,
                enabled: true
            )
        } catch {
            if let saved {
                storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .failed)
            }
            if case TraceError.accessibilityRequired = error {
                PermissionService.requestAccessibilityPermission()
            } else {
                TraceNotificationCenter.showDeliveryFailed(
                    appName: destination.name,
                    message: error.localizedDescription,
                    enabled: true
                )
            }
            if saved != nil {
                openHistory()
            }
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

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Trace 오류"
        alert.informativeText = message
        alert.runModal()
        TraceNotificationCenter.showFailure(message, enabled: true)
    }

    private func presentPermissionAlert(
        _ permission: PermissionAlertKind,
        completion: (PermissionAlertAction) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = permission.title
        alert.informativeText = permission.message
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "다시 확인")
        alert.addButton(withTitle: "취소")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            completion(.openSettings)
        case .alertSecondButtonReturn:
            completion(.retry)
        default:
            completion(.cancel)
        }
    }
}

private enum PermissionAlertKind {
    case screenRecording
    case accessibility

    var title: String {
        switch self {
        case .screenRecording:
            "화면 캡처 권한이 필요합니다."
        case .accessibility:
            "손쉬운 사용 권한이 필요합니다."
        }
    }

    var message: String {
        switch self {
        case .screenRecording:
            """
            Trace가 선택한 영역을 이미지로 저장하려면 Screen Recording 권한이 필요합니다.

            시스템 설정에서 Trace 또는 현재 실행 주체를 허용한 뒤 다시 시도하세요. 권한을 허용한 뒤에도 반영되지 않으면 앱을 재시작해야 할 수 있습니다.
            """
        case .accessibility:
            """
            앱으로 자동 전달하려면 Accessibility 권한이 필요합니다.

            권한이 없으면 캡처는 저장되고 클립보드에는 복사되지만, 대상 앱 활성화와 붙여넣기는 진행하지 않습니다.
            """
        }
    }
}

private enum PermissionAlertAction {
    case openSettings
    case retry
    case cancel
}
