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

// Per-source analog input state
private struct AnalogInputState {
    var filteredStick = CGVector(dx: 0, dy: 0)
    var lastDirection: OverlayMoveDirection? = nil
    var lastInputType: AxisInputType? = nil
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
    var onScroll: ((CGVector) -> Void)?
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
    
    var enableMouseInKeyboard = true {
        didSet {
            guard enableMouseInKeyboard != oldValue else { return }
            resetAnalogStateForContextChange()
        }
    }
    var isKeyboardOverlayVisible = false {
        didSet {
            guard isKeyboardOverlayVisible != oldValue else { return }
            resetAnalogStateForContextChange()
        }
    }
    var isMouseOverlayVisible = false {
        didSet {
            guard isMouseOverlayVisible != oldValue else { return }
            resetAnalogStateForContextChange()
        }
    }
    
    var leftStickInputType: [AxisInputType] = [.overlayMovement] {
        didSet {
            rebindSticksIfNeeded()
            resetAnalogStateForContextChange()
        }
    }
    
    var rightStickInputType: [AxisInputType] = [.mouseMovement] {
        didSet {
            rebindSticksIfNeeded()
            resetAnalogStateForContextChange()
        }
    }
    
    var padInputType: [AxisInputType] = [.overlayMovement] {
        didSet {
            rebindSticksIfNeeded()
            resetAnalogStateForContextChange()
        }
    }
    
    var dismissWithGuideButton = true
    var isOverlayVisible = false
    var keyboardMovementStyle: KeyboardMovementMode = .limited
    var leftStickDeadzone: CGFloat = 0.20
    var rightStickDeadzone: CGFloat = 0.20
    var mouseSensitivity: CGFloat = 400.0
    var mouseSmoothingAlpha: CGFloat = 0.65
    var invertMouseX: Bool = false
    var invertMouseY: Bool = false
    var scrollSpeed: CGFloat = 600.0
    var invertScrollX: Bool = false
    var invertScrollY: Bool = false
    
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
    
    // Arrow key emulation
    private let keyEmitter = KeyEmitter()
    private var arrowDirectionPressCounts: [OverlayMoveDirection: Int] = [:]
    private var heldArrowDirectionOrder: [OverlayMoveDirection] = []
    private var activeArrowMoveDirection: OverlayMoveDirection?
    private var arrowHoldRepeatStep = 0
    private var arrowHoldRepeatWorkItem: DispatchWorkItem?
    
    // Internal state for analog handling (per-source)
    private var analogStates: [MovementMode: AnalogInputState] = [
        .leftStick: AnalogInputState(),
        .rightStick: AnalogInputState(),
        .dpad: AnalogInputState()
    ]
    private var analogTimers: [MovementMode: Timer?] = [
        .leftStick: nil,
        .rightStick: nil,
        .dpad: nil
    ]
    private var lastAnalogUpdates: [MovementMode: Date] = [
        .leftStick: Date.distantPast,
        .rightStick: Date.distantPast,
        .dpad: Date.distantPast
    ]
    
    // Variables for handling input debounce
    private var lastDirectionChangeDate: Date = .distantPast
    private let directionDebounceInterval: TimeInterval = 0.1
    
    // Variables for dpad hold repeat behavior
    private let padHoldRepeatInitialDelay: TimeInterval = 0.28
    private let padHoldRepeatInitialInterval: TimeInterval = 0.22
    private let padHoldRepeatMinimumInterval: TimeInterval = 0.055
    private let padHoldRepeatAcceleration: Double = 0.84
    
    // Variables for discrete stick hold repeat behavior
    private var stickHoldRepeatInitialDelay: TimeInterval = 0.28
    private var stickHoldRepeatInitialInterval: TimeInterval = 0.30
    private var stickHoldRepeatMinimumInterval: TimeInterval = 0.08
    private var stickHoldRepeatAcceleration: Double = 0.9
    
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
        stopMoveRepeat(clearDirection: true, for: .overlayMovement)
        stopMoveRepeat(clearDirection: true, for: .arrowKeys)
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
        stopMoveRepeat(clearDirection: true, for: .overlayMovement)
        stopMoveRepeat(clearDirection: true, for: .arrowKeys)
        
