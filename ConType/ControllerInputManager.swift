//
//  ControllerInputManager.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import Foundation
import GameController
import Combine
import CoreHaptics

/// An enum representing the type of input for an axis (stick or d-pad).
/// Contains:
/// - Limited (4 Directional)
/// - Full (8 Directional)
/// - Mouse (Analog movement with filtering and deadzone)
enum KeyboardMovementMode {
    case limited
    case full
    case mouse
}

/// A struct containing the internal state for an analog input source. Utilized as a unified state containing the input state of each axis input
private struct AxisInputState {
    var filteredStick = CGVector(dx: 0, dy: 0)
    var lastDirection: OverlayMoveDirection? = nil
    var lastInputType: AxisActionType? = nil
}

/// The main model class responsible for managing controller input, processing it according to user settings, and exposing it for SwiftUI views.
@MainActor
final class JoystickInputModel: ObservableObject {
    @Published var leftStick: CGVector = .zero
    @Published var rightStick: CGVector = .zero
    @Published var pad: CGVector = .zero
    
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
        manager.onPadChanged = { [weak self] vector in
            DispatchQueue.main.async {
                self?.pad = vector
            }
        }
    }
}

/// The primary class responsible for interfacing with GCController, handling input events, applying user-configured settings, and exposing high-level input actions through closures. This class manages the lifecycle of controller connections, haptics, and input processing logic.
final class ControllerInputManager: NSObject {
    // MARK: - Closures for input events and state changes
    var onLeftStickChanged: ((CGVector) -> Void)?
    var onRightStickChanged: ((CGVector) -> Void)?
    var onPadChanged: ((CGVector) -> Void)?
    var onToggleKeyboard: (() -> Void)?
    var onToggleMouse: (() -> Void)?
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
    var onArrowMoveLeft: (() -> Void)?
    var onArrowMoveRight: (() -> Void)?
    var onGlyphStyleChanged: ((ControllerGlyphStyle) -> Void)?
    var onCaptureStateChanged: ((ControllerCaptureState) -> Void)?
    var onDetectedControllerChanged: ((DetectedController?) -> Void)?
    var onDismissWithGuideButton: (() -> Void)?
    
    // MARK: - Configuration state
    var isToggleEnabled = true
    var toggleBindings: ControllerToggleBindings = .default
    var actionBindings: ControllerActionBindings = .default
    
    // MARK: - Settings with special handling
    var enableMouseInKeyboard = true {
        didSet {
            guard enableMouseInKeyboard != oldValue else { return }
            resetAnalogStateForContextChange()
        }
    }
    
