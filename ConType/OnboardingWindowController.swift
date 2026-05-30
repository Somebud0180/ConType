//
//  OnboardingWindowController.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import AppKit
import SwiftUI

/// The controller for the onboarding window
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    var openSettings: (() -> Void)?
    var openTutorial: (() -> Void)?
    var onAccessibilityTrustChanged: ((Bool) -> Void)? {
        didSet {
            viewModel.onAccessibilityTrustChanged = onAccessibilityTrustChanged
        }
    }

    private let settings: AppSettings
    private let viewModel: OnboardingViewModel
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
        self.viewModel = OnboardingViewModel(settings: settings)
        super.init()

        viewModel.onComplete = { [weak self] in
            self?.close()
        }
        
        viewModel.openSettings = { [weak self] in
            self?.openSettings?()
            self?.close()
        }
        
        viewModel.openTutorial = { [weak self] in
            self?.openTutorial?()
            self?.close()
        }
    }

    var isVisible: Bool {
        window?.isVisible == true
    }
    
    /// Show the onboarding view, prepare the window, initialize with the view model and make it appear front and center.
    /// - Parameter startAtWelcome: Wether to explicitly start the onboarding view at the beginning.
    func show(startAtWelcome: Bool) {
        let window = makeWindowIfNeeded()
        viewModel.prepareForPresentation(startAtWelcome: startAtWelcome)
        window.makeKeyAndOrderFront(nil)
    }
    
    /// Calls the window to close.
    func close() {
        window?.performClose(nil)
    }
    
    /// Calls the view model to handle when the overlay shortcut is called.
    func handleShortcutActivation() {
        viewModel.handleShortcutActivation()
    }
    
    /// NSWindowDelegate method that gets called when the window is about to close.
    /// - Parameter notification: The notification object containing information about the window closing event. 
    func windowWillClose(_ notification: Notification) {
        viewModel.stop()
        onClose?()
    }
    
    /// Creates the onboarding window if it doesn't exist, sets up the hosting controller with the onboarding view and configures the window properties.
    /// - Returns: An `NSWindow` containing the onboarding view
    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }
        
        let screen = NSScreen.main ?? window?.screen ?? NSScreen.screens.first
        let frame = screen?.visibleFrame

        let hostingController = NSHostingController(
            rootView: OnboardingView(settings: settings, viewModel: viewModel)
        )
        
        let origin = NSPoint(
            x: (frame?.midX ?? 960) - (400 / 2),
            y: (frame?.midY ?? 540) - (480 / 2)
        )
        
        debugPrint("Origin: \(origin), Screen Frame: \(frame?.debugDescription ?? "nil")")
        
        let window = NSWindow(
            contentRect: NSRect(x: origin.x, y: origin.y, width: 400, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        debugPrint("Widow Origin: \(window.frame.origin), Window Size: \(window.frame.size)")
        
        window.contentViewController = hostingController
        window.title = "Welcome to ConType"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 480)
        window.maxSize = NSSize(width: 400, height: 480)

        self.window = window
        return window
    }
}
