//
//  OverlayWindowController.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import AppKit
import Combine
import SkyLightWindow
import SwiftUI

/// The controller for the overlay windows, both the keyboard and mouse overlays.
/// - Began
/// - Changed
/// - Ended
enum DragPhase { case began, changed, ended }

/// A custom NSPanel subclass that doesn't become key or main, allowing mouse events to pass through to underlying windows. It also includes a drag handler closure that can be set to respond to mouse drag events for implementing the snapping behavior.
final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    var dragHandler: ((NSEvent, DragPhase) -> Void)?
    
    /// Overrides mouseDown to track dragging events. It calls the dragHandler closure with the appropriate phase for began, changed, and ended drag events.
    /// - Parameter event: The initial mouse down event that starts the drag tracking.
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

/// The main controller for managing the overlay windows, including showing/hiding, resizing, moving, and handling interactions with the keyboard and mouse overlays. It also manages the snapping behavior through the `OverlaySnappingManager` and emits key events via the `KeyEmitter`.
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
    
    /// Shows the appropriate overlay window based on the current mode (keyboard or mouse). It first hides any existing windows, then creates and positions the new window as needed, and finally makes it visible.
    /// - Returns: `true` if the window is visible after calling `show()`, `false` otherwise.
    @discardableResult func show() -> Bool {
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
    
    /// Hides both the keyboard and mouse overlay windows, clears any snapping guides, and resets the snapping state in the `OverlaySnappingManager`.
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
    
    /// Moves the current selection in the keyboard overlay in the specified direction, triggered by either a key press or a key hold.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` indicating which direction to move the selection.
    ///   - trigger: The `OverlayMoveTrigger` indicating whether the move was triggered by a key press or a key hold. Defaults to `.press`.
    /// - Returns: `true` if the selection was successfully moved, `false` otherwise.
    @discardableResult func moveSelection(
        _ direction: OverlayMoveDirection,
        trigger: OverlayMoveTrigger = .press
    ) -> Bool {
        keyboardViewModel.move(direction, trigger: trigger)
    }
    
    /// Activates the currently selected key in the keyboard overlay, emitting the corresponding key event through the `KeyEmitter`.
    func activateSelectedKey() {
        keyboardViewModel.activateSelected { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }
    }
    
    /// Activates the backspace key by emitting the corresponding key event through the `KeyEmitter`.
    func activateBackspaceKey() {
        keyEmitter.emit(keyCode: 51)
    }
    
    /// Activates the space key by emitting the corresponding key event through the `KeyEmitter`.
    func activateSpaceKey() {
        keyEmitter.emit(keyCode: 49)
    }
    
    /// Activates the enter/return key by emitting the corresponding key event through the `KeyEmitter`.
    func activateEnterKey() {
        keyEmitter.emit(keyCode: 36)
    }
    
    /// Activates the shift shortcut, toggling or cycling through shift states in the keyboard overlay. Calls the `cycleShiftShortcut` method on the `keyboardViewModel`.
    /// - Parameter cyclesToCapsLock: A `Bool` indicating whether cycling through shift states should also include toggling caps lock.
    func activateShiftShortcut(cyclesToCapsLock: Bool) {
        keyboardViewModel.cycleShiftShortcut(cyclesToCapsLock: cyclesToCapsLock)
    }
    
    /// Activates the caps lock shortcut, toggling caps lock state in the keyboard overlay. Calls the `toggleCapsLockShortcut` method on the `keyboardViewModel`.
    func activateCapsLockShortcut() {
        keyboardViewModel.toggleCapsLockShortcut()
    }
    
    /// Updates the keyboard overlay window size based on the current settings. It calls the `resizeWindow` method with the `keyboardWindowSize` from the settings.
    func updateWindowSize() {
        resizeWindow(to: settings.keyboardWindowSize)
    }
    
    /// Enlarges the keyboard overlay window to the next larger preset size. If currently in mouse mode, it switches back to keyboard mode and shows the keyboard overlay instead.
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
    
    /// Shrinks the keyboard overlay window to the next smaller preset size. If currently in mouse mode, it does nothing. If already at the smallest preset size and not in mouse mode, it switches to mouse mode and shows the mouse overlay instead.
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
    
    /// Calculates the default window placement for either the keyboard or mouse overlay based on the screen frame and the window size. For the keyboard overlay, it centers the window on the screen. For the mouse overlay, it places the window in the bottom-left corner with a small inset.
    /// - Parameters:
    ///   - isKeyboard: A `Bool` indicating whether the placement is for the keyboard overlay (`true`) or the mouse overlay (`false`).
    ///   - windowSize: The `NSSize` of the window to be placed, used for calculating the centered position for the keyboard overlay.
    ///   - screenFrame: The `NSRect` representing the visible frame of the screen, used for calculating the placement of the window within the screen bounds.
    /// - Returns: An `NSPoint` representing the origin where the window should be placed by default.
    func defaultWindowPlacement(isKeyboard: Bool, windowSize: NSSize, screenFrame: NSRect) -> NSPoint {
        if isKeyboard {
            return NSPoint(
                x:
                    screenFrame.midX - (windowSize.width / 2),
                y: screenFrame.midY - (windowSize.height / 2)
            )
        } else {
            let inset: CGFloat = 16
            let x = screenFrame.minX + inset
            let y = screenFrame.minY + inset
            return NSPoint(x: x, y: y)
        }
    }
    
    /// Creates the keyboard overlay window if it doesn't already exist. It sets up the content view with the `KeyboardOverlayView`, configures the window properties for the overlay, and adds observers for window movement and resizing to handle snapping and settings updates.
    /// - Returns: An `NSWindow` instance representing the keyboard overlay, either newly created or existing.
    private func makeWindowIfNeeded() -> NSWindow {
        if let keyboardWindow {
            return keyboardWindow
        }
        
        let contentView = KeyboardOverlayView(
            viewModel: keyboardViewModel
        ) { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }
            .preferredColorScheme(settings.preferredColorScheme.colorScheme)
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
    
    /// Resizes the keyboard overlay window to the specified size. It calculates the target size based on the preset or custom dimensions, ensures it fits within the screen bounds, and then applies the new frame to the window. It also handles positioning the window appropriately based on whether it's the first time showing it or if it's being resized after already being shown. Finally, it refreshes the snapping guides if needed.
    /// - Parameters:
    ///   - size: The `WindowSize` indicating the preset or custom size to resize the keyboard overlay to.
    ///   - refreshGuide: A `Bool` indicating whether to refresh the snapping guide after resizing. Defaults to `true`.
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
    
    /// Creates the mouse overlay window if it doesn't already exist. It sets up the content view with the `MouseOverlayView`, configures the window properties for the overlay, and adds an observer for window movement to handle snapping and settings updates.
    /// - Returns: An `NSWindow` instance representing the mouse overlay, either newly created or existing.
    private func makeMouseWindowIfNeeded() -> NSWindow {
        if let mouseWindow {
            return mouseWindow
        }
        
        let contentView = MouseOverlayView() { [weak self] in
            self?.settings.inMouseMode = false
            self?.show()
        }
            .preferredColorScheme(settings.preferredColorScheme.colorScheme)
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
    
    /// Positions the mouse overlay window based on the current settings. It calculates the new origin for the window either from the saved position in the settings or by using the default placement if no position is saved. It then applies the new frame origin to the window and resets any snapping state in the `OverlaySnappingManager`.
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
    /// Handles the window movement event for both the keyboard and mouse overlay windows. It updates the corresponding position in the settings when either window is moved, and refreshes the snapping guides through the `OverlaySnappingManager`. It also checks flags to prevent handling movements that are caused by programmatic resizing or snapping to avoid conflicts.
    /// - Parameter notification: The `Notification` object containing information about the window movement event, including the window that moved.
    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard !isApplyingProgrammaticResize, !isApplyingProgrammaticSnap else { return }
        
        if window == keyboardWindow {
            settings.keyboardWindowPosition = window.frame.origin
        } else if window == mouseWindow {
            settings.mouseWindowPosition = window.frame.origin
        }
        
        snappingManager.refreshPositionGuide(for: window)
    }
    
    /// Handles the window resize event for the keyboard overlay window. It updates the custom dimensions and position in the settings when the keyboard window finishes resizing, and sets the window size to custom. It also checks a flag to prevent handling resizes that are caused by programmatic resizing to avoid conflicts.
    /// - Parameter notification: The `Notification` object containing information about the window resize event, including the window that finished resizing.
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
