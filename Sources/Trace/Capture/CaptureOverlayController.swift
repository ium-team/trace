import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CaptureOverlayController {
    private var windows: [CaptureOverlayWindow] = []
    private var completion: ((Result<CaptureResult, Error>) -> Void)?
    private var isFinishing = false
    private var generation = 0

    func start(completion: @escaping (Result<CaptureResult, Error>) -> Void) {
        cancelActiveOverlay()
        generation += 1
        isFinishing = false
        self.completion = completion
        windows = NSScreen.screens.map { screen in
            let window = CaptureOverlayWindow(screen: screen)
            window.overlayView.onComplete = { [weak self, weak window] selection in
                guard let self, let window else { return }
                self.finish(selection: selection, screen: window.traceScreen)
            }
            window.overlayView.onCancel = { [weak self] in
                self?.cancel()
            }
            window.makeKeyAndOrderFront(nil)
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(selection: CGRect, screen: NSScreen) {
        guard !isFinishing else { return }
        isFinishing = true

        let activeWindows = hideWindowsForDeferredClose()
        let activeCompletion = completion
        let activeGeneration = generation

        Task { @MainActor [weak self, activeWindows] in
            await Task.yield()
            defer {
                activeWindows.forEach { $0.close() }
                if self?.generation == activeGeneration {
                    self?.completion = nil
                    self?.isFinishing = false
                }
            }

            guard let self else { return }
            guard selection.width >= 8, selection.height >= 8 else {
                activeCompletion?(.failure(TraceError.captureFailed))
                return
            }

            guard let image = capture(selection: selection, on: screen) else {
                activeCompletion?(.failure(TraceError.captureFailed))
                return
            }

            activeCompletion?(.success(CaptureResult(image: image, pixelWidth: Int(image.size.width), pixelHeight: Int(image.size.height))))
        }
    }

    private func cancel() {
        cancelActiveOverlay()
        completion = nil
    }

    private func cancelActiveOverlay() {
        guard !windows.isEmpty else { return }
        let activeWindows = hideWindowsForDeferredClose()
        Task { @MainActor [activeWindows] in
            await Task.yield()
            activeWindows.forEach { $0.close() }
        }
    }

    private func hideWindowsForDeferredClose() -> [CaptureOverlayWindow] {
        let activeWindows = windows
        activeWindows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        return activeWindows
    }

    private func capture(selection: CGRect, on screen: NSScreen) -> NSImage? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)

        let scale = screen.backingScaleFactor
        let pixelRect = CGRect(
            x: selection.minX * scale,
            y: (screen.frame.height - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral

        guard let cgImage = CGDisplayCreateImage(displayID, rect: pixelRect) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

final class CaptureOverlayWindow: NSWindow {
    private(set) var traceScreen: NSScreen!
    private(set) var overlayView: CaptureOverlayView!

    init(screen: NSScreen) {
        self.traceScreen = screen
        self.overlayView = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
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
