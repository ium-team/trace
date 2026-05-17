import AppKit
import SwiftUI

@MainActor
final class AppController {
    private let settingsStore = SettingsStore()
    private lazy var storage = CaptureStorage(settingsStore: settingsStore)
    private let overlayController = CaptureOverlayController()
    private let deliveryService = DeliveryService()
    private let hotKeyManager = HotKeyManager()

    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var destinationWindow: NSWindow?

    func start() {
        settingsStore.save()
        TraceNotificationCenter.requestIfNeeded()
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
        menu.addItem(NSMenuItem(title: "캡처 시작", action: #selector(startCopyCaptureFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "앱으로 전달 캡처", action: #selector(startDeliveryCaptureFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "히스토리 열기", action: #selector(openHistoryFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "설정 열기", action: #selector(openSettingsFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func registerHotKeys() {
        hotKeyManager.register(copyAction: { [weak self] in
            Task { @MainActor in self?.startCapture(mode: .copyOnly) }
        }, deliverAction: { [weak self] in
            Task { @MainActor in self?.startCapture(mode: .deliverToApp) }
        })
    }

    @objc private func startCopyCaptureFromMenu() {
        startCapture(mode: .copyOnly)
    }

    @objc private func startDeliveryCaptureFromMenu() {
        startCapture(mode: .deliverToApp)
    }

    @objc private func openHistoryFromMenu() {
        openHistory()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    func startCapture(mode: CaptureMode? = nil) {
        let captureMode = mode ?? settingsStore.settings.defaultCaptureMode
        guard PermissionService.hasScreenRecordingPermission else {
            PermissionService.requestScreenRecordingPermission()
            showPermissionAlert(
                message: "화면 캡처 권한이 필요합니다.",
                info: """
                시스템 설정에서 아래 앱에 화면 기록 권한을 허용한 뒤 Trace를 완전히 종료하고 다시 실행하세요.

                \(PermissionService.currentAppIdentityDescription)
                """,
                openAction: PermissionService.openScreenRecordingSettings
            )
            return
        }

        overlayController.start { [weak self] result in
            Task { @MainActor in
                await self?.handleCaptureResult(result, mode: captureMode)
            }
        }
    }

    private func handleCaptureResult(_ result: Result<CaptureResult, Error>, mode: CaptureMode) async {
        switch result {
        case .success(let capture):
            do {
                let saved = try storage.save(image: capture.image, mode: mode)
                try ClipboardService.copy(image: capture.image)
                TraceNotificationCenter.showSaved(
                    fileURL: saved.fileURL,
                    folderName: TraceDateFormatters.folder.string(from: saved.item.createdAt),
                    enabled: settingsStore.settings.showSaveNotification
                )

                if mode == .deliverToApp {
                    presentDestinationPicker(for: saved)
                } else {
                    openHistory()
                }
            } catch {
                showError(error.localizedDescription)
            }
        case .failure(let error):
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

        destinationWindow = makeWindow(title: "전달 대상 선택", size: NSSize(width: 380, height: 460), rootView: view)
        destinationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func deliver(saved: SavedCapture, to destination: AppDestination) async {
        destinationWindow?.close()
        do {
            try await deliveryService.deliver(to: destination)
            storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .delivered)
        } catch {
            storage.updateDelivery(itemID: saved.item.id, appName: destination.name, state: .failed)
            if case TraceError.accessibilityRequired = error {
                PermissionService.requestAccessibilityPermission()
                showPermissionAlert(
                    message: "앱으로 자동 전달하려면 손쉬운 사용 권한이 필요합니다.",
                    info: "저장과 클립보드 복사는 완료되었습니다. 권한을 허용하면 다음 캡처부터 자동 전달을 사용할 수 있습니다.",
                    openAction: PermissionService.openAccessibilitySettings
                )
            } else {
                showError(error.localizedDescription)
            }
        }
        openHistory()
    }

    private func openHistory() {
        storage.reload()
        let view = HistoryView(storage: storage)
        if historyWindow == nil {
            historyWindow = makeWindow(title: "Trace 히스토리", size: NSSize(width: 920, height: 640), rootView: view)
        } else {
            historyWindow?.contentViewController = NSHostingController(rootView: view)
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        let view = SettingsView(settingsStore: settingsStore)
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Trace 설정", size: NSSize(width: 560, height: 420), rootView: view)
        } else {
            settingsWindow?.contentViewController = NSHostingController(rootView: view)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
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
        TraceNotificationCenter.showFailure(message)
    }
}
