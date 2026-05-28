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
    
    private let settings: AppSettings
    private var viewModel: TutorialViewModel?
    private var window: NSWindow?
    
    init(
        settings: AppSettings,
    ) {
        self.settings = settings
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
    /// Forwards a keyboard overlay activation event to the tutorial view model.
    func onKeyboardOverlayActivated() {
        viewModel?.handleKeyboardOverlayActivated()
    }
    
    /// Forwards a mouse overlay activation event to the tutorial view model.
    func onMouseOverlayActivated() {
        viewModel?.handleMouseOverlayActivated()
    }
    
    func dismissOverlayViaGuideButtonIfNeeded() {
        viewModel?.handleDismissOverlayViaGuideButton()
    }
    
    /// Forwards a movement event with direction and trigger to the tutorial view model.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` indicating the movement direction.
    ///   - trigger: The `OverlayMoveTrigger` indicating how the movement was triggered.
    @discardableResult func moveSelection(
        _ direction: OverlayMoveDirection,
        trigger: OverlayMoveTrigger = .press
    ) {
        viewModel?.handleMove(direction, trigger: trigger)
    }
    
    /// Creates the tutorial window if it doesn't exist, sets up the hosting controller with the tutorial view and configures the window properties.
    /// - Returns: An `NSWindow` containing the tutorial view.
    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }
        
        let screen = NSScreen.main ?? window?.screen ?? NSScreen.screens.first
        let frame = screen?.visibleFrame
        
        let viewModel = TutorialViewModel(settings: settings)
        self.viewModel = viewModel
        
        let hostingController = NSHostingController(
            rootView: TutorialView(viewModel: viewModel, settings: settings)
        )
        
        let dimension = NSSize(
            width: (frame?.width ?? 1920) / 2,
            height: (frame?.height ?? 1080) / 2
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
            styleMask: [.borderless, .resizable, .fullScreen, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 960, height: 540)
        
        self.window = window
        return window
    }
}
