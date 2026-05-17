import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CaptureOverlayController {
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
    private var completion: ((Result<CaptureResult, Error>) -> Void)?
    private var isFinishing = false
    private var generation = 0

    func start(completion: @escaping (Result<CaptureResult, Error>) -> Void) {
        cancelActiveOverlay()
        generation += 1
        isFinishing = false
        self.completion = completion
        sessions = NSScreen.screens.map { screen in
            let view = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let window = NSPanel(
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
            window.contentView = view

            view.onComplete = { [weak self] selection in
                self?.finish(selection: selection, screen: screen)
            }
            view.onCancel = { [weak self] in
                self?.cancel()
            }
            window.makeKeyAndOrderFront(nil)
            return OverlaySession(screen: screen, window: window, view: view)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(selection: CGRect, screen: NSScreen) {
        guard !isFinishing else { return }
        isFinishing = true

        let activeSessions = hideWindowsForDeferredClose()
        let activeCompletion = completion
        let activeGeneration = generation

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
                let image = try capture(selection: selection, on: screen)
                activeCompletion?(.success(CaptureResult(image: image, pixelWidth: Int(image.size.width), pixelHeight: Int(image.size.height))))
            } catch {
                activeCompletion?(.failure(error))
            }
        }
    }

    private func cancel() {
        cancelActiveOverlay()
        completion = nil
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
        activeSessions.forEach { $0.window.orderOut(nil) }
        sessions.removeAll()
        return activeSessions
    }

    private func close(sessions: [OverlaySession]) {
        sessions.forEach { session in
            session.view.onComplete = nil
            session.view.onCancel = nil
            session.window.contentView = nil
            session.window.close()
        }
    }

    private func capture(selection: CGRect, on screen: NSScreen) throws -> NSImage {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw TraceError.captureFailedReason("디스플레이 정보를 읽지 못했습니다.")
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)

        let scale = screen.backingScaleFactor
        let rawPixelRect = CGRect(
            x: selection.minX * scale,
            y: (screen.frame.height - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
        let displayBounds = CGRect(x: 0, y: 0, width: CGFloat(CGDisplayPixelsWide(displayID)), height: CGFloat(CGDisplayPixelsHigh(displayID)))
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
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

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
        let point = event.locationInWindow
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else {
            return
        }
        dragCurrent = event.locationInWindow
        guard let rect = selectionRect else {
            onCancel?()
            return
        }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
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
