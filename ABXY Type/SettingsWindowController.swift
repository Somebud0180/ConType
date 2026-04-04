import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let settings: AppSettings
    private let onRequestControllerBindingCapture: (@escaping (ControllerToggleBinding) -> Void) -> Void
    private var window: NSWindow?

    init(
        settings: AppSettings,
        onRequestControllerBindingCapture: @escaping (@escaping (ControllerToggleBinding) -> Void) -> Void
    ) {
        self.settings = settings
        self.onRequestControllerBindingCapture = onRequestControllerBindingCapture
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = makeWindowIfNeeded()
        window.makeKeyAndOrderFront(nil)
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
                onRequestControllerBindingCapture: onRequestControllerBindingCapture
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.center()
        window.title = "Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 340)
        window.maxSize = NSSize(width: 500, height: 340)

        self.window = window
        return window
    }
}
