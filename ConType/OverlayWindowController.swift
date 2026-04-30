import AppKit
import Combine
import SkyLightWindow
import SwiftUI

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController {
    private var cancellables = Set<AnyCancellable>()
    private var keyboardWindow: NSWindow?
    private var mouseWindow: NSWindow?
    private let settings: AppSettings
    private let keyboardViewModel: KeyboardOverlayViewModel
    private let keyEmitter = KeyEmitter()

    var isKeyboardVisible: Bool {
        keyboardWindow?.isVisible == true
    }
    
    var isMouseVisible: Bool {
        mouseWindow?.isVisible == true
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.keyboardViewModel = KeyboardOverlayViewModel(settings: settings)
        
        settings.$inMouseMode
            .sink { [weak self] _ in self?.settings.save() }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @discardableResult
    func show() -> Bool {
        // Hide any existing windows if any
        hide()
        
        if settings.inMouseMode {
            let mouseWindow = makeMouseWindowIfNeeded()
            SkyLightOperator.shared.delegateWindow(mouseWindow)
            
            mouseWindow.orderFrontRegardless()
            return mouseWindow.isVisible
        } else {
            let keyboardWindow = makeWindowIfNeeded()
            resizeWindow(to: settings.windowSize)
            SkyLightOperator.shared.delegateWindow(keyboardWindow)
            
            keyboardWindow.orderFrontRegardless()
            return keyboardWindow.isVisible
        }
    }

    func hide() {
        keyboardWindow?.orderOut(nil)
        mouseWindow?.orderOut(nil)
    }

    @discardableResult
    func moveSelection(
        _ direction: OverlayMoveDirection,
        trigger: OverlayMoveTrigger = .press
    ) -> Bool {
        keyboardViewModel.move(direction, trigger: trigger)
    }

    func activateSelectedKey() {
        keyboardViewModel.activateSelected { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }
    }

    func activateBackspaceKey() {
        keyEmitter.emit(keyCode: 51)
    }

    func activateSpaceKey() {
        keyEmitter.emit(keyCode: 49)
    }

    func activateEnterKey() {
        keyEmitter.emit(keyCode: 36)
    }

    func activateShiftShortcut(cyclesToCapsLock: Bool) {
        keyboardViewModel.cycleShiftShortcut(cyclesToCapsLock: cyclesToCapsLock)
    }

    func activateCapsLockShortcut() {
        keyboardViewModel.toggleCapsLockShortcut()
    }

    func enlargeWindow() {
        if settings.inMouseMode {
            settings.inMouseMode = false
            settings.save()
            show()
            return
        } else {
            switch settings.windowSize {
            case .small:
                resizeWindow(to: .medium)
                break
            case .medium:
                resizeWindow(to: .large)
                break
            case .large:
                resizeWindow(to: .xLarge)
                break
            case .xLarge:
                break
            }
        }
    }

    func shrinkWindow() {
        if settings.inMouseMode {
            return
        } else {
            switch settings.windowSize {
            case .small:
                settings.inMouseMode = true
                settings.save()
                show()
                break
            case .medium:
                resizeWindow(to: .small)
                break
            case .large:
                resizeWindow(to: .medium)
                break
            case .xLarge:
                resizeWindow(to: .large)
                break
            }
        }
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let keyboardWindow {
            return keyboardWindow
        }
        
        let contentView = KeyboardOverlayView(
            viewModel: keyboardViewModel
        ) { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }
        
        let windowDimensions = settings.windowSize.windowDimensions
        
        let hostingController = NSHostingController(rootView: contentView)
        let baseMask: NSWindow.StyleMask = [
            .borderless, .resizable, .fullSizeContentView,
        ]
        let window = NonActivatingOverlayPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: windowDimensions.width,
                height: windowDimensions.height
            ),
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
        window.contentMinSize = NSSize(width: 800, height: 300)
        
        self.keyboardWindow = window
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: keyboardWindow
        )
        
        return window
    }

    private func resizeWindow(to size: WindowSize) {
        guard let keyboardWindow else { return }
        let screen = NSScreen.main ?? keyboardWindow.screen ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }

        settings.windowSize = size
        let keyboardWindowDimensions = settings.windowSize.windowDimensions
        let keyboardWindowPosition = settings.windowPosition

        // Limit window size to constraint
        let targetSize = NSSize(
            width: min(1440, max(800, keyboardWindowDimensions.width)),
            height: min(540, max(300, keyboardWindowDimensions.height))
        )

        // Limit window size to within screen bounds
        let normalizedSize = NSSize(
            width: min(frame.width - 80, targetSize.width),
            height: min(frame.height - 120, targetSize.height)
        )

        let origin =
            keyboardWindowPosition != .zero
            ? keyboardWindowPosition
            : NSPoint(
                x: frame.midX - (normalizedSize.width / 2),
                y: frame.midY - (normalizedSize.height / 2)
            )

        keyboardWindow.setFrame(
            NSRect(origin: origin, size: normalizedSize),
            display: true,
            animate: true
        )
    }
    
    private func makeMouseWindowIfNeeded() -> NSWindow {
        if let mouseWindow {
            return mouseWindow
        }
        
        let contentView = MouseOverlayView() { [weak self] in
            self?.settings.inMouseMode = false
            self?.show()
        }
        
        let hostingController = NSHostingController(rootView: contentView)
        let baseMask: NSWindow.StyleMask = [
            .borderless, .fullSizeContentView,
        ]
        let window = NonActivatingOverlayPanel(
            contentRect: NSRect(
                x: 16,
                y: 16,
                width: 64,
                height: 64
            ),
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
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentAspectRatio = NSSize(width: 1, height: 1)
        window.contentMinSize = NSSize(width: 64, height: 64)
        
        self.mouseWindow = window
        
        return window
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            window === self.keyboardWindow
        else { return }
        settings.windowPosition = window.frame.origin
    }
}
