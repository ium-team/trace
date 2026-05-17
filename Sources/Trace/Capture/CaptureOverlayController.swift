import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CaptureOverlayController {
    private var windows: [CaptureOverlayWindow] = []
    private var completion: ((Result<CaptureResult, Error>) -> Void)?

    func start(completion: @escaping (Result<CaptureResult, Error>) -> Void) {
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
        closeWindows()
        guard selection.width >= 8, selection.height >= 8 else {
            completion?(.failure(TraceError.captureFailed))
            completion = nil
            return
        }

        guard let image = capture(selection: selection, on: screen) else {
            completion?(.failure(TraceError.captureFailed))
            completion = nil
            return
        }

        completion?(.success(CaptureResult(image: image, pixelWidth: Int(image.size.width), pixelHeight: Int(image.size.height))))
        completion = nil
    }

    private func cancel() {
        closeWindows()
        completion = nil
    }

    private func closeWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func capture(selection: CGRect, on screen: NSScreen) -> NSImage? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

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
    let traceScreen: NSScreen
    let overlayView: CaptureOverlayView

    init(screen: NSScreen) {
        self.traceScreen = screen
        self.overlayView = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
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
