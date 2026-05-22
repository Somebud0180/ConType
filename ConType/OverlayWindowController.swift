import AppKit
import Combine
import SkyLightWindow
import SwiftUI

enum DragPhase { case began, changed, ended }

final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    var dragHandler: ((NSEvent, DragPhase) -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        dragHandler?(event, .began)
        
        var isDragging = true
        while isDragging, let nextEvent = self.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if nextEvent.type == .leftMouseDragged {
                dragHandler?(nextEvent, .changed)
            } else if nextEvent.type == .leftMouseUp {
                isDragging = false
                dragHandler?(nextEvent, .ended)
            }
        }
    }
}

@MainActor
final class OverlayWindowController {
    private var hasShownKeyboard = false
    private var isApplyingProgrammaticResize = false
    private var isApplyingProgrammaticSnap = false
    private var guideHideWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var keyboardWindow: NSWindow?
    private var mouseWindow: NSWindow?
    private var positionGuideWindow: NSWindow?
    private let settings: AppSettings
    private let keyboardViewModel: KeyboardOverlayViewModel
    private let snappingManager: OverlaySnappingManager
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
        self.snappingManager = OverlaySnappingManager(settings: settings, keyboardWindow: keyboardWindow, mouseWindow: mouseWindow)
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
            positionMouseWindow()
            SkyLightOperator.shared.delegateWindow(mouseWindow)
            
            mouseWindow.orderFrontRegardless()
            return mouseWindow.isVisible
        } else {
            let keyboardWindow = makeWindowIfNeeded()
            resizeWindow(to: settings.keyboardWindowSize, refreshGuide: false)
            SkyLightOperator.shared.delegateWindow(keyboardWindow)
            
            keyboardWindow.orderFrontRegardless()
            return keyboardWindow.isVisible
        }
    }

    func hide() {
        keyboardWindow?.orderOut(nil)
        mouseWindow?.orderOut(nil)
        snappingManager.clearPositionGuide()
        snappingManager.keyboardSnapLockOrigin = nil
        snappingManager.mouseSnapLockOrigin = nil
        snappingManager.keyboardSnapSuppressionOrigin = nil
        snappingManager.mouseSnapSuppressionOrigin = nil
        snappingManager.keyboardSessionHasSnap = false
        snappingManager.mouseSessionHasSnap = false
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
    
    func defaultWindowPlacement(isKeyboard: Bool, windowSize: NSSize, screenFrame: NSRect) -> NSPoint {
        if isKeyboard {
            return NSPoint(
                x: screenFrame.midX - (windowSize.width / 2),
                y: screenFrame.midY - (windowSize.height / 2)
            )
        } else {
            let inset: CGFloat = 16
            let x = screenFrame.minX + inset
            let y = screenFrame.minY + inset
            return NSPoint(x: x, y: y)
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
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.aspectRatio = NSSize(width: 8, height: 3)
        window.minSize = NSSize(width: 640, height: 240)
        window.maxSize = NSSize(width: 1440, height: 540)
        window.dragHandler = { [weak self] event, phase in
            self?.snappingManager.handleWindowDrag(phase: phase, window: window)
        }
        
        self.keyboardWindow = window
        self.snappingManager.keyboardWindow = window
        
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

    private func resizeWindow(to size: WindowSize, refreshGuide: Bool = true) {
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
                newOrigin = defaultWindowPlacement(isKeyboard: true, windowSize: normalizedSize, screenFrame: frame)
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
        snappingManager.keyboardSnapLockOrigin = nil
        snappingManager.keyboardSnapSuppressionOrigin = nil
        snappingManager.keyboardSessionHasSnap = false
        if refreshGuide {
            snappingManager.refreshPositionGuide(for: keyboardWindow)
        }
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
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.aspectRatio = NSSize(width: 1, height: 1)
        window.minSize = NSSize(width: 64, height: 64)
        window.maxSize = NSSize(width: 64, height: 64)
        window.dragHandler = { [weak self] event, phase in
            self?.snappingManager.handleWindowDrag(phase: phase, window: window)
        }
        
        self.mouseWindow = window
        self.snappingManager.mouseWindow = window
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: mouseWindow
        )
        
        return window
    }
    
    func positionMouseWindow() {
        guard let mouseWindow else { return }
        let screen = NSScreen.main ?? mouseWindow.screen ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let mouseWindowPosition = settings.mouseWindowPosition
        
        let newOrigin: NSPoint
        if mouseWindowPosition != .zero {
            newOrigin = mouseWindowPosition
        } else {
            newOrigin = defaultWindowPlacement(isKeyboard: false, windowSize: mouseWindow.frame.size, screenFrame: frame)
        }
        
        isApplyingProgrammaticSnap = true
        mouseWindow.setFrameOrigin(newOrigin)
        isApplyingProgrammaticSnap = false
        snappingManager.mouseSnapLockOrigin = nil
        snappingManager.mouseSnapSuppressionOrigin = nil
        snappingManager.mouseSessionHasSnap = false
        settings.mouseWindowPosition = newOrigin
    }
    
    //MARK: - Window Event Handlers
    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard !isApplyingProgrammaticResize, !isApplyingProgrammaticSnap else { return }
        
        if window == keyboardWindow {
            settings.keyboardWindowPosition = window.frame.origin
        } else if window == mouseWindow {
            settings.mouseWindowPosition = window.frame.origin
        }
        
        snappingManager.refreshPositionGuide(for: window)
        snappingManager.scheduleGuideAutoHide()
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
