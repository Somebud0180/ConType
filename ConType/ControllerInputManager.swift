import Foundation
import GameController
import Combine

enum KeyboardMovementMode {
    case limited    // 4 Directional
    case full       // 8 Directional
    case mouse      // Similar to full but with different handling
}

enum MovementMode {
    case dpad
    case leftStick
    case rightStick
}

// ObservableObject for SwiftUI to observe joystick input
@MainActor
final class JoystickInputModel: ObservableObject {
    @Published var leftStick: CGVector = .zero
    @Published var rightStick: CGVector = .zero
    @Published var dPad: CGVector = .zero

    init(manager: ControllerInputManager) {
        // Subscribe to stick changes
        manager.onLeftStickChanged = { [weak self] vector in
            DispatchQueue.main.async {
                self?.leftStick = vector
            }
        }
        manager.onRightStickChanged = { [weak self] vector in
            DispatchQueue.main.async {
                self?.rightStick = vector
            }
        }
        manager.onDPadChanged = { [weak self] vector in
            DispatchQueue.main.async {
                self?.dPad = vector
            }
        }
    }
}

final class ControllerInputManager: NSObject {
    var onLeftStickChanged: ((CGVector) -> Void)?
    var onRightStickChanged: ((CGVector) -> Void)?
    var onDPadChanged: ((CGVector) -> Void)?
    var onToggle: (() -> Void)?
    var onMove: ((OverlayMoveDirection, OverlayMoveTrigger) -> Void)?
    var onMouseMove: ((CGVector) -> Void)?
    var onSelect: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onSpace: (() -> Void)?
    var onEnter: (() -> Void)?
    var onShift: (() -> Void)?
    var onCapsLock: (() -> Void)?
    var onLeftClickDown: (() -> Void)?
    var onLeftClickUp: (() -> Void)?
    var onRightClickDown: (() -> Void)?
    var onRightClickUp: (() -> Void)?
    var onEnlarge: (() -> Void)?
    var onShrink: (() -> Void)?
    var onGlyphStyleChanged: ((ControllerGlyphStyle) -> Void)?
    var onCaptureStateChanged: ((ControllerCaptureState) -> Void)?
    var onDetectedControllerChanged: ((DetectedController?) -> Void)?
    var onDismissWithGuideButton: (() -> Void)?

    var isToggleEnabled = true
    var toggleBinding: ControllerToggleBinding = .default
    var actionBindings: ControllerActionBindings = .default
    
    var leftStickInputType: AxisInputType = .overlayMovement {
        didSet { rebindSticksIfNeeded() }
    }
    
    var rightStickInputType: AxisInputType = .mouseMovement {
        didSet { rebindSticksIfNeeded() }
    }
    
    var padInputType: AxisInputType = .overlayMovement {
        didSet { rebindSticksIfNeeded() }
    }
    
    var dismissWithGuideButton = true
    var isOverlayVisible = false
    var keyboardMovementStyle: KeyboardMovementMode = .limited
    var leftStickDeadzone: CGFloat = 0.20
    var rightStickDeadzone: CGFloat = 0.20
    var mouseSensitivity: CGFloat = 400.0
    var mouseSmoothingAlpha: CGFloat = 0.65

    private var isGuideHeld = false {
        didSet { publishCaptureState() }
    }
    private var pressedAssignableButtons: Set<ControllerAssignableButton> = [] {
        didSet { publishCaptureState() }
    }
    private var lastGuidePressDate = Date.distantPast
    private let guideChordWindow: TimeInterval = 0.7

    private var pendingToggleCapture: ((ControllerToggleBinding) -> Void)?
    private var pendingAssignableButtonCapture: ((ControllerAssignableButton) -> Void)?

    private var directionPressCounts: [OverlayMoveDirection: Int] = [:]
    private var heldDirectionOrder: [OverlayMoveDirection] = []
    private var activeMoveDirection: OverlayMoveDirection?
    private var holdRepeatStep = 0
    private var holdRepeatWorkItem: DispatchWorkItem?
    private var suppressGuideChordUntilRelease = false
    