    var prioritizeMouseOverKeyboard = false {
        didSet {
            guard prioritizeMouseOverKeyboard != oldValue else { return }
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
    
    var leftStickInputType: [AxisActionType] = [.overlayMovement] {
        didSet {
            rebindSticksIfNeeded()
            resetAnalogStateForContextChange()
        }
    }
    
    var rightStickInputType: [AxisActionType] = [.mouseMovement] {
        didSet {
            rebindSticksIfNeeded()
            resetAnalogStateForContextChange()
        }
    }
    
    var padInputType: [AxisActionType] = [.overlayMovement] {
        didSet {
            rebindSticksIfNeeded()
            resetAnalogStateForContextChange()
        }
    }
    
    // MARK: - User preferences
    var dismissWithGuideButton = true
    var isTutorialVisible = false
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
    var enableHaptics = true

    // MARK: - State for haptics management
    private var controllerHapticsEngine: CHHapticEngine?
    private var controllerHapticsControllerID: ObjectIdentifier?
    private var controllerHapticsLocality: GCHapticsLocality?
    
    // MARK: - State for input capture and chord detection
    private var isGuideHeld = false { didSet { publishCaptureState() } }
    private var pressedAssignableButtons: Set<ControllerAssignableButton> = [] { didSet { publishCaptureState() } }
    private var lastGuidePressDate = Date.distantPast
    private let guideChordWindow: TimeInterval = 0.7
    
    // MARK: - Pending capture handlers
    private var pendingToggleCapture: ((ControllerAssignableButton) -> Void)?
    private var pendingAssignableButtonCapture: ((ControllerAssignableButton) -> Void)?
    
    // MARK: - Movement repeat handling
    private var directionPressCounts: [OverlayMoveDirection: Int] = [:]
    private var heldDirectionOrder: [OverlayMoveDirection] = []
    private var activeMoveDirection: OverlayMoveDirection?
    private var holdRepeatStep = 0
    private var holdRepeatWorkItem: DispatchWorkItem?
    
    // MARK: - Arrow key emulation
    private let keyEmitter = KeyEmitter()
    private var arrowDirectionPressCounts: [OverlayMoveDirection: Int] = [:]
    private var heldArrowDirectionOrder: [OverlayMoveDirection] = []
    private var activeArrowMoveDirection: OverlayMoveDirection?
    private var arrowHoldRepeatStep = 0
    private var arrowHoldRepeatWorkItem: DispatchWorkItem?
    
    // MARK: - Internal state for analog handling (per-source)
    private var analogStates: [AxisInput: AxisInputState] = [
        .leftStick: AxisInputState(),
        .rightStick: AxisInputState(),
        .pad: AxisInputState()
    ]
    private var analogTimers: [AxisInput: Timer?] = [
        .leftStick: nil,
        .rightStick: nil,
        .pad: nil
    ]
    private var lastAnalogUpdates: [AxisInput: Date] = [
        .leftStick: Date.distantPast,
        .rightStick: Date.distantPast,
        .pad: Date.distantPast
    ]
    
    // MARK: - Variables for handling input debounce (per-source)
    private var lastDirectionChangeDates: [AxisInput: Date] = [
        .leftStick: Date.distantPast,
        .rightStick: Date.distantPast,
        .pad: Date.distantPast
    ]
    private let directionDebounceInterval: TimeInterval = 0.1
    
    // MARK: - Variables for pad hold repeat behavior
    private let padHoldRepeatInitialDelay: TimeInterval = 0.28
    private let padHoldRepeatInitialInterval: TimeInterval = 0.22
    private let padHoldRepeatMinimumInterval: TimeInterval = 0.055
    private let padHoldRepeatAcceleration: Double = 0.84
    
    // MARK: - Variables for stick hold repeat behavior
    private var stickHoldRepeatInitialDelay: TimeInterval = 0.28
    private var stickHoldRepeatInitialInterval: TimeInterval = 0.30
    private var stickHoldRepeatMinimumInterval: TimeInterval = 0.08
    private var stickHoldRepeatAcceleration: Double = 0.9
    
    // MARK: - Variables for mouse mode
    private var joystickTickInterval: TimeInterval = 1.0 / 60.0
    
    // MARK: - Augmented hold repeat variables
    private var holdRepeatInitialDelay: TimeInterval?
    private var holdRepeatInitialInterval: TimeInterval?
    private var holdRepeatMinimumInterval: TimeInterval?
    private var holdRepeatAcceleration: Double?
    
#if DEBUG
    private func debugLog(_ message: String) { debugPrint("[Controller] \(message)") }
#else
    private func debugLog(_ message: String) {}
#endif
    
    /// Captures the next button press for a toggle binding. The provided closure will be called with the captured button. Only one pending capture is allowed at a time; subsequent calls will overwrite the pending capture.
    /// - Parameter onCaptured: A closure that will be called with the captured `ControllerAssignableButton` when the next button press is detected.
    func captureNextToggleBinding(_ onCaptured: @escaping (ControllerAssignableButton) -> Void) {
        pendingToggleCapture = onCaptured
    }
    
    /// Captures the next button press for an action binding. The provided closure will be called with the captured button. Only one pending capture is allowed at a time; subsequent calls will overwrite the pending capture.
    /// - Parameter onCaptured: A closure that will be called with the captured `ControllerAssignableButton` when the next button press is detected.
    func captureNextAssignableButton(_ onCaptured: @escaping (ControllerAssignableButton) -> Void) {
        pendingAssignableButtonCapture = onCaptured
    }
    
    /// Cancels any pending button capture operations for both toggle and action bindings. This will clear the pending capture closures.
    func cancelPendingCaptures() {
        pendingToggleCapture = nil
        pendingAssignableButtonCapture = nil
    }
    
    /// Initializes the controller input manager, sets up notifications for controller connections, and configures any currently connected controllers.
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
        
        /// Receive input while the app is in the background (menu bar / accessory / non-activating panel)
        GCController.shouldMonitorBackgroundEvents = true
        debugLog("Background events monitoring enabled")
        
        /// Optionally discover wireless controllers proactively
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        debugLog("Started wireless controller discovery")
        
        for controller in GCController.controllers() {
            configure(controller)
        }
        
        refreshConnectedControllerGlyphStyle()
        publishCaptureState()
    }
    
    deinit {
        stopControllerHapticsEngine()
        stopMoveRepeat(clearDirection: true, for: .overlayMovement)
        stopMoveRepeat(clearDirection: true, for: .arrowKeys)
        NotificationCenter.default.removeObserver(self)
    }
    
    //MARK: - Haptics Handling
    /// Plays a rumble pattern on the connected controller if haptics are enabled and a compatible controller with haptic capabilities is available.
    func playRumbleIfSupported() {
        guard enableHaptics else {
            return
        }
        
        guard let engine = resolvedControllerHapticsEngine() else {
            debugLog("No controller haptics engine available; skipping move rumble")
            return
        }

        /// Engines can auto-stop while idle; ensure it is running before playback
        do {
            try engine.start()
        } catch {
            debugLog("Failed to start controller haptics engine: \(error)")
            invalidateControllerHapticsEngine()
            
            /// Attempt one retry with a fresh engine
            guard let recreatedEngine = resolvedControllerHapticsEngine() else {
                debugLog("Unable to recover haptics engine after failure")
                return
            }
            
            do {
                try recreatedEngine.start()
                try playRumble(with: recreatedEngine)
            } catch {
                debugLog("Controller haptics recovery failed: \(error)")
            }
            return
        }

        do {
            try playRumble(with: engine)
        } catch {
            debugLog("Controller move rumble playback failed: \(error)")
        }
    }

    /// Plays a transient haptic pattern suitable for movement/navigation feedback.
    /// - Parameter engine: The `CHHapticEngine` instance to use for playback. Must be started before calling this method.
    private func playRumble(with engine: CHHapticEngine) throws {
        let events = [
            /// A haptic event containing intensity and sharpness, with a duration of 0.1 seconds, starting immediately. This creates a short rumble effect on the controller.
            /// A duration is required for the event to be played on game controllers, even for transient haptics.
            /// 0.1 seconds is the lowest tested possible duration that produces a small rumble. Lower values produce unpredictable results.
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0,
                duration: 0.1
            )
        ]

        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: CHHapticTimeImmediate)
    }

    /// Resolves and returns a `CHHapticEngine` instance for the currently preferred connected controller with haptic capabilities.
    /// Caches the engine for reuse and handles lifecycle management. Returns nil if no compatible controller or engine is available.
    /// - Returns: An optional `CHHapticEngine` instance for the connected controller, or nil if unavailable.
    private func resolvedControllerHapticsEngine() -> CHHapticEngine? {
        let hapticsControllers = GCController.controllers().filter { $0.haptics != nil }
        
        guard let controller = preferredConnectedController(from: hapticsControllers) else {
            invalidateControllerHapticsEngine()
            return nil
        }
        
        guard let haptics = controller.haptics else {
            invalidateControllerHapticsEngine()
            return nil
        }

        /// Check if we can reuse existing engine
        let controllerID = ObjectIdentifier(controller)
        if let existingEngine = controllerHapticsEngine,
           controllerHapticsControllerID == controllerID {
            return existingEngine
        }

        /// Clean up any existing engine before creating a new one
        stopControllerHapticsEngine()

        /// Validate supported localities (GCDeviceHaptics.supportedLocalities must not be empty)
        guard !haptics.supportedLocalities.isEmpty else {
            return nil
        }

        /// Select the optimal locality for haptics
        let selectedLocality = selectOptimalHapticsLocality(from: haptics.supportedLocalities)

        /// Create the haptic engine with the selected locality
        guard let engine = haptics.createEngine(withLocality: selectedLocality) else {
            return nil
        }

        /// Configure engine handlers for lifecycle management
        configureHapticsEngineHandlers(engine)

        /// Cache the engine and associated metadata
        controllerHapticsEngine = engine
        controllerHapticsControllerID = controllerID
        controllerHapticsLocality = selectedLocality
        return engine
    }
    
    // MARK: - Haptics Engine Configuration
    /// Selects the optimal haptics locality, the source of the vibration in the controller, from the supported options.
    /// Prefers `.default` if available, otherwise uses the first supported locality.
    /// - Parameter supportedLocalities: The set of haptics localities supported by the controller.
    /// - Returns: The selected `GCHapticsLocality` to use for the haptic engine.
    private func selectOptimalHapticsLocality(from supportedLocalities: Set<GCHapticsLocality>) -> GCHapticsLocality {
        if supportedLocalities.contains(.default) {
            return .default
        }
        return supportedLocalities.first ?? .default
    }
    
    /// Configures reset and stopped handlers for the haptics engine to manage its lifecycle.
    /// - Parameter engine: The `CHHapticEngine` instance to configure handlers for.
    private func configureHapticsEngineHandlers(_ engine: CHHapticEngine) {
        engine.resetHandler = { [weak self] in
            self?.debugLog("Controller haptics engine received reset signal")
            self?.handleHapticsEngineReset(engine)
        }
        
        engine.stoppedHandler = { [weak self] reason in
            let reasonDescription = Self.describeStoppedReason(reason)
            self?.debugLog("Controller haptics engine stopped: \(reason.rawValue) [\(reasonDescription)]")
        }
    }
    
    /// Handles engine reset by attempting to restart it.
    /// - Parameter engine: The `CHHapticEngine` instance that received the reset signal.
    private func handleHapticsEngineReset(_ engine: CHHapticEngine) {
        do {
            try engine.start()
        } catch {
            debugLog("Failed to restart controller haptics engine after reset: \(error)")
            invalidateControllerHapticsEngine()
        }
    }
    
    /// Stops the haptics engine and clears cached references.
    private func stopControllerHapticsEngine() {
        if controllerHapticsEngine != nil {
            debugLog("Stopping and clearing cached controller haptics engine")
        }
        controllerHapticsEngine?.stop(completionHandler: nil)
        controllerHapticsEngine = nil
        controllerHapticsLocality = nil
    }

    /// Invalidates the current haptics engine. This stops the engine and clears cached references.
    private func invalidateControllerHapticsEngine() {
        stopControllerHapticsEngine()
        controllerHapticsControllerID = nil
    }

    /// Gives a human-readable description of the `CHHapticEngine.StoppedReason`.
    /// - Parameter reason: The `CHHapticEngine.StoppedReason` to describe.
    /// - Returns: A string description of the stopped reason.
    private static func describeStoppedReason(_ reason: CHHapticEngine.StoppedReason) -> String {
        switch reason {
        case .audioSessionInterrupt:
            return "audioSessionInterrupt"
        case .applicationSuspended:
            return "applicationSuspended"
        case .idleTimeout:
            return "idleTimeout"
        case .systemError:
            return "systemError"
        case .notifyWhenFinished:
            return "notifyWhenFinished"
        case .engineDestroyed:
            return "engineDestroyed"
        case .gameControllerDisconnect:
            return "gameControllerDisconnect"
        @unknown default:
            return "unknown"
        }
    }
    
    // MARK: - Controller Connection Handling
    /// Configures a newly connected controller by setting up input handlers and refreshing the UI state.
    /// - Parameter notification: The notification containing the connected controller object.
    @objc private func controllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        debugLog("Controller connected: \(controller.vendorName ?? "Unknown")")
        configure(controller)
        refreshConnectedControllerGlyphStyle()
    }
    
    /// Handles controller disconnection by invalidating haptics if necessary, resetting input state to avoid stale inputs, and refreshing the UI state.
    /// - Parameter notification: The notification containing the disconnected controller object.
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        debugLog("Controller disconnected: \(controller.vendorName ?? "Unknown")")

        if controllerHapticsControllerID == ObjectIdentifier(controller) {
            invalidateControllerHapticsEngine()
        }
        
        /// Avoid stale pressed state from a disconnected device.
        isGuideHeld = false
        pressedAssignableButtons.removeAll()
        stopMoveRepeat(clearDirection: true, for: .overlayMovement)
        stopMoveRepeat(clearDirection: true, for: .arrowKeys)
        
        /// Reset all per-source analog states and timers
        for mode in [AxisInput.leftStick, .rightStick, .pad] {
            resetAnalogStateForSource(mode)
        }
        
        refreshConnectedControllerGlyphStyle()
    }
    
    // MARK: - Controller Handling
    /// Configures a connected controller by setting up input handlers based on its profile (extended or micro gamepad), and configuring fallback handlers for guide button presses on older systems.
    /// - Parameter controller: The `GCController` instance to configure.
    private func configure(_ controller: GCController) {
        debugLog("Configuring controller: \(controller.vendorName ?? "Unknown")")
        
        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad)
            configureThumbstickButtonPresses(from: controller)
            /// Fallback for very old systems where Menu/Home/Options aren't surfaced.
            /// `controllerPausedHandler` is deprecated on macOS 10.15+. Only use when necessary.
            if #available(macOS 11.0, iOS 13.0, tvOS 13.0, *) {
                /// On modern systems we already handle Menu/Home/Options via the input profile; no paused handler needed.
            } else {
                controller.controllerPausedHandler = { [weak self] _ in
                    self?.dismissOverlayViaGuideIfNeeded()
                    self?.debugLog("controllerPausedHandler fired (guide momentary)")
                }
            }
            debugLog("Configured as extended gamepad")
            return
        }
        
        if let microGamepad = controller.microGamepad {
            configureMicroGamepad(microGamepad)
            /// Fallback for very old systems where Menu/Home/Options aren't surfaced.
            /// `controllerPausedHandler` is deprecated on macOS 10.15+. Only use when necessary.
            if #available(macOS 11.0, iOS 13.0, tvOS 13.0, *) {
                /// On modern systems we already handle Menu/Home/Options via the input profile; no paused handler needed.
            } else {
                controller.controllerPausedHandler = { [weak self] _ in
                    self?.dismissOverlayViaGuideIfNeeded()
                    self?.debugLog("controllerPausedHandler fired (guide momentary)")
                }
            }
            debugLog("Configured as micro gamepad")
        }
    }
    
    /// Configures input handlers for an extended gamepad profile, including assignable buttons, guide buttons, and analog sticks.
    private func configureExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        /// Treat Home/Menu/Options as the "guide" modifier; also record moment of press for chorded detection.
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
    
    /// Configures handlers for a micro gamepad profile, which has a more limited set of inputs. Treats the d-pad as an analog stick and binds the available buttons as assignable inputs.
    private func configureMicroGamepad(_ gamepad: GCMicroGamepad) {
        bindAssignableButton(gamepad.buttonA, as: .south)
        bindAssignableButton(gamepad.buttonX, as: .west)
        bindAnalogStick(gamepad.dpad, from: .pad, inputType: padInputType)
    }
    
    /// Configures input handlers for a micro gamepad profile, including assignable buttons and the d-pad as an analog stick.
    func bindSticks(_ gamepad: GCExtendedGamepad) {
        bindAnalogStick(gamepad.leftThumbstick, from: .leftStick, inputType: leftStickInputType)
        bindAnalogStick(gamepad.rightThumbstick, from: .rightStick, inputType: rightStickInputType)
        bindAnalogStick(gamepad.dpad, from: .pad, inputType: padInputType)
    }
    
    /// Rebinds the analog stick handlers for all connected controllers based on the current input type settings.
    private func rebindSticksIfNeeded() {
        for controller in GCController.controllers() {
            if let gamepad = controller.extendedGamepad {
                bindSticks(gamepad)
            } else if let gamepad = controller.microGamepad {
                bindAnalogStick(gamepad.dpad, from: .pad, inputType: padInputType)
            }
        }
    }
    
    /// Configures handlers for thumbstick button presses on controllers that support them, treating them as assignable buttons for input capture and action triggering.
    private func configureThumbstickButtonPresses(from controller: GCController) {
        let buttons = controller.physicalInputProfile.buttons
        buttons[GCInputLeftThumbstickButton]?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handleAssignableButtonChange(.leftStickPress, pressed: pressed)
        }
        
        buttons[GCInputRightThumbstickButton]?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handleAssignableButtonChange(.rightStickPress, pressed: pressed)
        }
    }
    
    /// Binds a button input as a "guide" button, which can be used for special functions like dismissing overlays. Sets up a handler to track its pressed state and trigger associated actions.
    private func bindGuideButton(_ button: GCControllerButtonInput?, source: String) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.setGuidePressed(pressed, source: source)
        }
    }
    
    /// Updates the internal state when a guide button is pressed or released, and triggers overlay dismissal if configured to do so on guide presses.
    private func setGuidePressed(_ pressed: Bool, source: String) {
        isGuideHeld = pressed
        if pressed {
            dismissOverlayViaGuideIfNeeded()
            debugLog("Guide (\(source)) pressed")
        }
    }
    
    /// Dismisses the overlay if the guide button is pressed and the user has enabled dismissal via the guide button.
    private func dismissOverlayViaGuideIfNeeded() {
        guard dismissWithGuideButton else { return }
        debugLog("Dismissed overlay via guide button")
        onDismissWithGuideButton?()
    }
    
    /// Binds a button input as an assignable button for game actions. Sets up a handler to track its pressed state and trigger associated actions based on the button's role in the control scheme.
    private func bindAssignableButton(_ buttonInput: GCControllerButtonInput?, as button: ControllerAssignableButton) {
        buttonInput?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.updateRepeatTuning(for: .pad)
            self?.handleAssignableButtonChange(button, pressed: pressed)
        }
    }
    
    /// Handles changes in the pressed state of assignable buttons, updating internal state and triggering associated actions for button presses and releases.
    private func handleAssignableButtonChange(_ button: ControllerAssignableButton, pressed: Bool) {
        if pressed {
            pressedAssignableButtons.insert(button)
            handleAssignableButtonPress(button)
        } else {
            pressedAssignableButtons.remove(button)
            handleAssignableButtonLift(button)
        }
    }
    
    // MARK: - Analog Stick Handling
    /// Binds a `GCControllerDirectionPad` as an analog stick input source, setting up a value changed handler that processes stick movements according to the specified input types and user settings. Clears any existing handler before binding to avoid conflicts when re-binding.
    /// - Parameters:
    ///   - stick: The `GCControllerDirectionPad` to bind as an analog stick input source.
    ///   - source: The logical source of the input (left stick, right stick, or d-pad) used for state management and action triggering.
    ///   - inputType: The types of actions this stick should trigger (e.g., overlay movement, mouse movement), which determines how the input is processed and mapped to actions.
    private func bindAnalogStick(_ stick: GCControllerDirectionPad, from source: AxisInput, inputType: [AxisActionType]) {
        stick.valueChangedHandler = nil // Clear any existing handler to avoid conflicts when re-binding
        
        let normalizedInputTypes = normalizedAxisActionTypes(from: inputType)
        if normalizedInputTypes.isEmpty {
            return
        }
        
        stick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }
            self.handleAnalogStick(x: xValue, y: yValue, from: source, inputTypes: normalizedInputTypes)
        }
    }
    
    /// Handles input from an analog stick, applying user-configured settings such as deadzone, movement style, and input type prioritization to determine what action to surface.
    /// - Parameters:
    ///   - x: The x-axis value of the stick input, typically normalized to the range [-1, 1].
    ///   - y: The y-axis value of the stick input, typically normalized to the range [-1, 1].
    ///   - source: The logical source of the input (left stick, right stick, or d-pad) used for state management and action triggering.
    ///   - inputTypes: The types of actions this stick triggers (e.g., overlay movement, mouse movement).
    private func handleAnalogStick(x: Float, y: Float, from source: AxisInput, inputTypes: [AxisActionType]) {
        let raw = CGVector(dx: CGFloat(x), dy: CGFloat(y))
        let rawMagnitude = sqrt(raw.dx * raw.dx + raw.dy * raw.dy)
        let joystickDeadzone = switch source {
        case .pad: CGFloat(0)
        case .leftStick: leftStickDeadzone
        case .rightStick: rightStickDeadzone
        }
        
        /// Notify observers of stick changes
        switch source {
        case .leftStick:
            onLeftStickChanged?(raw)
        case .rightStick:
            onRightStickChanged?(raw)
        case .pad:
            onPadChanged?(raw)
        }
        
        /// Get per-source state
        guard var state = analogStates[source] else { return }
        
        guard let activeInputType = resolvedAxisActionType(from: inputTypes) else {
            resetAnalogStateForContextChange()
            return
        }
        
        /// If input type changed since last update, clear any existing state that may not apply to the new type (e.g., held directions from previous input type).
        if activeInputType != state.lastInputType {
            clearAnalogState(for: source)
            state.lastInputType = activeInputType
        }
        
        /// Identifies the input event and appropriate movement style.
        let isMouseMovementType = activeInputType == .mouseMovement || activeInputType == .scrollWheel
        let keyboardMovementStyle: KeyboardMovementMode = isMouseMovementType ? .mouse : self.keyboardMovementStyle
        if keyboardMovementStyle != .mouse {
            stopAnalogTimerIfNeeded(for: source)
        }
        
        switch keyboardMovementStyle {
        case .mouse:
            /// Low-pass filter to reduce jitter.
            let alpha = activeInputType == .scrollWheel ? 0.0 : mouseSmoothingAlpha
            state.filteredStick.dx = state.filteredStick.dx * alpha + raw.dx * (1.0 - alpha)
            state.filteredStick.dy = state.filteredStick.dy * alpha + raw.dy * (1.0 - alpha)
            
            /// Start or stop analog timer depending on magnitude vs deadZone.
            if rawMagnitude > joystickDeadzone {
                startAnalogTimerIfNeeded(from: source)
                lastAnalogUpdates[source] = Date()
            } else {
                stopAnalogTimerIfNeeded(for: source)
            }
            
            /// When in analog mode we do not synthesize discrete presses; timer will generate deltas.
            /// But we still may want to clear any discrete held direction state:
            if let last = state.lastDirection {
                /// Release the previous discrete direction if any.
                setDirectionalInput(last, pressed: false, for: activeInputType)
                state.lastDirection = nil
                stopMoveRepeat(clearDirection: true, for: activeInputType)
            }
            
        case .limited, .full:
            /// Use the instantaneous raw vector for discrete direction mapping.
            /// Previously we accumulated inputs which could cause drift and
            /// spurious vertical/horizontal components. Assigning the raw
            /// vector prevents those artifacts while still honoring deadzone.
            state.filteredStick.dx = raw.dx
            state.filteredStick.dy = raw.dy
            
            /// Map to discrete direction based on filteredStick and magnitude vs deadZone.
            if rawMagnitude <= joystickDeadzone {
                /// Release any held discrete direction.
                if let last = state.lastDirection {
                    setDirectionalInput(last, pressed: false, for: activeInputType)
                    state.lastDirection = nil
                }
                stopMoveRepeat(clearDirection: true, for: activeInputType)
                state.filteredStick = CGVector(dx: 0, dy: 0)
                analogStates[source] = state
                return
            }
            
            let newDir = discreteDirection(for: state.filteredStick, mode: keyboardMovementStyle)
            let now = Date()
            let lastChange = lastDirectionChangeDates[source] ?? Date.distantPast
            if newDir != state.lastDirection {
                if now.timeIntervalSince(lastChange) >= directionDebounceInterval {
                    /// Release previous, press new.
                    if let last = state.lastDirection {
                        setDirectionalInput(last, pressed: false, for: activeInputType)
                    }
                    state.lastDirection = newDir
                    lastDirectionChangeDates[source] = now
                    updateRepeatTuning(for: source)
                    setDirectionalInput(newDir, pressed: true, for: activeInputType)
                }
            }
        }
        
        analogStates[source] = state
    }
    
    /// Maps a continuous stick input vector to a discrete direction based on the specified movement mode, which determines the angular ranges for each direction.
    /// - Parameters:
    ///   - vector: The input vector from the analog stick, typically filtered for smoothing. The x and y components represent the stick position,
    ///   - mode: The movement mode (limited or full) that determines how the input vector is mapped to discrete directions.
    /// - Returns: The `OverlayMoveDirection` corresponding to the input vector based on the movement mode.
    private func discreteDirection(for vector: CGVector, mode: KeyboardMovementMode) -> OverlayMoveDirection {
        /// The angle of movement [-π..π]
        let angle = atan2(vector.dy, vector.dx)
        
        /// Convert to degrees 0..360 where 0 = right, 90 = up.
        var degrees = angle * 180.0 / .pi
        
        /// Turns -180..180  to 0..360 for easier range checks
        if degrees < 0 { degrees += 360.0 }
        
        /// Cardinal and diagonal angular ranges.
        switch mode {
        case .limited:
            /// Map to nearest cardinal.
            if degrees >= 45 && degrees < 135 { return .up }
            if degrees >= 135 && degrees < 225 { return .left }
            if degrees >= 225 && degrees < 315 { return .down }
            return .right
            
        case .full:
            /// Fully map to 8 directions.
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
            /// Return a placeholder direction since we won't use it for discrete presses in mouse mode.
            return .right
        }
    }
    
    /// Initializes an analog timer for a given input source if one is not already running. Used to generate repeated input events based on the stick position and user settings.
    /// - Parameter source: The source of the input (left stick, right stick, or d-pad) for which to start the timer.
    private func startAnalogTimerIfNeeded(from source: AxisInput) {
        guard analogTimers[source] == nil else { return }
        
        let timer = Timer.scheduledTimer(withTimeInterval: joystickTickInterval, repeats: true, block: { [weak self] _ in
            self?.analogTimerFired(from: source)
        })
        /// Ensure timer runs on main runloop in common modes
        RunLoop.main.add(timer, forMode: .common)
        analogTimers[source] = timer
    }
    
    /// Stops and invalidates the analog timer for a given input source if one is running.
    private func stopAnalogTimerIfNeeded(for source: AxisInput) {
        if let timer = analogTimers[source] {
            timer?.invalidate()
            analogTimers[source] = nil
        }
    }
    
    /// Called when the analog timer fires for a given input source. Computes the appropriate input deltas based on the current stick position, user settings (e.g., sensitivity, inversion), and elapsed time since the last update, then triggers the corresponding mouse movement or scroll actions on the main thread.
    private func analogTimerFired(from source: AxisInput) {
        let inputType = resolvedAxisActionType(from: inputTypes(for: source))
        guard (inputType == .mouseMovement) || (inputType == .scrollWheel) else {
            stopAnalogTimerIfNeeded(for: source)
            return
        }
        
        /// Get analog input type
        let isMouseMovement = inputType == .mouseMovement
        
        /// Get active deadzone
        let joystickDeadzone = switch source {
        case .pad: CGFloat(0)
        case .leftStick: leftStickDeadzone
        case .rightStick: rightStickDeadzone
        }
        
        /// Compute delta using per-source filteredStick and sensitivity
        let tNow = Date()
        let elapsed = tNow.timeIntervalSince(lastAnalogUpdates[source] ?? Date.distantPast)
        lastAnalogUpdates[source] = tNow
        
        guard let state = analogStates[source] else { return }
        let mag = sqrt(state.filteredStick.dx * state.filteredStick.dx + state.filteredStick.dy * state.filteredStick.dy)
        guard mag > joystickDeadzone else { return }
        
        /// Normalize and scale magnitude into [0..1] beyond dead zone
        let normalizedMag = (mag - joystickDeadzone) / (1.0 - joystickDeadzone)
        let nx = state.filteredStick.dx / mag
        let ny = state.filteredStick.dy / mag
        
        /// velocity = sensitivity * normalizedMag (units/sec)
        let sensitivity = isMouseMovement ? mouseSensitivity : scrollSpeed
        let velocityX = nx * sensitivity * CGFloat(normalizedMag)
        let velocityY = ny * sensitivity * CGFloat(normalizedMag)
        
        /// final variables
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
        
        /// send delta as mouse move on main thread
        DispatchQueue.main.async {
            if isMouseMovement {
                self.sendMouseMove(delta)
            } else {
                self.sendScroll(delta)
            }
        }
    }
    
    /// Updates the repeat tuning parameters based on the input source type, which determines the initial delay, repeat interval, and acceleration for held inputs that trigger repeated actions.
    private func updateRepeatTuning(for type: AxisInput) {
        switch type {
        case .pad:
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
    /// Refreshes the detected controller glyph style and name based on the currently connected controllers.
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
    
    /// Picks a preferred controller from a list of connected controllers, prioritizing those with a recognizable glyph style for better UI representation.
    /// Falls back to the first controller if none have a recognizable style.
    private func preferredConnectedController(from controllers: [GCController]) -> GCController? {
        controllers.first(where: { glyphStyle(for: $0) != .generic }) ?? controllers.first
    }
    
    /// Determines the appropriate glyph style for a given controller based on its vendor name and product category, using a detection method that maps known controllers to specific glyph styles for accurate UI representation.
    /// - Parameter controller: The `GCController` instance for which to determine the glyph style.
    /// - Returns: The `ControllerGlyphStyle` corresponding to the controller, or `.generic` if no specific style is detected.
    private func glyphStyle(for controller: GCController) -> ControllerGlyphStyle {
        ControllerGlyphStyle.detect(
            vendorName: controller.vendorName,
            productCategory: productCategory(for: controller)
        )
    }
    
    /// Determines a human-readable name for a detected controller based on its vendor name and product category, using a detection method that provides the most specific available information for display in the UI.
    /// - Parameter controller: The `GCController` instance for which to determine the name.
    /// - Returns: A string representing the detected controller's name, or "Unknown Controller" if no specific information is available.
    private func detectedControllerName(for controller: GCController) -> String {
        if let vendorName = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines), !vendorName.isEmpty {
            return vendorName
        }
        
        if let productCategory = productCategory(for: controller)?.trimmingCharacters(in: .whitespacesAndNewlines), !productCategory.isEmpty {
            return productCategory
        }
        
        return "Unknown Controller"
    }
    
    /// Determines which guide buttons (e.g., Menu, Home, Options) are supported by a given controller, which can be used for special functions like dismissing overlays.
    /// - Parameter controller: The `GCController` instance for which to determine supported guide buttons.
    /// - Returns: An array of `ControllerGuideButton` values representing the guide buttons supported by the controller.
    private func supportedGuideButtons(for controller: GCController) -> [ControllerGuideButton] {
        guard controller.extendedGamepad != nil else {
            return []
        }
        
        var buttons: [ControllerGuideButton] = []
        buttons.append(.menu)
        buttons.append(.options)
        return buttons
    }
    
    /// Retrieves the product category of a controller, which can provide additional information about the controller type for glyph detection and display purposes.
    /// - Parameter controller: The `GCController` instance for which to retrieve the product category.
    /// - Returns: A string representing the product category of the controller, or `nil` if this information is not available on the current platform version.
    private func productCategory(for controller: GCController) -> String? {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
            return controller.productCategory
        }
        return nil
    }
    
    /// Logs debug messages with a consistent prefix for easier identification in the console output.
    private func publishCaptureState() {
        onCaptureStateChanged?(
            ControllerCaptureState(
                isGuidePressed: isGuideHeld,
                pressedButtons: pressedAssignableButtons
            )
        )
    }
    
    /// A computed property that determines whether the guide button is currently active.
    private var isGuideActive: Bool {
        isGuideHeld || Date().timeIntervalSince(lastGuidePressDate) < guideChordWindow
    }
    
    /// Handles setting or clearing directional input for a given direction and action type, managing press counts for multiple input sources, held direction order for fallback behavior, and triggering the appropriate actions when directions are pressed or released.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` that is being pressed or released.
    ///   - pressed: A boolean indicating whether the direction is being pressed (`true`) or released (`false`).
    ///   - mode: The `AxisActionType` indicating whether this input is for overlay movement or arrow key emulation,  determines which state variables and actions to update.
    private func setDirectionalInput(_ direction: OverlayMoveDirection, pressed: Bool, for mode: AxisActionType) {
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
    
    /// Normalizes the input axis action types by filtering out `.none` and removing duplicates while preserving order, which simplifies the logic for determining the active input type when processing stick movements.
    /// - Parameter inputTypes: An array of `AxisActionType` values representing the configured input types for a given stick.
    /// - Returns: An array of `AxisActionType` values with `.none` removed and duplicates filtered out, preserving the original order of first occurrence.
    private func normalizedAxisActionTypes(from inputTypes: [AxisActionType]) -> [AxisActionType] {
        var seen = Set<AxisActionType>()
        return inputTypes
            .filter { $0 != .none }
            .filter { seen.insert($0).inserted }
    }
    
    /// Determines the active axis action type for a given set of input types based on the current overlay visibility and user settings for input prioritization.
    /// This method resolves conflicts when multiple input types are configured for a stick by applying a consistent prioritization logic that takes into account which
    /// overlays are currently visible and the user's preferences for how mouse and keyboard inputs should be handled in those contexts.
    /// - Parameter inputTypes: An array of `AxisActionType` values representing the configured input types for a given stick.
    /// - Returns: The resolved `AxisActionType` that should be active based on the current context and settings, or `nil` if no valid input type is active.
    private func resolvedAxisActionType(from inputTypes: [AxisActionType]) -> AxisActionType? {
        let normalized = normalizedAxisActionTypes(from: inputTypes)
        guard !normalized.isEmpty else { return nil }
        
        let mouseType = preferredMouseAxisActionType(from: normalized)
        let keyboardType = preferredKeyboardAxisActionType(from: normalized)
        
        if isMouseOverlayVisible {
            return mouseType != nil ? mouseType : keyboardType
        }
        
        if isKeyboardOverlayVisible {
            if enableMouseInKeyboard {
                if prioritizeMouseOverKeyboard {
                    return mouseType ?? keyboardType
                }
                /// Prefer keyboard when present, otherwise allow mouse.
                return keyboardType ?? mouseType
            }
            return keyboardType
        }
        
        return keyboardType
    }
    
    /// Determines the preferred mouse-related axis action type from a list of input types, prioritizing `mouseMovement` over `scrollWheel` when both are present.
    /// This method is used to resolve which mouse action should be active when processing stick movements for overlays that support mouse input.
    /// - Parameter inputTypes: An array of `AxisActionType` values representing the configured input types for a given stick.
    /// - Returns: The preferred mouse-related `AxisActionType` (`.mouseMovement`, `.scrollWheel` or `nil`) based on the configured input types.
    private func preferredMouseAxisActionType(from inputTypes: [AxisActionType]) -> AxisActionType? {
        if inputTypes.contains(.mouseMovement) {
            return .mouseMovement
        }
        if inputTypes.contains(.scrollWheel) {
            return .scrollWheel
        }
        return nil
    }
    
    /// Determines the preferred keyboard-related axis action type from a list of input types, prioritizing `overlayMovement` over `arrowKeys` when both are present.
    /// - Parameter inputTypes: An array of `AxisActionType` values representing the configured input types for a given stick.
    /// - Returns: The preferred keyboard-related `AxisActionType` (`.overlayMovement`, `.arrowKeys` or `nil`) based on the configured input types.
    private func preferredKeyboardAxisActionType(from inputTypes: [AxisActionType]) -> AxisActionType? {
        if inputTypes.contains(.overlayMovement) {
            return .overlayMovement
        }
        if inputTypes.contains(.arrowKeys) {
            return .arrowKeys
        }
        return nil
    }
    
    /// Retrieves the configured input types for a given axis input source, which determines how stick movements from that source should be processed and mapped to actions.
    /// This method is used when handling stick input to determine the active input type based on the source of the input.
    /// - Parameter source: The `AxisInput` source (left stick, right stick, or d-pad) for which to retrieve the configured input types.
    /// - Returns: An array of `AxisActionType` values representing the configured input types for the specified source.
    private func inputTypes(for source: AxisInput) -> [AxisActionType] {
        switch source {
        case .leftStick:
            return leftStickInputType
        case .rightStick:
            return rightStickInputType
        case .pad:
            return padInputType
        }
    }
    
    /// Clears the analog state for a given input source, resetting the filtered stick position, last direction, and last input type. Also stops any running analog timer for that source.
    /// - Parameter source: The `AxisInput` source (left stick, right stick, or d-pad) for which to clear the analog state.
    private func clearAnalogState(for source: AxisInput) {
        stopAnalogTimerIfNeeded(for: source)
        if var state = analogStates[source] {
            state.filteredStick = CGVector(dx: 0, dy: 0)
            state.lastDirection = nil
            state.lastInputType = nil
            analogStates[source] = state
        }
    }
    
    /// Resets the analog state for a given input source, which includes clearing the filtered stick position, last direction, and last input type, as well as stopping any running analog timer.
    /// - Parameter source: The `AxisInput` source (left stick, right stick, or d-pad) for which to reset the analog state.
    private func resetAnalogStateForSource(_ source: AxisInput) {
        clearAnalogState(for: source)
        stopAnalogTimerIfNeeded(for: source)
    }
    
    /// Resets the analog state for all input sources (left stick, right stick, and d-pad). This ensures that any stale state from previous contexts does not interfere with the new context.
    private func resetAnalogStateForContextChange() {
        for mode in [AxisInput.leftStick, .rightStick, .pad] {
            resetAnalogStateForSource(mode)
        }
    }
    
    // MARK: - Input Handling
    // MARK: Movement Handling
    /// Begins a held movement in the specified direction for the given action type (overlay movement or arrow key emulation).
    /// This method manages the state for held directions, starts the repeat timer, and triggers the initial move action.
    /// It also ensures that if the direction is already active, it does not restart the movement.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` in which to begin the held movement.
    ///   - mode: The `AxisActionType` indicating whether this movement is for overlay movement or arrow key emulation.
    private func beginHeldMovement(in direction: OverlayMoveDirection, for mode: AxisActionType = .overlayMovement) {
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
    
    /// Schedules a repeated movement action after a specified delay for the given action type (overlay movement or arrow key emulation).
    /// This method checks if the corresponding direction is still active before scheduling the repeat and uses a `DispatchWorkItem` to manage the scheduled task,
    /// allowing it to be cancelled if the direction is released before the repeat occurs.
    /// - Parameters:
    ///   - delay: The time interval after which to trigger the repeated movement action.
    ///   - mode: The `AxisActionType` indicating whether this repeat is for overlay movement or arrow key emulation.
    private func scheduleMoveRepeat(after delay: TimeInterval, for mode: AxisActionType = .overlayMovement) {
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
    
    /// Performs the repeated movement action for the active direction and action type (overlay movement or arrow key emulation).
    /// This method checks if the direction is still active, triggers the appropriate move action, increments the repeat step for acceleration,
    /// calculates the next repeat interval based on the acceleration settings, and schedules the next repeat.
    /// - Parameter mode: The `AxisActionType` indicating whether this repeat is for overlay movement or arrow key emulation.
    private func performMoveRepeat(_ mode: AxisActionType) {
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
    
    /// Stops the repeated movement action for the active direction and action type (overlay movement or arrow key emulation), optionally clearing the active direction state.
    /// - Parameters:
    ///   - clearDirection: A boolean indicating whether to clear the active direction state when stopping the repeat.
    ///   - mode: The `AxisActionType` indicating whether to stop the repeat for overlay movement or arrow key emulation.
    private func stopMoveRepeat(clearDirection: Bool, for mode: AxisActionType) {
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
    
    /// Sends a move action for the specified direction and trigger type, invoking the `onMove` callback with the appropriate parameters.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` in which the move action is occurring.
    ///   - trigger: The `OverlayMoveTrigger` indicating whether this is an initial press, a hold repeat, or another type of trigger for the move action.
    private func sendMove(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger) {
        debugLog("Move: \(direction) trigger=\(trigger)")
        onMove?(direction, trigger)
    }
    
    /// Sends a mouse movement action with the specified delta, invoking the `onMouseMove` callback.
    /// - Parameter delta: A `CGVector` representing the amount of mouse movement to apply in the x and y directions.
    private func sendMouseMove(_ delta: CGVector) {
        debugLog("Mouse Move: \(delta)")
        onMouseMove?(delta)
    }
    
    /// Sends a scroll action with the specified delta, invoking the `onScroll` callback.
    /// - Parameter delta: A `CGVector` representing the amount of scroll to apply in the horizontal and vertical directions.
    private func sendScroll(_ delta: CGVector) {
        debugLog("Scroll: \(delta)")
        onScroll?(delta)
    }
    
    /// Sends arrow key emulation for the specified direction, invoking the `onSelect` callback with the appropriate key codes for the arrow keys corresponding to the direction.
    /// - Parameter direction: The `OverlayMoveDirection` for which to send the arrow key emulation, which determines which arrow keys are emitted.
    private func sendArrowMove(_ direction: OverlayMoveDirection) {
        debugLog("Arrow Move: \(direction)")
        if !isOverlayVisible || isMouseOverlayVisible {
            return
        }
        
        if isTutorialVisible {
            switch direction {
            case .left, .upLeft, .downLeft: onArrowMoveLeft?()
            case .right, .upRight, .downRight: onArrowMoveRight?()
            default: break
            }
        } else {
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
    }
    
    // MARK: Button Input Handling
    /// Handles the press of an assignable button, determining whether it should be captured for a pending binding, trigger a toggle action if the guide is active,
    /// or invoke the appropriate callbacks based on the configured action bindings.
    /// - Parameter button: The `ControllerAssignableButton` that was pressed.
    private func handleAssignableButtonPress(_ button: ControllerAssignableButton) {
        debugLog("Button pressed: \(button)")
        
        if let pendingAssignableButtonCapture {
            self.pendingAssignableButtonCapture = nil
            pendingAssignableButtonCapture(button)
            debugLog("Captured assignable button: \(button)")
            return
        }
        
        if isGuideActive {
            if let pendingToggleCapture {
                self.pendingToggleCapture = nil
                pendingToggleCapture(button)
                debugLog("Captured toggle binding: \(button)")
                return
            }
            
            if isToggleEnabled {
                if toggleBindings.keyboardToggle == button {
                    debugLog("Toggled keyboard overlay via controller binding")
                    onToggleKeyboard?()
                } else if toggleBindings.mouseToggle == button {
                    debugLog("Toggled mouse overlay via controller binding")
                    onToggleMouse?()
                }
            }
            
            return
        }
        
        if actionBindings.accept == button {
            debugLog("Accept triggered")
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
    
    /// Handles the release of an assignable button, triggering the appropriate callbacks based on the configured action bindings for button releases.
    /// - Parameter button: The `ControllerAssignableButton` that was released.
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
