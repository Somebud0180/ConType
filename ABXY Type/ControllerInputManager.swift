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
    private var lastMoveTimestamp = Date.distantPast
    private let moveDebounce: TimeInterval = 0.15
    private var pendingToggleCapture: ((ControllerToggleBinding) -> Void)?

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
        configure(controller)
    }

    private func configure(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad)
            return
        }

        if let microGamepad = controller.microGamepad {
            configureMicroGamepad(microGamepad)
        }
    }

    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.isGuideHeld = pressed
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

    private func sendMove(_ direction: OverlayMoveDirection) {
        let now = Date()
        guard now.timeIntervalSince(lastMoveTimestamp) > moveDebounce else { return }
        lastMoveTimestamp = now
        onMove?(direction)
    }

    private func handleFaceButton(_ faceButton: ControllerFaceButton) {
        if isGuideHeld {
            let recorded = ControllerToggleBinding(faceButton: faceButton)
            if let pendingToggleCapture {
                self.pendingToggleCapture = nil
                pendingToggleCapture(recorded)
                return
            }

            if isToggleEnabled && toggleBinding.faceButton == faceButton {
                onToggle?()
            }
            return
        }

        let primaryPress: ControllerFaceButton = invertControllerFaceButtons ? .east : .south
        let secondaryBackspace: ControllerFaceButton = invertControllerFaceButtons ? .south : .east

        if faceButton == primaryPress {
            onSelect?()
        } else if faceButton == secondaryBackspace {
            onBackspace?()
        }
    }
}