        // Reset all per-source analog states and timers
        for mode in [MovementMode.leftStick, .rightStick, .dpad] {
            resetAnalogStateForSource(mode)
        }
        
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
    private func bindAnalogStick(_ stick: GCControllerDirectionPad, from source: MovementMode, inputType: [AxisInputType]) {
        stick.valueChangedHandler = nil // Clear any existing handler to avoid conflicts when re-binding
        
        let normalizedInputTypes = normalizedAxisInputTypes(from: inputType)
        if normalizedInputTypes.isEmpty {
            return
        }
        
        stick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }
            self.handleAnalogStick(x: xValue, y: yValue, from: source, inputTypes: normalizedInputTypes)
        }
    }
    
    private func handleAnalogStick(x: Float, y: Float, from source: MovementMode, inputTypes: [AxisInputType]) {
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
        
        // Get per-source state
        guard var state = analogStates[source] else { return }
        
        guard let activeInputType = resolvedAxisInputType(from: inputTypes) else {
            resetAnalogStateForContextChange()
            return
        }
        
        if activeInputType != state.lastInputType {
            clearAnalogState(for: source)
            state.lastInputType = activeInputType
        }
        
        let isMouseMovementType = activeInputType == .mouseMovement || activeInputType == .scrollWheel
        let keyboardMovementStyle: KeyboardMovementMode = isMouseMovementType ? .mouse : self.keyboardMovementStyle
        if keyboardMovementStyle != .mouse {
            stopAnalogTimerIfNeeded(for: source)
        }
        
        switch keyboardMovementStyle {
        case .mouse:
            // Low-pass filter to reduce jitter
            let alpha = activeInputType == .scrollWheel ? 0.0 : mouseSmoothingAlpha
            state.filteredStick.dx = state.filteredStick.dx * alpha + raw.dx * (1.0 - alpha)
            state.filteredStick.dy = state.filteredStick.dy * alpha + raw.dy * (1.0 - alpha)
            
            // Start or stop analog timer depending on magnitude vs deadZone
            if rawMagnitude > joystickDeadzone {
                startAnalogTimerIfNeeded(from: source)
                lastAnalogUpdates[source] = Date()
            } else {
                stopAnalogTimerIfNeeded(for: source)
            }
            
            // When in analog mode we do not synthesize discrete presses; timer will generate deltas
            // But we still may want to clear any discrete held direction state:
            if let last = state.lastDirection {
                // release the previous discrete direction if any
                setDirectionalInput(last, pressed: false, for: activeInputType)
                state.lastDirection = nil
                stopMoveRepeat(clearDirection: true, for: activeInputType)
            }
            
        case .limited, .full:
            // Map to discrete direction based on filteredStick and magnitude vs deadZone
            if rawMagnitude <= joystickDeadzone {
                // release any held discrete direction
                if let last = state.lastDirection {
                    setDirectionalInput(last, pressed: false, for: activeInputType)
                    state.lastDirection = nil
                }
                stopMoveRepeat(clearDirection: true, for: activeInputType)
                state.filteredStick = CGVector(dx: 0, dy: 0)
                analogStates[source] = state
                return
            }
            
            // Update filtered stick with raw input for discrete direction calculation
            state.filteredStick = raw
            let newDir = discreteDirection(for: state.filteredStick, mode: keyboardMovementStyle)
            let now = Date()
            if newDir != state.lastDirection {
                if now.timeIntervalSince(lastDirectionChangeDate) >= directionDebounceInterval {
                    // Release previous, press new
                    if let last = state.lastDirection {
                        setDirectionalInput(last, pressed: false, for: activeInputType)
                    }
                    state.lastDirection = newDir
                    lastDirectionChangeDate = now
                    updateRepeatTuning(for: source)
                    setDirectionalInput(newDir, pressed: true, for: activeInputType)
                }
            }
        }
        
        analogStates[source] = state
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
        guard analogTimers[source] == nil else { return }
        
        let timer = Timer.scheduledTimer(withTimeInterval: joystickTickInterval, repeats: true, block: { [weak self] _ in
            self?.analogTimerFired(from: source)
        })
        // Ensure timer runs on main runloop in common modes
        RunLoop.main.add(timer, forMode: .common)
        analogTimers[source] = timer
    }
    
    private func stopAnalogTimerIfNeeded(for source: MovementMode) {
        if let timer = analogTimers[source] {
            timer?.invalidate()
            analogTimers[source] = nil
        }
    }
    
    private func analogTimerFired(from source: MovementMode) {
        let inputType = resolvedAxisInputType(from: inputTypes(for: source))
        guard (inputType == .mouseMovement) || (inputType == .scrollWheel) else {
            stopAnalogTimerIfNeeded(for: source)
            return
        }
        
        // Get analog input type
        let isMouseMovement = inputType == .mouseMovement
        
        // Get active deadzone
        let joystickDeadzone = switch source {
        case .dpad: CGFloat(0)
        case .leftStick: leftStickDeadzone
        case .rightStick: rightStickDeadzone
        }
        
        // Compute delta using per-source filteredStick and sensitivity
        let tNow = Date()
        let elapsed = tNow.timeIntervalSince(lastAnalogUpdates[source] ?? Date.distantPast)
        lastAnalogUpdates[source] = tNow
        
        guard let state = analogStates[source] else { return }
        let mag = sqrt(state.filteredStick.dx * state.filteredStick.dx + state.filteredStick.dy * state.filteredStick.dy)
        guard mag > joystickDeadzone else { return }
        
        // Normalize and scale magnitude into [0..1] beyond dead zone
        let normalizedMag = (mag - joystickDeadzone) / (1.0 - joystickDeadzone)
        let nx = state.filteredStick.dx / mag
        let ny = state.filteredStick.dy / mag
        
        // velocity = sensitivity * normalizedMag (units/sec)
        let sensitivity = isMouseMovement ? mouseSensitivity : scrollSpeed
        let velocityX = nx * sensitivity * CGFloat(normalizedMag)
        let velocityY = ny * sensitivity * CGFloat(normalizedMag)
        
        // final variables
        var finalVelocityX: CGFloat
        var finalVelocityY: CGFloat
        var xMult: CGFloat
        var yMult: CGFloat
        
        if isMouseMovement {
            finalVelocityX = velocityX * CGFloat(elapsed)
            finalVelocityY = velocityY * CGFloat(elapsed)
            xMult = invertMouseX ? -1 : 1
            yMult = invertMouseY ? 1 : -1 // Invert mouse Y by default
        } else {
            finalVelocityX = velocityX * CGFloat(elapsed)
            finalVelocityY = velocityY * CGFloat(elapsed)
            xMult = invertScrollX ? 1 : -1  // Invert scroll X by default
            yMult = invertScrollY ? -1 : 1
        }
        
        let delta = CGVector(dx: finalVelocityX * xMult, dy: finalVelocityY * yMult)
        
        // send delta as mouse move on main thread
        DispatchQueue.main.async {
            if isMouseMovement {
                self.sendMouseMove(delta)
            } else {
                self.sendScroll(delta)
            }
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
    
    private func setDirectionalInput(_ direction: OverlayMoveDirection, pressed: Bool, for mode: AxisInputType) {
        if pressed {
            if mode == .overlayMovement {
                let currentCount = directionPressCounts[direction, default: 0] + 1
                directionPressCounts[direction] = currentCount
                
                guard currentCount == 1 else { return }
                
                heldDirectionOrder.removeAll { $0 == direction }
                heldDirectionOrder.append(direction)
                
                guard activeMoveDirection != direction else { return }
            } else if mode == .arrowKeys {
                let currentCount = arrowDirectionPressCounts[direction, default: 0] + 1
                arrowDirectionPressCounts[direction] = currentCount
                
                guard currentCount == 1 else { return }
                
                heldArrowDirectionOrder.removeAll { $0 == direction }
                heldArrowDirectionOrder.append(direction)
                
                guard activeArrowMoveDirection != direction else { return }
            }
            
            beginHeldMovement(in: direction, for: mode)
            return
        }
        
        if mode == .overlayMovement {
            guard let currentCount = directionPressCounts[direction], currentCount > 0 else { return }
            
            if currentCount == 1 {
                directionPressCounts[direction] = nil
                heldDirectionOrder.removeAll { $0 == direction }
                
                guard activeMoveDirection == direction else { return }
                stopMoveRepeat(clearDirection: true, for: mode)
                if let fallback = heldDirectionOrder.last {
                    beginHeldMovement(in: fallback)
                }
            } else {
                directionPressCounts[direction] = currentCount - 1
            }
        } else if mode == .arrowKeys {
            guard let currentCount = arrowDirectionPressCounts[direction], currentCount > 0 else { return }
            
            if currentCount == 1 {
                arrowDirectionPressCounts[direction] = nil
                heldArrowDirectionOrder.removeAll { $0 == direction }
                
                guard activeArrowMoveDirection == direction else { return }
                stopMoveRepeat(clearDirection: true, for: mode)
                if let fallback = heldDirectionOrder.last {
                    beginHeldMovement(in: fallback, for: mode)
                }
            } else {
                arrowDirectionPressCounts[direction] = currentCount - 1
            }
        }
    }
    
    private func normalizedAxisInputTypes(from inputTypes: [AxisInputType]) -> [AxisInputType] {
        var seen = Set<AxisInputType>()
        return inputTypes
            .filter { $0 != .none }
            .filter { seen.insert($0).inserted }
    }
    
    private func resolvedAxisInputType(from inputTypes: [AxisInputType]) -> AxisInputType? {
        let normalized = normalizedAxisInputTypes(from: inputTypes)
        guard !normalized.isEmpty else { return nil }
        
        let mouseType = preferredMouseAxisInputType(from: normalized)
        let keyboardType = preferredKeyboardAxisInputType(from: normalized)
        
        if isMouseOverlayVisible {
            return mouseType != nil ? mouseType : keyboardType
        }
        
        if isKeyboardOverlayVisible {
            if enableMouseInKeyboard, mouseType != nil {
                return mouseType
            }
            return keyboardType
        }
        
        return keyboardType
    }
    
    private func preferredMouseAxisInputType(from inputTypes: [AxisInputType]) -> AxisInputType? {
        if inputTypes.contains(.mouseMovement) {
            return .mouseMovement
        }
        if inputTypes.contains(.scrollWheel) {
            return .scrollWheel
        }
        return nil
    }
    
    private func preferredKeyboardAxisInputType(from inputTypes: [AxisInputType]) -> AxisInputType? {
        if inputTypes.contains(.overlayMovement) {
            return .overlayMovement
        }
        if inputTypes.contains(.arrowKeys) {
            return .arrowKeys
        }
        return nil
    }
    
    private func inputTypes(for source: MovementMode) -> [AxisInputType] {
        switch source {
        case .leftStick:
            return leftStickInputType
        case .rightStick:
            return rightStickInputType
        case .dpad:
            return padInputType
        }
    }
    
    
    private func clearAnalogState(for source: MovementMode) {
        stopAnalogTimerIfNeeded(for: source)
        if var state = analogStates[source] {
            state.filteredStick = CGVector(dx: 0, dy: 0)
            state.lastDirection = nil
            state.lastInputType = nil
            analogStates[source] = state
        }
    }
    
    private func resetAnalogStateForSource(_ source: MovementMode) {
        clearAnalogState(for: source)
        stopAnalogTimerIfNeeded(for: source)
    }
    
    private func resetAnalogStateForContextChange() {
        for mode in [MovementMode.leftStick, .rightStick, .dpad] {
            resetAnalogStateForSource(mode)
        }
    }
    
    // MARK: - Input Handling
    // MARK: Movement Handling
    private func beginHeldMovement(in direction: OverlayMoveDirection, for mode: AxisInputType = .overlayMovement) {
        stopMoveRepeat(clearDirection: false, for: mode)
        
        if mode == .overlayMovement {
            activeMoveDirection = direction
            holdRepeatStep = 0
            sendMove(direction, trigger: .press)
        } else if mode == .arrowKeys {
            activeArrowMoveDirection = direction
            arrowHoldRepeatStep = 0
            sendArrowMove(direction)
        }
        
        scheduleMoveRepeat(after: holdRepeatInitialDelay ?? padHoldRepeatInitialDelay, for: mode)
    }
    
    private func scheduleMoveRepeat(after delay: TimeInterval, for mode: AxisInputType = .overlayMovement) {
        if mode == .overlayMovement {
            guard activeMoveDirection != nil else { return }
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.performMoveRepeat(mode)
            }
            holdRepeatWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else if mode == .arrowKeys {
            guard activeArrowMoveDirection != nil else { return }
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.performMoveRepeat(mode)
            }
            arrowHoldRepeatWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private func performMoveRepeat(_ mode: AxisInputType) {
        var acceleratedInterval: TimeInterval = 0
        
        if mode == .overlayMovement {
            guard let direction = activeMoveDirection else { return }
            
            guard directionPressCounts[direction, default: 0] > 0 else {
                stopMoveRepeat(clearDirection: true, for: mode)
                return
            }
            
            sendMove(direction, trigger: .holdRepeat)
            holdRepeatStep += 1
            
            acceleratedInterval = max(
                holdRepeatMinimumInterval ?? padHoldRepeatMinimumInterval,
                (holdRepeatInitialInterval ?? padHoldRepeatInitialInterval) * pow(holdRepeatAcceleration ?? padHoldRepeatAcceleration, Double(holdRepeatStep))
            )
        } else if mode == .arrowKeys {
            guard let direction = activeArrowMoveDirection else { return }
            
            guard arrowDirectionPressCounts[direction, default: 0] > 0 else {
                stopMoveRepeat(clearDirection: true, for: mode)
                return
            }
            
            sendArrowMove(direction)
            arrowHoldRepeatStep += 1
            
            acceleratedInterval = max(
                holdRepeatMinimumInterval ?? padHoldRepeatMinimumInterval,
                (holdRepeatInitialInterval ?? padHoldRepeatInitialInterval) * pow(holdRepeatAcceleration ?? padHoldRepeatAcceleration, Double(arrowHoldRepeatStep))
            )
        }
        
        scheduleMoveRepeat(after: acceleratedInterval, for: mode)
    }
    
    private func stopMoveRepeat(clearDirection: Bool, for mode: AxisInputType) {
        if mode == .overlayMovement {
            holdRepeatWorkItem?.cancel()
            holdRepeatWorkItem = nil
            holdRepeatStep = 0
            
            if clearDirection {
                activeMoveDirection = nil
            }
        } else if mode == .arrowKeys {
            arrowHoldRepeatWorkItem?.cancel()
            arrowHoldRepeatWorkItem = nil
            arrowHoldRepeatStep = 0
            
            if clearDirection {
                activeArrowMoveDirection = nil
            }
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
    
    private func sendScroll(_ delta: CGVector) {
        debugLog("Scroll: \(delta)")
        onScroll?(delta)
    }
    
    private func sendArrowMove(_ direction: OverlayMoveDirection) {
        debugLog("Arrow Move: \(direction)")
        if !isOverlayVisible || isMouseOverlayVisible {
            return
        }
        
        switch direction {
        case .up: keyEmitter.emit(keyCode: 126)
        case .down: keyEmitter.emit(keyCode: 125)
        case .left: keyEmitter.emit(keyCode: 123)
        case .right: keyEmitter.emit(keyCode: 124)
        case .upLeft:
            keyEmitter.emit(keyCode: 126)
            keyEmitter.emit(keyCode: 123)
        case .upRight:
            keyEmitter.emit(keyCode: 126)
            keyEmitter.emit(keyCode: 124)
        case .downLeft:
            keyEmitter.emit(keyCode: 125)
            keyEmitter.emit(keyCode: 123)
        case .downRight:
            keyEmitter.emit(keyCode: 125)
            keyEmitter.emit(keyCode: 124)
        }
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
        
        if actionBindings.moveCaretLeft == button {
            debugLog("Move Caret Left shortcut triggered")
            sendArrowMove(.left)
        }
        
        if actionBindings.moveCaretRight == button {
            debugLog("Move Caret Right shortcut triggered")
            sendArrowMove(.right)
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
