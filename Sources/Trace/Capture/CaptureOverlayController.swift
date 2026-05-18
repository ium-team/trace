import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CaptureOverlayController {
    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private final class OverlaySession {
        let screen: NSScreen
        let window: NSPanel
        let view: CaptureOverlayView

        init(screen: NSScreen, window: NSPanel, view: CaptureOverlayView) {
            self.screen = screen
            self.window = window
            self.view = view
        }
    }

    private var sessions: [OverlaySession] = []
    private var completion: ((Result<InteractiveCaptureResult, Error>) -> Void)?
    private var isFinishing = false
    private var generation = 0
    private var currentPlan: CapturePlan = .areaCopy
    private var keyMonitor: Any?

    func start(defaultPlan: CapturePlan, completion: @escaping (Result<InteractiveCaptureResult, Error>) -> Void) {
        cancelActiveOverlay()
        generation += 1
        isFinishing = false
        currentPlan = defaultPlan
        self.completion = completion

        sessions = NSScreen.screens.map { screen in
            let view = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.plan = defaultPlan
            let window = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.defaultButtonCell = captureButtonCell(for: view)
            window.contentView = view

            view.onComplete = { [weak self] selection in
                self?.finish(selection: selection, screen: screen, overlayBounds: view.bounds)
            }
            view.onCaptureFullScreen = { [weak self] in
                self?.finishFullScreen(on: screen)
            }
            view.onPlanChange = { [weak self] plan in
                self?.updatePlan(plan)
            }
            view.onCancel = { [weak self] in
                self?.cancel()
            }

            window.makeKeyAndOrderFront(nil)
            return OverlaySession(screen: screen, window: window, view: view)
        }

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func forceCancelActiveOverlay() {
        cancel()
    }

    func captureFullScreen() throws -> CaptureResult {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw TraceError.captureFailedReason("디스플레이 정보를 읽지 못했습니다.")
        }

        return try captureFullScreen(on: screen)
    }

    private func captureFullScreen(on screen: NSScreen) throws -> CaptureResult {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw TraceError.captureFailedReason("디스플레이 정보를 읽지 못했습니다.")
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            throw TraceError.captureFailedReason("CoreGraphics가 전체 화면 이미지를 만들지 못했습니다. 화면 기록 권한을 다시 확인하세요.")
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return CaptureResult(image: image)
    }

    private func updatePlan(_ plan: CapturePlan) {
        currentPlan = plan
        sessions.forEach { session in
            if session.view.plan != plan {
                session.view.plan = plan
            }
        }
    }

    private func finish(selection: CGRect, screen: NSScreen, overlayBounds: CGRect) {
        guard !isFinishing else { return }
        isFinishing = true

        let activeSessions = hideWindowsForDeferredClose()
        let activeCompletion = completion
        let activeGeneration = generation
        let activePlan = currentPlan

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, activeSessions] in
            guard let self else { return }
            defer {
                self.close(sessions: activeSessions)
                if self.generation == activeGeneration {
                    self.completion = nil
                    self.isFinishing = false
                }
            }

            guard selection.width >= 8, selection.height >= 8 else {
                activeCompletion?(.failure(TraceError.captureFailedReason("캡처 영역이 너무 작습니다. 최소 8x8 포인트 이상 드래그하세요.")))
                return
            }

            do {
                let image = try self.capture(selection: selection, overlayBounds: overlayBounds, on: screen)
                activeCompletion?(.success(InteractiveCaptureResult(capture: CaptureResult(image: image), plan: activePlan)))
            } catch {
                activeCompletion?(.failure(error))
            }
        }
    }

    private func finishFullScreen(on screen: NSScreen) {
        guard !isFinishing else { return }
        isFinishing = true

        let activeSessions = hideWindowsForDeferredClose()
        let activeCompletion = completion
        let activeGeneration = generation
        let activePlan = CapturePlan(mode: currentPlan.mode, scope: .fullScreen)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, activeSessions] in
            guard let self else { return }
            defer {
                self.close(sessions: activeSessions)
                if self.generation == activeGeneration {
                    self.completion = nil
                    self.isFinishing = false
                }
            }

            do {
                let capture = try self.captureFullScreen(on: screen)
                activeCompletion?(.success(InteractiveCaptureResult(capture: capture, plan: activePlan)))
            } catch {
                activeCompletion?(.failure(error))
            }
        }
    }

    private func cancel() {
        cancelActiveOverlay()
        completion?(.failure(TraceError.captureCancelled))
        completion = nil
        isFinishing = false
    }

    private func cancelActiveOverlay() {
        guard !sessions.isEmpty else { return }
        let activeSessions = hideWindowsForDeferredClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, activeSessions] in
            self?.close(sessions: activeSessions)
        }
    }

    private func hideWindowsForDeferredClose() -> [OverlaySession] {
        let activeSessions = sessions
        removeKeyMonitor()
        activeSessions.forEach { $0.window.orderOut(nil) }
        sessions.removeAll()
        return activeSessions
    }

    private func close(sessions: [OverlaySession]) {
        sessions.forEach { session in
            session.view.onComplete = nil
            session.view.onCaptureFullScreen = nil
            session.view.onPlanChange = nil
            session.view.onCancel = nil
            session.window.contentView = nil
            session.window.close()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.sessions.isEmpty else { return event }
            guard self.handleKey(event) else { return event }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            cancel()
            return true
        case 36, 76, 49:
            captureFromKeyInput()
            return true
        default:
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                captureFromKeyInput()
                return true
            }
            return false
        }
    }

    private func captureFromKeyInput() {
        guard let session = sessions.first(where: { $0.window.isKeyWindow }) ?? sessions.first else { return }
        session.view.captureFromKeyboard()
    }

    private func captureButtonCell(for view: CaptureOverlayView) -> NSButtonCell? {
        view.captureButtonCell
    }

    private func capture(selection: CGRect, overlayBounds: CGRect, on screen: NSScreen) throws -> NSImage {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw TraceError.captureFailedReason("디스플레이 정보를 읽지 못했습니다.")
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        let displayBounds = CGDisplayBounds(displayID)
        guard overlayBounds.width > 0, overlayBounds.height > 0, displayBounds.width > 0, displayBounds.height > 0 else {
            throw TraceError.captureFailedReason("캡처 영역 좌표를 계산하지 못했습니다.")
        }

        let scaleX = displayBounds.width / overlayBounds.width
        let scaleY = displayBounds.height / overlayBounds.height
        let rawPixelRect = CGRect(
            x: displayBounds.minX + selection.minX * scaleX,
            y: displayBounds.minY + (overlayBounds.height - selection.maxY) * scaleY,
            width: selection.width * scaleX,
            height: selection.height * scaleY
        ).integral
        let pixelRect = rawPixelRect.intersection(displayBounds).integral

        guard pixelRect.width >= 8, pixelRect.height >= 8, !pixelRect.isNull else {
            throw TraceError.captureFailedReason("선택 영역 좌표가 디스플레이 범위를 벗어났습니다.")
        }

        guard let cgImage = CGDisplayCreateImage(displayID, rect: pixelRect) else {
            throw TraceError.captureFailedReason("CoreGraphics가 선택 영역 이미지를 만들지 못했습니다. 화면 기록 권한을 다시 확인하세요.")
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

final class CaptureOverlayView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCaptureFullScreen: (() -> Void)?
    var onPlanChange: ((CapturePlan) -> Void)?
    var onCancel: (() -> Void)?
    var plan: CapturePlan = .areaCopy {
        didSet {
            updateControls()
            needsDisplay = true
        }
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private let scopeControl = NSSegmentedControl(labels: CaptureScope.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: CaptureMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let captureButton = NSButton(title: "캡처", target: nil, action: nil)
    private let cancelButton = NSButton(title: "취소", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupToolbar()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupToolbar()
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if plan.scope == .fullScreen {
            NSGraphicsContext.current?.compositingOperation = .clear
            bounds.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.controlAccentColor.withAlphaComponent(0.82).setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
            path.lineWidth = 4
            path.stroke()
            return
        }

        guard let rect = selectionRect else { return }

        NSGraphicsContext.current?.compositingOperation = .clear
        rect.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        NSColor.white.withAlphaComponent(0.12).setFill()
        rect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard plan.scope == .area else { return }
        let point = event.locationInWindow
        dragStart = point
        dragCurrent = point
        updateControls()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard plan.scope == .area else { return }
        dragCurrent = event.locationInWindow
        updateControls()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard plan.scope == .area else { return }
        guard dragStart != nil else {
            return
        }
        dragCurrent = event.locationInWindow
        updateControls()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
            capturePressed()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            capturePressed()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func setupToolbar() {
        let toolbar = NSVisualEffectView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 10
        toolbar.layer?.masksToBounds = true

        let stack = NSStackView(views: [scopeControl, modeControl, captureButton, cancelButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        toolbar.addSubview(stack)
        addSubview(toolbar)

        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.refusesFirstResponder = true
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.refusesFirstResponder = true
        captureButton.target = self
        captureButton.action = #selector(capturePressed)
        captureButton.keyEquivalent = "\r"
        captureButton.refusesFirstResponder = true
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.refusesFirstResponder = true

        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -10)
        ])
        updateControls()
    }

    private func updateControls() {
        scopeControl.selectedSegment = CaptureScope.allCases.firstIndex(of: plan.scope) ?? 0
        modeControl.selectedSegment = CaptureMode.allCases.firstIndex(of: plan.mode) ?? 0
        captureButton.isEnabled = plan.scope == .fullScreen || selectionRect != nil
    }

    fileprivate var captureButtonCell: NSButtonCell? {
        captureButton.cell as? NSButtonCell
    }

    @objc private func scopeChanged() {
        let scope = CaptureScope.allCases[max(0, scopeControl.selectedSegment)]
        dragStart = nil
        dragCurrent = nil
        onPlanChange?(CapturePlan(mode: plan.mode, scope: scope))
    }

    @objc private func modeChanged() {
        let mode = CaptureMode.allCases[max(0, modeControl.selectedSegment)]
        onPlanChange?(CapturePlan(mode: mode, scope: plan.scope))
    }

    @objc private func capturePressed() {
        captureFromKeyboard()
    }

    fileprivate func captureFromKeyboard() {
        if plan.scope == .fullScreen {
            onCaptureFullScreen?()
        } else if let selectionRect {
            onComplete?(selectionRect)
        }
    }

    @objc private func cancelPressed() {
        onCancel?()
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
    }
}
