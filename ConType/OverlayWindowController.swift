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
    private var hasShownKeyboard = false
    private var isApplyingProgrammaticResize = false
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
            resizeWindow(to: settings.keyboardWindowSize)
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
    
    func updateWindowSize() {
        resizeWindow(to: settings.keyboardWindowSize)
    }

    func enlargeWindow() {
        if settings.inMouseMode {
            settings.inMouseMode = false
            show()
            return
        } else {
            settings.keyboardWindowSize = settings.keyboardWindowSize.largerPreset(using: settings.keyboardCustomDimensions)
            updateWindowSize()
        }
    }

    func shrinkWindow() {
        if settings.inMouseMode {
            return
        } else {
            let nextSize = settings.keyboardWindowSize.smallerPreset(using: settings.keyboardCustomDimensions)
            if settings.keyboardWindowSize == .custom {
                settings.keyboardWindowSize = nextSize
                updateWindowSize()
            } else if nextSize == .small && settings.keyboardWindowSize == .small {
                settings.inMouseMode = true
                show()
            } else {
                settings.keyboardWindowSize = nextSize
                updateWindowSize()
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
            .frame(minWidth: 640, maxWidth: 1440, minHeight: 240, maxHeight: 540)
        
        let windowDimensions = settings.keyboardWindowSize.windowDimensions(customSize: settings.keyboardCustomDimensions)
        
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
        window.aspectRatio = NSSize(width: 8, height: 3)
        window.minSize = NSSize(width: 640, height: 240)
        window.maxSize = NSSize(width: 1440, height: 540)
        
        self.keyboardWindow = window
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: keyboardWindow
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: keyboardWindow
        )
        
        return window
    }

    private func resizeWindow(to size: WindowSize) {
        guard let keyboardWindow else { return }
        guard !isApplyingProgrammaticResize else { return }
        let screen = NSScreen.main ?? keyboardWindow.screen ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }

        let keyboardWindowDimensions = size.windowDimensions(customSize: settings.keyboardCustomDimensions)
        let keyboardWindowPosition = settings.keyboardWindowPosition
        
        let targetSize = NSSize(
            width: min(1440, max(640, keyboardWindowDimensions.width)),
            height: min(540, max(240, keyboardWindowDimensions.height))
        )
        
        let normalizedSize = NSSize(
            width: min(frame.width - 80, targetSize.width),
            height: min(frame.height - 120, targetSize.height)
        )
        
        let newOrigin: NSPoint
        
        if !hasShownKeyboard {
            if keyboardWindowPosition != .zero {
                newOrigin = keyboardWindowPosition
            } else {
                newOrigin = NSPoint(
                    x: frame.midX - (normalizedSize.width / 2),
                    y: frame.midY - (normalizedSize.height / 2)
                )
            }
            
            hasShownKeyboard = true
        } else {
            let currentCenter = NSPoint(
                x: keyboardWindow.frame.origin.x + keyboardWindow.frame.size.width / 2,
                y: keyboardWindow.frame.origin.y + keyboardWindow.frame.size.height / 2
            )
            
            newOrigin = NSPoint(
                x: currentCenter.x - (normalizedSize.width / 2),
                y: currentCenter.y - (normalizedSize.height / 2)
            )
        }
        
        isApplyingProgrammaticResize = true
        keyboardWindow.setFrame(
            NSRect(origin: newOrigin, size: normalizedSize),
            display: true,
            animate: true
        )
        isApplyingProgrammaticResize = false
    }
    
    private func makeMouseWindowIfNeeded() -> NSWindow {
        if let mouseWindow {
            return mouseWindow
        }
        
        let contentView = MouseOverlayView() { [weak self] in
            self?.settings.inMouseMode = false
            self?.show()
        }
            .frame(minWidth: 64, maxWidth: 64, minHeight: 64, maxHeight: 64)
        
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
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.aspectRatio = NSSize(width: 1, height: 1)
        window.minSize = NSSize(width: 64, height: 64)
        window.maxSize = NSSize(width: 64, height: 64)
        
        self.mouseWindow = window
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: mouseWindow
        )
        
        return window
    }

    //MARK: - Window Event Handlers
    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == keyboardWindow {
            settings.keyboardWindowPosition = window.frame.origin
        } else if window == mouseWindow {
            settings.mouseWindowPosition = window.frame.origin
        }
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            window === self.keyboardWindow,
            !isApplyingProgrammaticResize
        else { return }

        settings.keyboardCustomDimensions = window.frame.size
        settings.keyboardWindowPosition = window.frame.origin
        settings.keyboardWindowSize = .custom

//        let snappedPreset = WindowSize.preset(for: window.frame.size)
//        let snappedDimensions = snappedPreset.windowDimensions()
//        
//        if window.frame.size.width == snappedDimensions.width
//            && window.frame.size.height == snappedDimensions.height {
//            settings.keyboardWindowSize = snappedPreset
//        } else {
//            settings.keyboardWindowSize = .custom
//        }
    }
}
