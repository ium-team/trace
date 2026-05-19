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
    private var lastSettingsSnapshot: TraceSettings?
    private var pendingRecentDeliveryDestination: AppDestination?
    private var statusMenu: NSMenu?

    func start() {
        settingsStore.save()
        lastSettingsSnapshot = settingsStore.settings
        settingsStore.onUpdate = { [weak self] _ in
            self?.handleSettingsChanged()
        }
        TraceNotificationCenter.configure()
        TraceNotificationCenter.requestIfNeeded(enabled: true)
        configureStatusItem()
        registerHotKeys()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Trace"
        let menu = makeMenu()
        item.menu = menu
        statusMenu = menu
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

        let quickSettingsItem = NSMenuItem(title: "빠른 설정", action: nil, keyEquivalent: "")
        quickSettingsItem.submenu = makeQuickSettingsMenu()
        menu.addItem(quickSettingsItem)

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

    private func handleSettingsChanged() {
        let current = settingsStore.settings
        let previous = lastSettingsSnapshot
        lastSettingsSnapshot = current

        if previous?.basicCaptureShortcut != current.basicCaptureShortcut ||
            previous?.deliveryCaptureShortcut != current.deliveryCaptureShortcut {
            registerHotKeys()
        }

        if previous?.fileNameRule != current.fileNameRule ||
            previous?.dateFileNameFormat != current.dateFileNameFormat ||
            previous?.sequenceStyle != current.sequenceStyle {
            do {
                try storage.applyNamingRuleToAllCaptures()
            } catch {
                NSLog("Trace rename-all failed: \(error.localizedDescription)")
            }
        }

        refreshQuickSettingsMenuIfNeeded()
    }

    private func makeQuickSettingsMenu() -> NSMenu {
        let menu = NSMenu()

        let autoCopyItem = NSMenuItem(title: "캡처 후 자동 복사", action: #selector(toggleAutoCopyFromMenu), keyEquivalent: "")
        autoCopyItem.target = self
        menu.addItem(autoCopyItem)

        menu.addItem(.separator())

        let defaultModeItem = NSMenuItem(title: "기본 캡처 방식", action: nil, keyEquivalent: "")
        defaultModeItem.submenu = makeDefaultModeMenu()
        menu.addItem(defaultModeItem)

        let basicActionItem = NSMenuItem(title: "기본 캡처 완료 후 동작", action: nil, keyEquivalent: "")
        basicActionItem.submenu = makeBasicActionMenu()
        menu.addItem(basicActionItem)

        let deliveryActionItem = NSMenuItem(title: "전달 캡처 완료 후 동작", action: nil, keyEquivalent: "")
        deliveryActionItem.submenu = makeDeliveryActionMenu()
        menu.addItem(deliveryActionItem)

        let deliveryTargetItem = NSMenuItem(title: "전달 대상", action: nil, keyEquivalent: "")
        deliveryTargetItem.submenu = makeDeliveryTargetMenu()
        menu.addItem(deliveryTargetItem)

        updateQuickSettingsMenuState(menu)
        return menu
    }

    private func makeDefaultModeMenu() -> NSMenu {
        let menu = NSMenu()
        for mode in CaptureMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectDefaultCaptureModeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func makeBasicActionMenu() -> NSMenu {
        let menu = NSMenu()
        for action in TraceSettings.BasicCaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(selectBasicCaptureActionFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func makeDeliveryActionMenu() -> NSMenu {
        let menu = NSMenu()
        for action in TraceSettings.DeliveryCaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(selectDeliveryCaptureActionFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func makeDeliveryTargetMenu() -> NSMenu {
        let menu = NSMenu()
        for target in TraceSettings.DeliveryTargetMode.allCases {
            let item = NSMenuItem(title: target.title, action: #selector(selectDeliveryTargetModeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func refreshQuickSettingsMenuIfNeeded() {
        guard let rootMenu = statusMenu,
              let quickSettingsMenu = rootMenu.item(withTitle: "빠른 설정")?.submenu
        else {
            return
        }

        updateQuickSettingsMenuState(quickSettingsMenu)
    }

    private func updateQuickSettingsMenuState(_ menu: NSMenu) {
        let settings = settingsStore.settings

        if let autoCopyItem = menu.item(withTitle: "캡처 후 자동 복사") {
            autoCopyItem.state = settings.copyToClipboardByDefault ? .on : .off
        }

        if let defaultModeMenu = menu.item(withTitle: "기본 캡처 방식")?.submenu {
            updateSubmenuState(defaultModeMenu, selectedRawValue: settings.defaultCaptureMode.rawValue)
        }

        if let basicActionMenu = menu.item(withTitle: "기본 캡처 완료 후 동작")?.submenu {
            updateSubmenuState(basicActionMenu, selectedRawValue: settings.basicCaptureAction.rawValue)
        }

        if let deliveryActionMenu = menu.item(withTitle: "전달 캡처 완료 후 동작")?.submenu {
            updateSubmenuState(deliveryActionMenu, selectedRawValue: settings.deliveryCaptureAction.rawValue)
        }

        if let deliveryTargetMenu = menu.item(withTitle: "전달 대상")?.submenu {
            updateSubmenuState(deliveryTargetMenu, selectedRawValue: settings.deliveryTargetMode.rawValue)
        }
    }

    private func updateSubmenuState(_ menu: NSMenu, selectedRawValue: String) {
        menu.items.forEach { item in
            let rawValue = item.representedObject as? String
            item.state = rawValue == selectedRawValue ? .on : .off
        }
    }

    @objc private func toggleAutoCopyFromMenu() {
        var updated = settingsStore.settings
        updated.copyToClipboardByDefault.toggle()
        settingsStore.update(updated)
    }

    @objc private func selectDefaultCaptureModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = CaptureMode(rawValue: rawValue)
        else {
            return
        }

        var updated = settingsStore.settings
        updated.defaultCaptureMode = mode
        settingsStore.update(updated)
    }

    @objc private func selectBasicCaptureActionFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = TraceSettings.BasicCaptureAction(rawValue: rawValue)
        else {
            return
        }

        var updated = settingsStore.settings
        updated.basicCaptureAction = action
        settingsStore.update(updated)
    }

    @objc private func selectDeliveryCaptureActionFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = TraceSettings.DeliveryCaptureAction(rawValue: rawValue)
        else {
            return
        }

        var updated = settingsStore.settings
        updated.deliveryCaptureAction = action
        settingsStore.update(updated)
    }

    @objc private func selectDeliveryTargetModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = TraceSettings.DeliveryTargetMode(rawValue: rawValue)
        else {
            return
        }

        var updated = settingsStore.settings
        updated.deliveryTargetMode = mode
        settingsStore.update(updated)
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
        pendingRecentDeliveryDestination = currentExternalFrontmostApplication()
        guard PermissionService.hasScreenRecordingPermission else {
            requestScreenRecordingPermissionForCapture(defaultPlan: plan)
            return
        }

        performInteractiveCapture(defaultPlan: plan)
    }

    private func requestScreenRecordingPermissionForCapture(defaultPlan: CapturePlan) {
        _ = PermissionService.requestScreenRecordingPermission()

        guard PermissionService.hasScreenRecordingPermission else {
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
        defer {
            pendingRecentDeliveryDestination = nil
        }

        switch result {
        case .success(let capture):
            do {
                let shouldCopyToClipboard = settingsStore.settings.copyToClipboardByDefault || mode == .deliverToApp
                if shouldCopyToClipboard {
                    try ClipboardService.copy(image: capture.image)
                }

                let saved = try saveIfNeeded(capture: capture, mode: mode)

                if mode == .deliverToApp {
                    guard prepareAccessibilityForDelivery(saved: saved) else {
                        return
                    }
                    await continueDelivery(saved: saved)
                } else if shouldCopyToClipboard {
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

    private func continueDelivery(saved: SavedCapture?) async {
        switch settingsStore.settings.deliveryTargetMode {
        case .chooseEachTime:
            presentDestinationPicker(for: saved)
        case .mostRecentApp:
            guard let destination = pendingRecentDeliveryDestination else {
                markDeliveryFailed(saved: saved)
                TraceNotificationCenter.showDeliveryFailed(
                    appName: "최근 사용 앱",
                    message: "캡처 시작 직전에 사용하던 앱을 찾지 못했습니다.",
                    enabled: true
                )
                return
            }
            await deliver(saved: saved, to: destination, window: nil)
        case .fixedApp:
            await continueFixedAppDelivery(saved: saved)
        }
    }

    private func continueFixedAppDelivery(saved: SavedCapture?) async {
        let settings = settingsStore.settings
        let appName = settings.fixedDeliveryAppName ?? "지정 앱"
        guard let bundleIdentifier = settings.fixedDeliveryAppBundleIdentifier else {
            markDeliveryFailed(saved: saved)
            TraceNotificationCenter.showDeliveryFailed(
                appName: appName,
                message: "설정에서 전달할 앱을 먼저 선택해야 합니다.",
                enabled: true
            )
            return
        }

        guard let destination = deliveryService.runningApp(bundleIdentifier: bundleIdentifier) else {
            markDeliveryFailed(saved: saved)
            TraceNotificationCenter.showDeliveryFailed(
                appName: appName,
                message: "앱이 실행 중이 아닙니다.",
                enabled: true
            )
            return
        }

        switch settings.fixedDeliveryAppWindowMode {
        case .mostRecentWindow:
            let window = await mostRecentWindow(for: destination)
            await deliver(saved: saved, to: destination, window: window)
        case .chooseWindow:
            await presentFixedAppWindowPicker(for: saved, destination: destination)
        }
    }

    private func mostRecentWindow(for destination: AppDestination) async -> AppWindowDestination? {
        let windows = await deliveryService.windows(for: destination)
        return windows.first { $0.isMain } ?? windows.first
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
            },
            onSelect: { [weak self] destination in
                Task { @MainActor in
                    await self?.presentWindowPicker(for: saved, destination: destination)
                }
            }
        )

        let size = destinationPickerSize(for: destinations)
        if destinationWindow == nil {
            destinationWindow = makeDeliveryOverlayWindow(size: size, rootView: view)
        } else {
            destinationWindow?.contentViewController = NSHostingController(rootView: view)
            destinationWindow?.setContentSize(size)
            destinationWindow?.center()
        }
        showDeliveryOverlayWindow(destinationWindow)
    }

    private func presentWindowPicker(for saved: SavedCapture?, destination: AppDestination) async {
        let windows = await deliveryService.windows(for: destination)
        let appSpecificDestinations = deliveryService.appSpecificDestinations(for: destination)
        let view = WindowPickerView(
            app: destination,
            windows: windows,
            appSpecificDestinations: appSpecificDestinations,
            backLabel: "앱",
            onBack: { [weak self] in
                self?.presentDestinationPicker(for: saved)
            },
            onSkip: { [weak self] in
                if let saved {
                    self?.storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .skipped)
                }
                self?.destinationWindow?.close()
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

        if destinationWindow == nil {
            destinationWindow = makeDeliveryOverlayWindow(size: NSSize(width: 760, height: 540), rootView: view)
        } else {
            destinationWindow?.contentViewController = NSHostingController(rootView: view)
            destinationWindow?.setContentSize(NSSize(width: 760, height: 540))
            destinationWindow?.center()
        }
        showDeliveryOverlayWindow(destinationWindow)
    }

    private func presentFixedAppWindowPicker(for saved: SavedCapture?, destination: AppDestination) async {
        let windows = await deliveryService.windows(for: destination)
        let appSpecificDestinations = deliveryService.appSpecificDestinations(for: destination)
        let view = WindowPickerView(
            app: destination,
            windows: windows,
            appSpecificDestinations: appSpecificDestinations,
            backLabel: "닫기",
            onBack: { [weak self] in
                if let saved {
                    self?.storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .skipped)
                }
                self?.destinationWindow?.close()
            },
            onSkip: { [weak self] in
                if let saved {
                    self?.storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .skipped)
                }
                self?.destinationWindow?.close()
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

        if destinationWindow == nil {
            destinationWindow = makeDeliveryOverlayWindow(size: NSSize(width: 760, height: 540), rootView: view)
        } else {
            destinationWindow?.contentViewController = NSHostingController(rootView: view)
            destinationWindow?.setContentSize(NSSize(width: 760, height: 540))
            destinationWindow?.center()
        }
        showDeliveryOverlayWindow(destinationWindow)
    }

    private func prepareAccessibilityForDelivery(saved: SavedCapture?) -> Bool {
        guard !PermissionService.hasAccessibilityPermission else {
            return true
        }

        PermissionService.requestAccessibilityPermission()

        if PermissionService.hasAccessibilityPermission {
            return true
        }

        markDeliveryFailed(saved: saved)
        return false
    }

    private func markDeliveryFailed(saved: SavedCapture?) {
        guard let saved else { return }
        storage.updateDelivery(itemID: saved.item.id, appName: nil, state: .failed)
    }

    private func currentExternalFrontmostApplication() -> AppDestination? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular
        else {
            return nil
        }

        let name = application.localizedName ?? application.bundleIdentifier ?? "Unknown"
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return AppDestination(
            bundleIdentifier: application.bundleIdentifier,
            name: name,
            icon: application.icon ?? NSImage(size: NSSize(width: 32, height: 32)),
            isActive: application.isActive,
            application: application
        )
    }

    private func deliver(saved: SavedCapture?, to destination: AppDestination, window: AppWindowDestination?) async {
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

    private func makeDeliveryOverlayWindow<Content: View>(size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.setContentSize(size)
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
    }

    private func destinationPickerSize(for destinations: [AppDestination]) -> NSSize {
        guard !destinations.isEmpty else {
            return NSSize(width: 360, height: 220)
        }

        let columnCount = min(max(destinations.count, 1), 6)
        let rowCount = Int(ceil(Double(destinations.count) / Double(columnCount)))
        let tileWidth: CGFloat = 124
        let tileHeight: CGFloat = 156
        let spacing: CGFloat = 14
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 16
        let width = CGFloat(columnCount) * tileWidth + CGFloat(columnCount - 1) * spacing + horizontalPadding
        let uncappedHeight = CGFloat(rowCount) * tileHeight + CGFloat(max(rowCount - 1, 0)) * spacing + verticalPadding
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 720
        return NSSize(width: width, height: min(uncappedHeight, visibleHeight * 0.78))
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

    private func showDeliveryOverlayWindow(_ window: NSWindow?) {
        guard let window else { return }
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
}