    // Internal state for analog handling
    private var filteredStick = CGVector(dx: 0, dy: 0)
    private var lastAnalogDirection: OverlayMoveDirection? = nil
    private var analogTimer: Timer? = nil
    private var lastAnalogUpdate = Date()

    // Variables for dpad hold repeat behavior
    private let padHoldRepeatInitialDelay: TimeInterval = 0.28
    private let padHoldRepeatInitialInterval: TimeInterval = 0.22
    private let padHoldRepeatMinimumInterval: TimeInterval = 0.055
    private let padHoldRepeatAcceleration: Double = 0.84
    
    // Variables for discrete stick hold repeat behavior
    private var stickHoldRepeatInitialDelay: TimeInterval = 1.0
    private var stickHoldRepeatInitialInterval: TimeInterval = 0.30
    private var stickHoldRepeatMinimumInterval: TimeInterval = 0.08
    private var stickHoldRepeatAcceleration: Double = 0.65
    
    // Variables for mouse mode
    private var joystickTickInterval: TimeInterval = 1.0 / 60.0
    
    // Augmented hold repeat variables
    private var holdRepeatInitialDelay: TimeInterval?
    private var holdRepeatInitialInterval: TimeInterval?
    private var holdRepeatMinimumInterval: TimeInterval?
    private var holdRepeatAcceleration: Double?
    
#if DEBUG
    private func debugLog(_ message: String) { print("[Controller] \(message)") }
#else
    private func debugLog(_ message: String) {}
#endif

    func captureNextToggleBinding(_ onCaptured: @escaping (ControllerToggleBinding) -> Void) {
        pendingToggleCapture = onCaptured
    }

    func captureNextAssignableButton(_ onCaptured: @escaping (ControllerAssignableButton) -> Void) {
        pendingAssignableButtonCapture = onCaptured
    }

    func cancelPendingCaptures() {
        pendingToggleCapture = nil
        pendingAssignableButtonCapture = nil
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect,
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

        refreshConnectedControllerGlyphStyle()
        publishCaptureState()
    }

    deinit {
        stopMoveRepeat(clearDirection: true)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Controller Connection Handling
    @objc
    private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        debugLog("Controller connected: \(controller.vendorName ?? "Unknown")")
        configure(controller)
        refreshConnectedControllerGlyphStyle()
    }

    @objc
    private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        debugLog("Controller disconnected: \(controller.vendorName ?? "Unknown")")

