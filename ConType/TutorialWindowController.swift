//
//  TutorialWindowController.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/27/26.
//

import AppKit
import SwiftUI

/// The controller for the tutorial window, manages the lifecycle of the window and serves as a bridge between the SwiftUI view and the app's logic.
@MainActor
final class TutorialWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    var openSettings: (() -> Void)?
    var updateCoordinatorVisibility: (() -> Void)?
    
    private let settings: AppSettings
    private var viewModel: TutorialViewModel
    private var window: NSWindow?
    
    init(settings: AppSettings) {
        self.settings = settings
        self.viewModel = TutorialViewModel(settings: settings)
        super.init()
        
        viewModel.onComplete = { [weak self] in
            self?.close()
        }
        
        viewModel.openSettings = { [weak self] in
            self?.openSettings?()
        }
        
        viewModel.updateCoordinatorVisibilty = { [weak self] in
            self?.updateCoordinatorVisibility?()
        }
    }
    
    /// A computed property that checks if the tutorial window is currently visible by accessing the `isVisible` property of the window.
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    /// Shows the tutorial window. If the window doesn't exist yet, it creates it using `makeWindowIfNeeded()`, then makes it key and orders it to the front.
    func show() {
        let window = makeWindowIfNeeded()
        window.makeKeyAndOrderFront(nil)
    }
    
    /// Closes the tutorial window by calling `performClose(nil)`.
    func close() {
        window?.performClose(nil)
    }
    
    /// NSWindowDelegate method that gets called when the window is about to close.
    /// - Parameter notification: The notification object containing information about the window closing event.
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
    
    // MARK: - Tutorial Input Callbacks
    /// A computed property that checks if the keyboard overlay is currently visible by accessing the `keyboardOverlayVisible` property of the tutorial view model.
    var isKeboardVisible: Bool {
        viewModel.keyboardOverlayVisible
    }
    
    /// A computed property that checks if the mouse overlay is currently visible by accessing the `mouseOverlayVisible` property of the tutorial view model.
    var isMouseVisible: Bool {
        viewModel.mouseOverlayVisible
    }
    
    /// Forwards a keyboard overlay activation event to the tutorial view model.
    func onKeyboardOverlayActivated() {
        viewModel.handleKeyboardOverlayActivated()
    }
    
    /// Forwards a mouse overlay activation event to the tutorial view model.
    func onMouseOverlayActivated() {
        viewModel.handleMouseOverlayActivated()
    }
    
    /// Forwards a keyboard overlay dismissal event triggered by the guide button to the tutorial view model.
    func dismissOverlayViaGuideButtonIfNeeded() {
        viewModel.handleDismissOverlayViaGuideButton()
    }
    
    /// Forwards a movement event with direction and trigger to the tutorial view model.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` indicating the movement direction.
    ///   - trigger: The `OverlayMoveTrigger` indicating how the movement was triggered.
    func moveSelection(
        _ direction: OverlayMoveDirection,
        trigger: OverlayMoveTrigger = .press
    ) {
        viewModel.handleMove(direction, trigger: trigger)
    }
    
    /// Forwards a mouse movement event with a delta vector to the tutorial view model.
    /// - Parameter delta: A `CGVector` representing the change in mouse position.
    func moveMouse(by delta: CGVector) {
        viewModel.handleMouseMove(by: delta)
    }
    
    /// Forwards a scroll event with a delta vector to the tutorial view model.
    func activateSelectedKey() {
        viewModel.activateSelectedKey()
    }
    
    
    /// Forwards a backspace key activation event to the tutorial view model.
    func activateBackspaceKey() {
        viewModel.activateBackspaceKey()
    }
    
    /// Forwards a space key activation event to the tutorial view model.
    func activateSpaceKey() {
        viewModel.activateSpaceKey()
    }
    
    /// Forwards an enter key activation event to the tutorial view model.
    func activateEnterKey() {
        viewModel.activateEnterKey()
    }
    
    /// Forwards a shift key activation event to the tutorial view model, with an optional parameter to indicate if it should cycle to caps lock.
    /// - Parameter cyclesToCapsLock: A `Bool` indicating whether the shift key activation should cycle to caps lock.
    func activateShiftShortcut(cyclesToCapsLock: Bool) {
        viewModel.activateShiftShortcut(cyclesToCapsLock: cyclesToCapsLock)
    }
    
    /// Forwards a caps lock key activation event to the tutorial view model.
    func activateCapsLockShortcut() {
        viewModel.activateCapsLockShortcut()
    }
    
    func moveCaretLeft() {
        viewModel.moveCaretLeft()
    }
    
    func moveCaretRight() {
        viewModel.moveCaretRight()
    }
    
    /// Forwards a mouse button activation event to the tutorial view model, indicating whether it's a mouse down or mouse up event based on the `CGEventType`.
    /// - Parameter eventType: The `CGEventType` indicating the type of mouse event (e.g., left mouse down, right mouse up).
    func activateMouseButton(_ eventType: CGEventType) {
        if eventType == .leftMouseDown || eventType == .rightMouseDown {
            viewModel.handleMouseClick(isDown: true)
        } else if eventType == .leftMouseUp || eventType == .rightMouseUp {
            viewModel.handleMouseClick(isDown: false)
        }
    }
        
    
    /// Creates the tutorial window if it doesn't exist, sets up the hosting controller with the tutorial view and configures the window properties.
    /// - Returns: An `NSWindow` containing the tutorial view.
    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }
        
        let screen = NSScreen.main ?? window?.screen ?? NSScreen.screens.first
        let frame = screen?.visibleFrame
        
        let hostingController = NSHostingController(
            rootView: TutorialView(viewModel: viewModel, settings: settings)
                .frame(minWidth: 960, minHeight: 540)
        )
        
        hostingController.sizingOptions = .minSize
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.autoresizingMask = [.width, .height]

        
        let dimension = NSSize(
            width: (frame?.width ?? 1920) / 2,
            height: max(frame?.height ?? 1080, 1080) / 2
        )
        
        let origin = NSPoint(
            x: (frame?.midX ?? 960) - (dimension.width / 2),
            y: (frame?.midY ?? 540) - (dimension.height / 2)
        )
        
        let window = NSWindow(
            contentRect: NSRect(
                x: origin.x,
                y: origin.y,
                width: dimension.width,
                height: dimension.height
            ),
            styleMask: [.titled, .resizable, .fullSizeContentView, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingController.view
        window.hasShadow = true
        window.delegate = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 960, height: 540)
        
        self.window = window
        return window
    }
}
