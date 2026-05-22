import AppKit
import Combine
import SkyLightWindow
import SwiftUI

enum DragPhase { case began, changed, ended }

private final class NonActivatingOverlayPanel: NSPanel {
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
    // How far the user has to pull before freeing from snap
    @State private var keyboardSnapDistance: CGFloat = 72
    @State private var mouseSnapDistance: CGFloat = 44
    
    private var hasShownKeyboard = false
    private var isApplyingProgrammaticResize = false
    private var guideHideWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var keyboardWindow: NSWindow?
    private var mouseWindow: NSWindow?
    private var positionGuideWindow: NSWindow?
    private let settings: AppSettings
    private let keyboardViewModel: KeyboardOverlayViewModel
    private let positionGuideModel = OverlayPositionGuideModel()
    private let keyEmitter = KeyEmitter()
    
    // Snap/Drag variables
    private var isApplyingProgrammaticSnap = false
    private var keyboardSnapLockOrigin: NSPoint?
    private var mouseSnapLockOrigin: NSPoint?
    private var keyboardSnapSuppressionOrigin: NSPoint?
    private var mouseSnapSuppressionOrigin: NSPoint?
    private var keyboardSessionHasSnap = false
    private var mouseSessionHasSnap = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var virtualWindowOrigin: NSPoint = .zero

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
        clearPositionGuide()
        keyboardSnapLockOrigin = nil
        mouseSnapLockOrigin = nil
        keyboardSnapSuppressionOrigin = nil
        mouseSnapSuppressionOrigin = nil
        keyboardSessionHasSnap = false
        mouseSessionHasSnap = false
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
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.aspectRatio = NSSize(width: 8, height: 3)
        window.minSize = NSSize(width: 640, height: 240)
        window.maxSize = NSSize(width: 1440, height: 540)
        window.dragHandler = { [weak self] event, phase in
            self?.handleWindowDrag(phase: phase, window: window)
        }
        
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
        keyboardSnapLockOrigin = nil
        keyboardSnapSuppressionOrigin = nil
        keyboardSessionHasSnap = false
        if refreshGuide {
            refreshPositionGuide(for: keyboardWindow)
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
            self?.handleWindowDrag(phase: phase, window: window)
        }
        
