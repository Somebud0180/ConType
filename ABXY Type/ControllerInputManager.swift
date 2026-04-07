import Foundation
import GameController

final class ControllerInputManager: NSObject {
    var onToggle: (() -> Void)?
    var onMove: ((OverlayMoveDirection) -> Void)?
    var onSelect: (() -> Void)?
    var onBackspace: (() -> Void)?
    var isToggleEnabled = true
    var toggleBinding: ControllerToggleBinding = .default
    var invertControllerFaceButtons = false

    private var isGuideHeld = false
    private var lastGuidePressDate = Date.distantPast
    private let guideChordWindow: TimeInterval = 0.7
    private var lastMoveTimestamp = Date.distantPast
    private let moveDebounce: TimeInterval = 0.15
    private var pendingToggleCapture: ((ControllerToggleBinding) -> Void)?

#if DEBUG
    private func debugLog(_ message: String) { print("[Controller] \(message)") }
#else
    private func debugLog(_ message: String) {}
#endif

    func captureNextToggleBinding(_ onCaptured: @escaping (ControllerToggleBinding) -> Void) {
        pendingToggleCapture = onCaptured
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )

        // Receive input while the app is in the background (menu bar / accessory / non-activating panel)
        GCController.shouldMonitorBackgroundEvents = true
        debugLog("Background events monitoring enabled")

        // Optionally discover wireless controllers proactively
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        debugLog("Started wireless controller discovery")

        for controller in GCController.controllers() {
            configure(controller)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        debugLog("Controller connected: \(controller.vendorName ?? "Unknown")")
        configure(controller)
    }

    private func configure(_ controller: GCController) {
        debugLog("Configuring controller: \(controller.vendorName ?? "Unknown")")

        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad)
            // Fallback for controllers that surface the guide as a pause event (momentary)
            controller.controllerPausedHandler = { [weak self] _ in
                self?.recordGuidePress()
                self?.debugLog("controllerPausedHandler fired (guide momentary)")
            }
            debugLog("Configured as extended gamepad")
            return
        }

        if let microGamepad = controller.microGamepad {
            configureMicroGamepad(microGamepad)
            // Fallback for controllers that surface the guide as a pause event (momentary)
            controller.controllerPausedHandler = { [weak self] _ in
                self?.recordGuidePress()
                self?.debugLog("controllerPausedHandler fired (guide momentary)")
            }
            debugLog("Configured as micro gamepad")
        }
    }

    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        // Treat Home/Menu/Options as the "guide" modifier; also record moment of press for chorded detection
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.isGuideHeld = pressed
            if pressed {
                self?.recordGuidePress()
                self?.debugLog("Guide (Menu) pressed")
            } else {
                self?.debugLog("Guide (Menu) released")
            }
        }
        gamepad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.isGuideHeld = pressed
            if pressed {
                self?.recordGuidePress()
                self?.debugLog("Guide (Home) pressed")
            } else {
                self?.debugLog("Guide (Home) released")
            }
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.isGuideHeld = pressed
            if pressed {
                self?.recordGuidePress()
                self?.debugLog("Guide (Options) pressed")
            } else {
                self?.debugLog("Guide (Options) released")
            }
        }

        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleFaceButton(.south)
        }

        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleFaceButton(.east)
        }

        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleFaceButton(.west)
        }

        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleFaceButton(.north)
        }

        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.left)
        }

        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.right)
        }

        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.up)
        }

        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.down)
        }
    }

    private func configureMicroGamepad(_ gamepad: GCMicroGamepad) {
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleFaceButton(.south)
        }

        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.handleFaceButton(.west)
        }

        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.left)
        }

        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.right)
        }

        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.up)
        }

        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.sendMove(.down)
        }
    }

    private func recordGuidePress() {
        lastGuidePressDate = Date()
        debugLog("Guide press recorded at \(lastGuidePressDate)")
    }

    private var isGuideActive: Bool {
        isGuideHeld || Date().timeIntervalSince(lastGuidePressDate) < guideChordWindow
    }

    private func sendMove(_ direction: OverlayMoveDirection) {
        let now = Date()
        guard now.timeIntervalSince(lastMoveTimestamp) > moveDebounce else { return }
        lastMoveTimestamp = now
        debugLog("Move: \(direction)")
        onMove?(direction)
    }

    private func handleFaceButton(_ faceButton: ControllerFaceButton) {
        debugLog("Face button: \(faceButton) guideActive=\(isGuideActive)")
        if isGuideActive {
            let recorded = ControllerToggleBinding(faceButton: faceButton)
            if let pendingToggleCapture {
                self.pendingToggleCapture = nil
                pendingToggleCapture(recorded)
                debugLog("Captured toggle binding: \(recorded.faceButton)")
                return
            }

            if isToggleEnabled && toggleBinding.faceButton == faceButton {
                debugLog("Toggled overlay via controller binding")
                onToggle?()
            }
            return
        }

        let primaryPress: ControllerFaceButton = invertControllerFaceButtons ? .east : .south
        let secondaryBackspace: ControllerFaceButton = invertControllerFaceButtons ? .south : .east

        if faceButton == primaryPress {
            debugLog("Primary select triggered")
            onSelect?()
        } else if faceButton == secondaryBackspace {
            debugLog("Secondary backspace triggered")
            onBackspace?()
        }
    }
}