        // Avoid stale pressed state from a disconnected device.
        isGuideHeld = false
        pressedAssignableButtons.removeAll()
        stopMoveRepeat(clearDirection: true)
        lastAnalogDirection = nil
        stopAnalogTimerIfNeeded()
        filteredStick = CGVector(dx: 0, dy: 0)
        refreshConnectedControllerGlyphStyle()
    }

    // MARK: - Controller Handling
    private func configure(_ controller: GCController) {
        debugLog("Configuring controller: \(controller.vendorName ?? "Unknown")")

        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad)
            configureThumbstickButtonPresses(from: controller)
            // Fallback for very old systems where Menu/Home/Options aren't surfaced.
            // `controllerPausedHandler` is deprecated on macOS 10.15+. Only use when necessary.
            if #available(macOS 11.0, iOS 13.0, tvOS 13.0, *) {
                // On modern systems we already handle Menu/Home/Options via the input profile; no paused handler needed.
            } else {
                controller.controllerPausedHandler = { [weak self] _ in
                    self?.dismissOverlayViaGuideIfNeeded(momentary: true)
                    self?.debugLog("controllerPausedHandler fired (guide momentary)")
                }
            }
            debugLog("Configured as extended gamepad")
            return
        }

        if let microGamepad = controller.microGamepad {
            configureMicroGamepad(microGamepad)
            // Fallback for very old systems where Menu/Home/Options aren't surfaced.
            // `controllerPausedHandler` is deprecated on macOS 10.15+. Only use when necessary.
            if #available(macOS 11.0, iOS 13.0, tvOS 13.0, *) {
                // On modern systems we already handle Menu/Home/Options via the input profile; no paused handler needed.
            } else {
                controller.controllerPausedHandler = { [weak self] _ in
                    self?.dismissOverlayViaGuideIfNeeded(momentary: true)
                    self?.debugLog("controllerPausedHandler fired (guide momentary)")
                }
            }
            debugLog("Configured as micro gamepad")
        }
    }

    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        // Treat Home/Menu/Options as the "guide" modifier; also record moment of press for chorded detection.
        bindGuideButton(gamepad.buttonMenu, source: "Menu")
        bindGuideButton(gamepad.buttonHome, source: "Home")
        bindGuideButton(gamepad.buttonOptions, source: "Options")

        bindAssignableButton(gamepad.buttonA, as: .south)
        bindAssignableButton(gamepad.buttonB, as: .east)
        bindAssignableButton(gamepad.buttonX, as: .west)
        bindAssignableButton(gamepad.buttonY, as: .north)
        bindAssignableButton(gamepad.leftShoulder, as: .leftShoulder)
        bindAssignableButton(gamepad.rightShoulder, as: .rightShoulder)
        bindAssignableButton(gamepad.leftTrigger, as: .leftTrigger)
        bindAssignableButton(gamepad.rightTrigger, as: .rightTrigger)

        
        bindSticks(gamepad)
    }
    
    func bindSticks(_ gamepad: GCExtendedGamepad) {
        bindAnalogStick(gamepad.leftThumbstick, from: .leftStick, inputType: leftStickInputType)
        bindAnalogStick(gamepad.rightThumbstick, from: .rightStick, inputType: rightStickInputType)
        bindAnalogStick(gamepad.dpad, from: .dpad, inputType: padInputType)
    }
    
    private func rebindSticksIfNeeded() {
        for controller in GCController.controllers() {
            if let gamepad = controller.extendedGamepad {
                bindSticks(gamepad)
            } else if let gamepad = controller.microGamepad {
                bindAnalogStick(gamepad.dpad, from: .dpad, inputType: padInputType)
            }
        }
    }
    
    private func configureThumbstickButtonPresses(from controller: GCController) {
        let buttons = controller.physicalInputProfile.buttons
        buttons[GCInputLeftThumbstickButton]?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handleAssignableButtonChange(.leftStickPress, pressed: pressed)
        }

        buttons[GCInputRightThumbstickButton]?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handleAssignableButtonChange(.rightStickPress, pressed: pressed)
        }
    }

    private func configureMicroGamepad(_ gamepad: GCMicroGamepad) {
        bindAssignableButton(gamepad.buttonA, as: .south)
        bindAssignableButton(gamepad.buttonX, as: .west)
        bindAnalogStick(gamepad.dpad, from: .dpad, inputType: padInputType)
    }
    
    private func configureAxisInput() {
        // Handle binding axis inputs dynamically
        // Left Stick, Right Stick, D-pad as overlay movement or mouse movement
    }

    private func bindGuideButton(_ button: GCControllerButtonInput?, source: String) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setGuidePressed(pressed, source: source)
        }
    }

    private func setGuidePressed(_ pressed: Bool, source: String) {
        isGuideHeld = pressed
        if pressed {
            dismissOverlayViaGuideIfNeeded(momentary: false)
            debugLog("Guide (\(source)) pressed")
        } else {
            suppressGuideChordUntilRelease = false
        }
    }

    private func dismissOverlayViaGuideIfNeeded(momentary: Bool) {
        guard dismissWithGuideButton, isOverlayVisible else { return }

        suppressGuideChordUntilRelease = true
        if momentary {
            DispatchQueue.main.asyncAfter(deadline: .now() + guideChordWindow) { [weak self] in
                self?.suppressGuideChordUntilRelease = false
            }
        }

        debugLog("Dismissed overlay via guide button")
        onDismissWithGuideButton?()
    }

    private func bindAssignableButton(_ buttonInput: GCControllerButtonInput?, as button: ControllerAssignableButton) {
        buttonInput?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.updateRepeatTuning(for: .dpad)
            self?.handleAssignableButtonChange(button, pressed: pressed)
        }
    }

    private func handleAssignableButtonChange(_ button: ControllerAssignableButton, pressed: Bool) {
        if pressed {
            pressedAssignableButtons.insert(button)
            handleAssignableButtonPress(button)
        } else {
            pressedAssignableButtons.remove(button)
            handleAssignableButtonLift(button)
        }
    }