        self.mouseWindow = window
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: mouseWindow
        )
        
        return window
    }

    //MARK: - Position Guide Logic
    private func makePositionGuideWindowIfNeeded(for screenFrame: NSRect) -> NSWindow {
        if let positionGuideWindow {
            if positionGuideWindow.frame != screenFrame {
                positionGuideWindow.setFrame(screenFrame, display: false)
            }
            return positionGuideWindow
        }
        
        let hostingController = NSHostingController(
            rootView: OverlayPositionGuideView(model: positionGuideModel)
        )
        let baseMask: NSWindow.StyleMask = [
            .borderless, .fullSizeContentView,
        ]
        let window = NonActivatingOverlayPanel(
            contentRect: screenFrame,
            styleMask: baseMask.union(.nonactivatingPanel),
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        
        self.positionGuideWindow = window
        return window
    }
    
    private func refreshPositionGuide(for window: NSWindow) {
        guard let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else {
            clearPositionGuide()
            return
        }
        
        let screenRect = NSRect(origin: screenFrame.origin, size: screenFrame.size)
        positionGuideModel.screenFrame = screenRect
        
        if window == keyboardWindow {
            let targetFrame = keyboardGuideTargetFrame(for: window.frame, screenFrame: screenRect)
            let distance = centerDistance(between: window.frame, and: targetFrame)
            let revealDistance: CGFloat = 88
            let snapDistance: CGFloat = 24
            let releaseDistance: CGFloat = keyboardSessionHasSnap ? 156 : 96
            let suppressionDistance: CGFloat = keyboardSessionHasSnap ? 100 : 68
            
            if let snapOrigin = keyboardSnapLockOrigin {
                let movedAwayDistance = originDistance(between: window.frame.origin, and: snapOrigin)
                if movedAwayDistance < releaseDistance {
                    clearPositionGuide()
                    return
                }
                keyboardSnapSuppressionOrigin = snapOrigin
                keyboardSnapLockOrigin = nil
            }
            
            if let suppressionOrigin = keyboardSnapSuppressionOrigin {
                let suppressionOffset = originDistance(between: window.frame.origin, and: suppressionOrigin)
                if suppressionOffset < suppressionDistance {
                    clearPositionGuide()
                    return
                }
                keyboardSnapSuppressionOrigin = nil
            }
            
            if distance <= snapDistance {
                snapKeyboardWindow(to: targetFrame.origin)
                clearPositionGuide()
                return
            }
            
            if distance <= revealDistance && distance > 1 {
                positionGuideModel.targets = [OverlayPositionGuideTarget(kind: .keyboard, frame: targetFrame)]
                makePositionGuideWindowIfNeeded(for: screenRect).orderFrontRegardless()
            } else {
                clearPositionGuide()
            }
        } else if window == mouseWindow {
            let targets = mouseGuideTargets(for: window.frame.size, screenFrame: screenRect)
            guard let nearestTarget = targets.min(by: {
                originDistance(between: window.frame.origin, and: $0.frame.origin) < originDistance(between: window.frame.origin, and: $1.frame.origin)
            }) else {
                clearPositionGuide()
                return
            }
            
            let distance = originDistance(between: window.frame.origin, and: nearestTarget.frame.origin)
            let revealDistance: CGFloat = 52
            let snapDistance: CGFloat = 18
            let releaseDistance: CGFloat = mouseSessionHasSnap ? 108 : 64
            let suppressionDistance: CGFloat = mouseSessionHasSnap ? 72 : 44
            
            if let snapOrigin = mouseSnapLockOrigin {
                let movedAwayDistance = originDistance(between: window.frame.origin, and: snapOrigin)
                if movedAwayDistance < releaseDistance {
                    clearPositionGuide()
                    return
                }
                mouseSnapSuppressionOrigin = snapOrigin
                mouseSnapLockOrigin = nil
            }
            
            if let suppressionOrigin = mouseSnapSuppressionOrigin {
                let suppressionOffset = originDistance(between: window.frame.origin, and: suppressionOrigin)
                if suppressionOffset < suppressionDistance {
                    clearPositionGuide()
                    return
                }
                mouseSnapSuppressionOrigin = nil
            }
            
            if distance <= snapDistance {
                snapMouseWindow(to: nearestTarget.frame.origin)
                clearPositionGuide()
                return
            }
            
            if distance <= revealDistance && distance > 1 {
                positionGuideModel.targets = [nearestTarget]
                makePositionGuideWindowIfNeeded(for: screenRect).orderFrontRegardless()
            } else {
                clearPositionGuide()
            }
        } else {
            clearPositionGuide()
        }
    }
    
    private func clearPositionGuide() {
        guideHideWorkItem?.cancel()
        guideHideWorkItem = nil
        positionGuideWindow?.orderOut(nil)
        positionGuideModel.clear()
    }
    
    private func scheduleGuideAutoHide() {
        guideHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.guideHideWorkItem = nil
            self?.positionGuideWindow?.orderOut(nil)
            self?.positionGuideModel.clear()
            self?.keyboardSessionHasSnap = false
            self?.mouseSessionHasSnap = false
        }
        guideHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }
    
    private func snapKeyboardWindow(to origin: NSPoint) {
        guard let keyboardWindow, keyboardWindow.frame.origin != origin else { return }
        isApplyingProgrammaticSnap = true
        keyboardWindow.setFrameOrigin(origin)
        isApplyingProgrammaticSnap = false
        keyboardSnapLockOrigin = origin
        keyboardSnapSuppressionOrigin = nil
        keyboardSessionHasSnap = true
        settings.keyboardWindowPosition = origin
    }
    
    private func snapMouseWindow(to origin: NSPoint) {
        guard let mouseWindow, mouseWindow.frame.origin != origin else { return }
        isApplyingProgrammaticSnap = true
        mouseWindow.setFrameOrigin(origin)
        isApplyingProgrammaticSnap = false
        mouseSnapLockOrigin = origin
        mouseSnapSuppressionOrigin = nil
        mouseSessionHasSnap = true
        settings.mouseWindowPosition = origin
    }
    
    private func keyboardGuideTargetFrame(for currentFrame: NSRect, screenFrame: NSRect) -> NSRect {
        NSRect(
            x: screenFrame.midX - (currentFrame.width / 2),
            y: screenFrame.midY - (currentFrame.height / 2),
            width: currentFrame.width,
            height: currentFrame.height
        )
    }
    
    private func mouseGuideTargets(for windowSize: NSSize, screenFrame: NSRect) -> [OverlayPositionGuideTarget] {
        let inset: CGFloat = 16
        let width = windowSize.width
        let height = windowSize.height
        
        let bottomLeft = NSRect(
            x: screenFrame.minX + inset,
            y: screenFrame.minY + inset,
            width: width,
            height: height
        )
        let bottomRight = NSRect(
            x: max(screenFrame.minX + inset, screenFrame.maxX - inset - width),
            y: screenFrame.minY + inset,
            width: width,
            height: height
        )
        let topLeft = NSRect(
            x: screenFrame.minX + inset,
            y: max(screenFrame.minY + inset, screenFrame.maxY - inset - height),
            width: width,
            height: height
        )
        let topRight = NSRect(
            x: max(screenFrame.minX + inset, screenFrame.maxX - inset - width),
            y: max(screenFrame.minY + inset, screenFrame.maxY - inset - height),
            width: width,
            height: height
        )
        
        return [
            OverlayPositionGuideTarget(kind: .mouse, frame: bottomLeft),
            OverlayPositionGuideTarget(kind: .mouse, frame: bottomRight),
            OverlayPositionGuideTarget(kind: .mouse, frame: topLeft),
            OverlayPositionGuideTarget(kind: .mouse, frame: topRight)
        ]
    }
    
    private func centerDistance(between first: NSRect, and second: NSRect) -> CGFloat {
        hypot(first.midX - second.midX, first.midY - second.midY)
    }
    
    private func originDistance(between first: NSPoint, and second: NSPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
    
    private func defaultWindowPlacement(isKeyboard: Bool, windowSize: NSSize, screenFrame: NSRect) -> NSPoint {
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
        mouseSnapLockOrigin = nil
        mouseSnapSuppressionOrigin = nil
        mouseSessionHasSnap = false
        settings.mouseWindowPosition = newOrigin
    }
    
    private func handleWindowDrag(phase: DragPhase, window: NSWindow) {
        let currentGlobalMouse = NSEvent.mouseLocation
        
        switch phase {
        case .began:
            dragStartMouseLocation = currentGlobalMouse
            dragStartWindowOrigin = window.frame.origin
            virtualWindowOrigin = window.frame.origin
            
        case .changed:
            let deltaX = currentGlobalMouse.x - dragStartMouseLocation.x
            let deltaY = currentGlobalMouse.y - dragStartMouseLocation.y
            virtualWindowOrigin = NSPoint(
                x: dragStartWindowOrigin.x + deltaX,
                y: dragStartWindowOrigin.y + deltaY
            )
            
            let isKeyboard = (window === keyboardWindow)
            let isSnapped = isKeyboard ? keyboardSessionHasSnap : mouseSessionHasSnap
            let snapOrigin = isKeyboard ? keyboardSnapLockOrigin : mouseSnapLockOrigin
            
            if isSnapped, let snapPoint = snapOrigin {
                let pullDistance = originDistance(between: virtualWindowOrigin, and: snapPoint)
                let breakoutThreshold: CGFloat = isKeyboard ? keyboardSnapDistance : mouseSnapDistance
                
                if pullDistance > breakoutThreshold {
                    // Break out of the snap
                    if isKeyboard {
                        keyboardSessionHasSnap = false
                        keyboardSnapLockOrigin = nil
                    } else {
                        mouseSessionHasSnap = false
                        mouseSnapLockOrigin = nil
                    }
                    window.setFrameOrigin(virtualWindowOrigin)
                    refreshPositionGuide(for: window)
                }
            } else {
                window.setFrameOrigin(virtualWindowOrigin)
                refreshPositionGuide(for: window)
            }
            
        case .ended:
            break
        }
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
        
        refreshPositionGuide(for: window)
        scheduleGuideAutoHide()
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
