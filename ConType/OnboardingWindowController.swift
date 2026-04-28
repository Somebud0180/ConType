import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onCompletion: (() -> Void)?
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
            self?.onCompletion?()
            self?.close()
        }
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(startAtWelcome: Bool) {
        let window = makeWindowIfNeeded()
        viewModel.prepareForPresentation(startAtWelcome: startAtWelcome)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }

    func handleShortcutActivation() {
        viewModel.handleShortcutActivation()
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stop()
        onClose?()
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(
            rootView: OnboardingView(settings: settings, viewModel: viewModel)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.title = "Welcome to ConType"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 400)
        window.maxSize = NSSize(width: 540, height: 600)

        self.window = window
        return window
    }
}
