import AppKit
import SwiftUI

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private let keyboardViewModel = KeyboardOverlayViewModel()
    private let keyEmitter = KeyEmitter()

    var isVisible: Bool {
        window?.isVisible == true
    }

    @discardableResult
    func show() -> Bool {
        let window = makeWindowIfNeeded()
        positionWindowOnActiveScreen(window)

        window.orderFrontRegardless()
        return window.isVisible
    }

    func hide() {
        window?.orderOut(nil)
    }

    func moveSelection(_ direction: OverlayMoveDirection) {
        keyboardViewModel.move(direction)
    }

    func activateSelectedKey() {
        keyboardViewModel.activateSelected { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }
    }

    func activateBackspaceKey() {
        keyEmitter.emit(keyCode: 51)
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let contentView = KeyboardOverlayView(viewModel: keyboardViewModel) { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }

        let hostingController = NSHostingController(rootView: contentView)
        let baseMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = NonActivatingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 420),
            styleMask: baseMask.union(.nonactivatingPanel),
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentAspectRatio = NSSize(width: 5, height: 2)
        window.contentMinSize = NSSize(width: 840, height: 320)

        self.window = window
        return window
    }

    private func positionWindowOnActiveScreen(_ window: NSWindow) {
        let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }

        let targetSize = NSSize(
            width: min(1040, max(840, frame.width - 80)),
            height: min(420, max(320, frame.height - 120))
        )

        let origin = NSPoint(
            x: frame.midX - (targetSize.width / 2),
            y: frame.midY - (targetSize.height / 2)
        )

        window.setFrame(NSRect(origin: origin, size: targetSize), display: true)
    }
}