//    private func bindDirectionalInput(_ directionPad: GCControllerDirectionPad) {
//        directionPad.left.pressedChangedHandler = { [weak self] _, _, pressed in
//            self?.setDirectionalInput(.left, pressed: pressed)
//        }
//
//        directionPad.right.pressedChangedHandler = { [weak self] _, _, pressed in
//            self?.setDirectionalInput(.right, pressed: pressed)
//        }
//
//        directionPad.up.pressedChangedHandler = { [weak self] _, _, pressed in
//            self?.setDirectionalInput(.up, pressed: pressed)
//        }
//
//        directionPad.down.pressedChangedHandler = { [weak self] _, _, pressed in
//            self?.setDirectionalInput(.down, pressed: pressed)
//        }
//    }
    
    // MARK: - Analog Stick Handling
    private func bindAnalogStick(_ stick: GCControllerDirectionPad, from source: MovementMode, inputType: AxisInputType) {
        stick.valueChangedHandler = nil // Clear any existing handler to avoid conflicts when re-binding
        
        if inputType == .none {
            return
        }
        
        stick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }
            self.handleAnalogStick(x: xValue, y: yValue, keyboardMovementStyle: inputType == .mouseMovement ? .mouse : self.keyboardMovementStyle, from: source)
        }
    }
    
    private func handleAnalogStick(x: Float, y: Float, keyboardMovementStyle: KeyboardMovementMode, from source: MovementMode) {
        // Flip Y if needed to match your overlay coordinate system (usually up is positive on the stick y)
        let raw = CGVector(dx: CGFloat(x), dy: CGFloat(y))
        let rawMagnitude = sqrt(raw.dx * raw.dx + raw.dy * raw.dy)
        let joystickDeadzone = switch source {
        case .dpad: CGFloat(0)
        case .leftStick: leftStickDeadzone
        case .rightStick: rightStickDeadzone
        }

        // Notify observers of stick changes
        switch source {
        case .leftStick:
            onLeftStickChanged?(raw)
        case .rightStick:
            onRightStickChanged?(raw)
        case .dpad:
            onDPadChanged?(raw)
        }

        // Low-pass filter to reduce jitter
        let alpha = mouseSmoothingAlpha
        filteredStick.dx = filteredStick.dx * alpha + raw.dx * (1.0 - alpha)
        filteredStick.dy = filteredStick.dy * alpha + raw.dy * (1.0 - alpha)

        // let filteredMagnitude = sqrt(filteredStick.dx * filteredStick.dx + filteredStick.dy * filteredStick.dy)

        switch keyboardMovementStyle {
        case .mouse:
            // Start or stop analog timer depending on magnitude vs deadZone
            if rawMagnitude > joystickDeadzone {
                startAnalogTimerIfNeeded(from: source)
                lastAnalogUpdate = Date()
            } else {
                stopAnalogTimerIfNeeded()
            }

            // When in analog mode we do not synthesize discrete presses; analogTimer will generate deltas
            // But we still may want to clear any discrete held direction state:
            if let last = lastAnalogDirection {
                // release the previous discrete direction if any
                setDirectionalInput(last, pressed: false)
                lastAnalogDirection = nil
                stopMoveRepeat(clearDirection: true)
            }

        case .limited, .full:
            // Map to discrete direction based on filteredStick and magnitude vs deadZone
            if rawMagnitude <= joystickDeadzone {
                // release any held discrete direction
                if let last = lastAnalogDirection {
                    setDirectionalInput(last, pressed: false)
                    lastAnalogDirection = nil
                }
                stopMoveRepeat(clearDirection: true)
                filteredStick = CGVector(dx: 0, dy: 0)
                return
            }

            let newDir = discreteDirection(for: filteredStick, mode: keyboardMovementStyle)
            if newDir != lastAnalogDirection {
                // release previous, press new
                if let last = lastAnalogDirection {
                    setDirectionalInput(last, pressed: false)
                }

                lastAnalogDirection = newDir
                updateRepeatTuning(for: source)
                setDirectionalInput(newDir, pressed: true)
            }
        }
    }
    
    private func discreteDirection(for vector: CGVector, mode: KeyboardMovementMode) -> OverlayMoveDirection {
        let angle = atan2(vector.dy, vector.dx) // -π..π
        // Convert to degrees 0..360 where 0 = right, 90 = up
        var degrees = angle * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }
        
        // Cardinal and diagonal angular ranges
        switch mode {
        case .limited:
            // Map to nearest cardinal: up (45..135), left (135..225), down (225..315), right (315..45)
            if degrees >= 45 && degrees < 135 { return .up }
            if degrees >= 135 && degrees < 225 { return .left }
            if degrees >= 225 && degrees < 315 { return .down }
            return .right
            
        case .full:
            switch degrees {
            case 337.5..<360, 0..<22.5: return .right
            case 22.5..<67.5: return .upRight
            case 67.5..<112.5: return .up
            case 112.5..<157.5: return .upLeft
            case 157.5..<202.5: return .left
            case 202.5..<247.5: return .downLeft
            case 247.5..<292.5: return .down
            case 292.5..<337.5: return .downRight
            default: return .right
            }
            
        case .mouse:
            return .right // unreachable for mouse
        }
    }

    private func startAnalogTimerIfNeeded(from source: MovementMode) {
        guard analogTimer == nil else { return }
        
        analogTimer = Timer.scheduledTimer(withTimeInterval: joystickTickInterval, repeats: true, block: { [weak self] _ in
            self?.analogTimerFired(from: source)
        })
        // Ensure timer runs on main runloop in common modes
        RunLoop.main.add(analogTimer!, forMode: .common)
    }
    
    private func stopAnalogTimerIfNeeded() {
        analogTimer?.invalidate()
        analogTimer = nil
    }
    
    private func analogTimerFired(from source: MovementMode) {
        // Get active deadzone
        let joystickDeadzone = switch source {
        case .dpad: CGFloat(0)
        case .leftStick: leftStickDeadzone
        case .rightStick: rightStickDeadzone
        }
        
        // Compute delta using filteredStick and sensitivity
        let tNow = Date()
        let elapsed = tNow.timeIntervalSince(lastAnalogUpdate)
        lastAnalogUpdate = tNow
        
        let mag = sqrt(filteredStick.dx * filteredStick.dx + filteredStick.dy * filteredStick.dy)
        guard mag > joystickDeadzone else { return }
        
        // Normalize and scale magnitude into [0..1] beyond dead zone
        let normalizedMag = (mag - joystickDeadzone) / (1.0 - joystickDeadzone)
        let nx = filteredStick.dx / mag
        let ny = filteredStick.dy / mag
        
        // velocity = sensitivity * normalizedMag (units/sec)
        let velocityX = nx * mouseSensitivity * CGFloat(normalizedMag)
        let velocityY = ny * mouseSensitivity * CGFloat(normalizedMag) * -1
        
        // delta = velocity * elapsed
        let delta = CGVector(dx: velocityX * CGFloat(elapsed), dy: velocityY * CGFloat(elapsed))
        
        // send delta as mouse move on main thread
        DispatchQueue.main.async {
            self.sendMouseMove(delta)
        }
    }
    
    private func updateRepeatTuning(for type: MovementMode) {
        switch type {
        case .dpad:
            holdRepeatInitialDelay = padHoldRepeatInitialDelay
            holdRepeatInitialInterval = padHoldRepeatInitialInterval
            holdRepeatMinimumInterval = padHoldRepeatMinimumInterval
            holdRepeatAcceleration = padHoldRepeatAcceleration
            
        case .leftStick, .rightStick:
            holdRepeatInitialDelay = stickHoldRepeatInitialDelay
            holdRepeatInitialInterval = stickHoldRepeatInitialInterval
            holdRepeatMinimumInterval = stickHoldRepeatMinimumInterval
            holdRepeatAcceleration = stickHoldRepeatAcceleration
        }
    }
    
    // MARK: - Controller Glyph Handling
    private func refreshConnectedControllerGlyphStyle() {
        let controllers = GCController.controllers()
        guard let preferredController = preferredConnectedController(from: controllers) else {
            onGlyphStyleChanged?(.generic)
            onDetectedControllerChanged?(nil)
            return
        }

        let style = glyphStyle(for: preferredController)
        onGlyphStyleChanged?(style)
        onDetectedControllerChanged?(
            DetectedController(
                name: detectedControllerName(for: preferredController),
                guideButtons: supportedGuideButtons(for: preferredController)
            )
        )
    }

    private func preferredConnectedController(from controllers: [GCController]) -> GCController? {
        controllers.first(where: { glyphStyle(for: $0) != .generic }) ?? controllers.first
    }

    private func glyphStyle(for controller: GCController) -> ControllerGlyphStyle {
        ControllerGlyphStyle.detect(
            vendorName: controller.vendorName,
            productCategory: productCategory(for: controller)
        )
    }

    private func detectedControllerName(for controller: GCController) -> String {
        if let vendorName = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines), !vendorName.isEmpty {
            return vendorName
        }

        if let productCategory = productCategory(for: controller)?.trimmingCharacters(in: .whitespacesAndNewlines), !productCategory.isEmpty {
            return productCategory
        }

        return "Unknown Controller"
    }

    private func supportedGuideButtons(for controller: GCController) -> [ControllerGuideButton] {
        guard controller.extendedGamepad != nil else {
            return []
        }

        var buttons: [ControllerGuideButton] = []
        buttons.append(.menu)
        buttons.append(.options)
        return buttons
    }

    private func productCategory(for controller: GCController) -> String? {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
            return controller.productCategory
        }
        return nil
    }

    private func publishCaptureState() {
        onCaptureStateChanged?(
            ControllerCaptureState(
                isGuidePressed: isGuideHeld,
                pressedButtons: pressedAssignableButtons
            )
        )
    }

    private var isGuideActive: Bool {
        isGuideHeld || Date().timeIntervalSince(lastGuidePressDate) < guideChordWindow
    }

    private func setDirectionalInput(_ direction: OverlayMoveDirection, pressed: Bool) {
        if pressed {
            let currentCount = directionPressCounts[direction, default: 0] + 1
            directionPressCounts[direction] = currentCount

            guard currentCount == 1 else { return }

            heldDirectionOrder.removeAll { $0 == direction }
            heldDirectionOrder.append(direction)

            guard activeMoveDirection != direction else { return }
            beginHeldMovement(in: direction)
            return
        }

        guard let currentCount = directionPressCounts[direction], currentCount > 0 else { return }

        if currentCount == 1 {
            directionPressCounts[direction] = nil
            heldDirectionOrder.removeAll { $0 == direction }

            guard activeMoveDirection == direction else { return }
            stopMoveRepeat(clearDirection: true)
            if let fallback = heldDirectionOrder.last {
                beginHeldMovement(in: fallback)
            }
        } else {
            directionPressCounts[direction] = currentCount - 1
        }
    }

    // MARK: - Input Handling
    // MARK: Movement Handling
    private func beginHeldMovement(in direction: OverlayMoveDirection) {
        stopMoveRepeat(clearDirection: false)
        activeMoveDirection = direction
        holdRepeatStep = 0

        sendMove(direction, trigger: .press)
        scheduleMoveRepeat(after: holdRepeatInitialDelay ?? padHoldRepeatInitialDelay)
    }

    private func scheduleMoveRepeat(after delay: TimeInterval) {
        print(delay)
        guard activeMoveDirection != nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performMoveRepeat()
        }
        holdRepeatWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performMoveRepeat() {
        guard let direction = activeMoveDirection else { return }
        guard directionPressCounts[direction, default: 0] > 0 else {
            stopMoveRepeat(clearDirection: true)
            return
        }

        sendMove(direction, trigger: .holdRepeat)
        holdRepeatStep += 1
        let acceleratedInterval = max(
            holdRepeatMinimumInterval ?? padHoldRepeatMinimumInterval,
            (holdRepeatInitialInterval ?? padHoldRepeatInitialInterval) * pow(holdRepeatAcceleration ?? padHoldRepeatAcceleration, Double(holdRepeatStep))
        )
        scheduleMoveRepeat(after: acceleratedInterval)
    }

    private func stopMoveRepeat(clearDirection: Bool) {
        holdRepeatWorkItem?.cancel()
        holdRepeatWorkItem = nil
        holdRepeatStep = 0

        if clearDirection {
            activeMoveDirection = nil
        }
    }

    private func sendMove(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger) {
        debugLog("Move: \(direction) trigger=\(trigger)")
        onMove?(direction, trigger)
    }
    
    private func sendMouseMove(_ delta: CGVector) {
        debugLog("Mouse Move: \(delta)")
        onMouseMove?(delta)
    }

    // MARK: Button Input Handling
    private func handleAssignableButtonPress(_ button: ControllerAssignableButton) {
        debugLog("Button pressed: \(button)")

        if let pendingAssignableButtonCapture {
            self.pendingAssignableButtonCapture = nil
            pendingAssignableButtonCapture(button)
            debugLog("Captured assignable button: \(button)")
            return
        }

        if isGuideActive {
            if suppressGuideChordUntilRelease {
                debugLog("Ignoring guide chord while dismiss suppression is active")
                return
            }

            let recorded = ControllerToggleBinding(button: button)
            if let pendingToggleCapture {
                self.pendingToggleCapture = nil
                pendingToggleCapture(recorded)
                debugLog("Captured toggle binding: \(recorded.button)")
                return
            }

            if isToggleEnabled && toggleBinding.button == button {
                debugLog("Toggled overlay via controller binding")
                onToggle?()
            }

            return
        }

        if actionBindings.acceptType == button {
            debugLog("Accept/Type triggered")
            onSelect?()
            return
        }

        if actionBindings.backspace == button {
            debugLog("Backspace triggered")
            onBackspace?()
            return
        }

        if actionBindings.space == button {
            debugLog("Space triggered")
            onSpace?()
            return
        }

        if actionBindings.enter == button {
            debugLog("Enter triggered")
            onEnter?()
            return
        }

        if actionBindings.shift == button {
            debugLog("Shift shortcut triggered")
            onShift?()
            return
        }

        if actionBindings.capsLock == button {
            debugLog("Caps Lock shortcut triggered")
            onCapsLock?()
        }
        
        if actionBindings.mouseLeftClick == button {
            debugLog("Left Click shortcut triggered")
            onLeftClickDown?()
        }
        
        if actionBindings.mouseRightClick == button {
            debugLog("Right Click shortcut triggered")
            onRightClickDown?()
        }
        
        if actionBindings.enlargeWindow == button {
            debugLog("Enlarge Overlay shortcut triggered")
            onEnlarge?()
        }
        
        if actionBindings.shrinkWindow == button {
            debugLog("Shrink Overlay shortcut triggered")
            onShrink?()
        }
    }
    
    func handleAssignableButtonLift(_ button: ControllerAssignableButton) {
        debugLog("Button lifted: \(button)")
        
        if actionBindings.mouseLeftClick == button {
            debugLog("Left Click release triggered")
            onLeftClickUp?()
        }
        
        if actionBindings.mouseRightClick == button {
            debugLog("Right Click release triggered")
            onRightClickUp?()
        }
    }
}
