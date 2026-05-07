import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    
    private let settings: AppSettings
    private let joystick: JoystickInputModel
    private let onRequestControllerBindingCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    private let onRequestControllerActionButtonCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    private let onCancelControllerCapture: () -> Void
    private let onRestartOnboarding: () -> Void
    private var window: NSWindow?
    
    init(
        settings: AppSettings,
        joystick: JoystickInputModel,
        onRequestControllerBindingCapture: @escaping (@escaping (ControllerAssignableButton) -> Void) -> Void,
        onRequestControllerActionButtonCapture: @escaping (@escaping (ControllerAssignableButton) -> Void) -> Void,
        onCancelControllerCapture: @escaping () -> Void,
        onRestartOnboarding: @escaping () -> Void
    ) {
        self.settings = settings
        self.joystick = joystick
        self.onRequestControllerBindingCapture = onRequestControllerBindingCapture
        self.onRequestControllerActionButtonCapture = onRequestControllerActionButtonCapture
        self.onCancelControllerCapture = onCancelControllerCapture
        self.onRestartOnboarding = onRestartOnboarding
    }
    
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    func show() {
        let window = makeWindowIfNeeded()
        window.makeKeyAndOrderFront(nil)
    }
    
    func close() {
        window?.performClose(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
    
    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }
        let screen = NSScreen.main ?? window?.screen ?? NSScreen.screens.first
        let frame = screen?.visibleFrame
        
        let viewModel = SettingsViewModel(
            settings: settings,
            joystick: joystick,
            onRequestControllerBindingCapture: onRequestControllerBindingCapture,
            onRequestControllerActionButtonCapture: onRequestControllerActionButtonCapture,
            onCancelControllerCapture: onCancelControllerCapture,
            onRestartOnboarding: onRestartOnboarding
        )
        
        let hostingController = NSHostingController(
            rootView: SettingsView(viewModel: viewModel)
        )
        
        let origin = NSPoint(
            x: (frame?.midX ?? 960) - (560 / 2),
            y: (frame?.midY ?? 540) - (520 / 2)
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: origin.x, y: origin.y, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.title = "Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 240)
        window.maxSize = NSSize(width: 560, height: 600)
        
        self.window = window
        return window
    }
}
