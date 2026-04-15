import AppKit
import SwiftUI
import SkyLightWindow

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let keyboardViewModel = KeyboardOverlayViewModel()
    private let keyEmitter = KeyEmitter()
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    @discardableResult
    func show() -> Bool {
        let window = makeWindowIfNeeded()
        resizeWindow(to: settings.windowSize, center: true)
        SkyLightOperator.shared.delegateWindow(window)
        
        window.orderFrontRegardless()
        return window.isVisible
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    @discardableResult
    func moveSelection(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger = .press) -> Bool {
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
    
    func enlargeWindow() {
        switch settings.windowSize {
        case .small:
            resizeWindow(to: .medium)
            break
        case .medium:
            resizeWindow(to: .large)
            break
        case .large:
            break
        }
    }
    
    func shrinkWindow() {
        switch settings.windowSize {
        case .small:
            break
        case .medium:
            resizeWindow(to: .small)
            break
        case .large:
            resizeWindow(to: .medium)
            break
        }
    }
    
    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }
        
        let contentView = KeyboardOverlayView(settings: settings, viewModel: keyboardViewModel) { [weak self] key, modifiers in
            self?.keyEmitter.emit(key, modifiers: modifiers)
        }
        
        let windowDimensions = settings.windowSize.windowDimensions
        
        let hostingController = NSHostingController(rootView: contentView)
        let baseMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = NonActivatingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowDimensions.width, height: windowDimensions.height),
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
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentAspectRatio = NSSize(width: 5, height: 2)
        window.contentMinSize = NSSize(width: 800, height: 320)
        
        self.window = window
        return window
    }
    
    private func resizeWindow(to size: WindowSize, center: Bool = false) {
        guard let window else { return }
        let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        
        settings.windowSize = size
        let windowDimensions = settings.windowSize.windowDimensions
        
        // Limit window size to constraint
        let targetSize = NSSize(
            width: min(1400, max(800, windowDimensions.width)),
            height: min(500, max(320, windowDimensions.height))
        )
        
        // Limit window size to within screen bounds
        let normalizedSize = NSSize(
            width: min(frame.width - 80, targetSize.width),
            height: min(frame.height - 120, targetSize.height)
        )
        
        let origin = center ?
        NSPoint(
            x: frame.midX - (normalizedSize.width / 2),
            y: frame.midY - (normalizedSize.height / 2)
        ) :
        {
            let currentCenter = NSPoint(
                x: window.frame.origin.x + window.frame.size.width / 2,
                y: window.frame.origin.y + window.frame.size.height / 2
            )
            return NSPoint(
                x: currentCenter.x - normalizedSize.width / 2,
                y: currentCenter.y - normalizedSize.height / 2
            )
        }()
        
        window.setFrame(NSRect(origin: origin, size: normalizedSize), display: true, animate: true)
    }
}
