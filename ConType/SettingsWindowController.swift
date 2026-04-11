import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let settings: AppSettings
    private let onRequestControllerBindingCapture: (@escaping (ControllerToggleBinding) -> Void) -> Void
    private let onRequestControllerActionButtonCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    private let onCancelControllerCapture: () -> Void
    private let onRestartOnboarding: () -> Void
    private var window: NSWindow?

    init(
        settings: AppSettings,
        onRequestControllerBindingCapture: @escaping (@escaping (ControllerToggleBinding) -> Void) -> Void,
        onRequestControllerActionButtonCapture: @escaping (@escaping (ControllerAssignableButton) -> Void) -> Void,
        onCancelControllerCapture: @escaping () -> Void,
        onRestartOnboarding: @escaping () -> Void
    ) {
        self.settings = settings
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

        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                onRequestControllerBindingCapture: onRequestControllerBindingCapture,
                onRequestControllerActionButtonCapture: onRequestControllerActionButtonCapture,
                onCancelControllerCapture: onCancelControllerCapture,
                onRestartOnboarding: onRestartOnboarding
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.center()
        window.title = "Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 520)
        window.maxSize = NSSize(width: 560, height: 520)

        self.window = window
        return window
    }
}
