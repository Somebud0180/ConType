//
//  Settingsswift
//  ConType
//
//  Created by Ethan John Lagera on 4/18/26.
//

import AppKit
import SwiftUI
import Combine

/// A enum representing the conflict status of an input binding, used to determine if there are any conflicts and to provide appropriate user feedback in the UI.
/// - `normal` - No conflict detected.
/// - `warn(message: String)` - A potential conflict detected that may cause one binding to override another, with a warning message explaining the issue and possible resolutions.
/// - `explicit(message: String)` - A direct conflict detected where two bindings are assigned to the same input, with a message indicating
enum ConflictStatus {
    case normal
    case warn(message: String)
    case explicit(message: String)
    
    /// A property indicating whether this conflict status represents a conflicting state.
    var isConflicting: Bool {
        switch self {
        case .normal: return false
        case .warn, .explicit: return true
        }
    }
    
    /// The assigned color for each conflict status.
    var color: Color {
        switch self {
        case .normal: return .clear
        case .warn: return Color.yellow
        case .explicit: return Color.red
        }
    }
    
    /// An optional message associated with the conflict status.
    var message: String? {
        switch self {
        case .normal: return nil
        case .warn(let message), .explicit(let message): return message
        }
    }
}

/// A view struct containing the controller glyph with a fallback mechanism.
struct ControllerGlyphBadge: View {
    let assetName: String
    let fallbackText: String
    var size: CGFloat = 20
    var colorMultiply: Color = .primary
    
    var body: some View {
        let finalName = assetName.isEmpty ? "questionmark.circle.fill" : assetName
        let hasAsset = NSImage(named: finalName) != nil
        
        ZStack {
            if hasAsset {
                Image(finalName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .colorMultiply(colorMultiply)
            } else {
                Image(systemName: finalName)
                    .resizable()
                    .scaledToFit()
                    .padding(max(2, size * 0.1))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(fallbackText))
    }
}

/// ViewModel for the Settings view, responsible for managing all state and logic related to the settings UI, including handling user interactions for recording hotkeys, selecting controller bindings, managing axis input types, and providing feedback on potential input conflicts. It interacts with the `AppSettings` model to persist changes and uses callbacks to communicate with the view for actions that require user input or confirmation.
@MainActor
final class SettingsViewModel: ObservableObject {
    // Dependencies
    let settings: AppSettings
    let joystick: JoystickInputModel
    private var cancellables = Set<AnyCancellable>()
    
    // Callbacks
    private let onRequestControllerBindingCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    private let onRequestControllerActionButtonCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    private let onCancelControllerCapture: () -> Void
    private let onRestartOnboarding: () -> Void
    var onUpdateWindowSize: () -> Void
    var onTriggerHaptics: () -> Void
    
    // Permission providers (injected for test seam)
    private let permissionIsAuthorized: @MainActor () -> Bool
    private let requestPermissionAuthorization: @MainActor () -> Bool
    
    // Published UI state
    @Published var isAccessibilityTrusted: Bool
    @Published var isAwaitingPermissionGrant: Bool = false
    
    @Published var isAxisInputPopoverOpen: Bool = false
    @Published var activeAxisInputPicker: AxisInput?
    
    @Published var isRecordingKeyboardHotkey = false
    @Published var keyboardPreviewShortcut: Shortcut?
    @Published var keyboardPressedModifiers: NSEvent.ModifierFlags = []
    
    @Published var isRecordingControllerHotkey = false
    @Published var activeControllerTogglePicker: ControllerToggleBinding?
    @Published var activeControllerActionPicker: ControllerActionBinding?
    @Published var keyboardMovementStyle = KeyboardMovementMode.limited
    @Published var leftStickDeadzone: CGFloat
    @Published var rightStickDeadzone: CGFloat
    @Published var mouseSensitivity: CGFloat = 500
    @Published var mouseSmoothing: CGFloat = 0.4
    @Published var invertMouseX: Bool = false
    @Published var invertMouseY: Bool = false
    @Published var scrollSpeed: CGFloat = 600
    @Published var invertScrollX: Bool = false
    @Published var invertScrollY: Bool = false
    
    // Event monitors (not @Published)
    private var keyboardKeyDownMonitor: Any?
    private var keyboardFlagsMonitor: Any?
    private var permissionPollTimer: Timer?
    
    // Constants
    let waitingKeyboardText = "Waiting for keyboard input..."
    let waitingControllerText = "Waiting for controller input..."
    let defaultKeyboardShortcut = Shortcut(key: "k", modifiers: [.command])
    let twoDecimalFormatter = Decimal.FormatStyle().precision(.fractionLength(2))
    
    init(
        settings: AppSettings,
        joystick: JoystickInputModel,
        onRequestControllerBindingCapture: @escaping (@escaping (ControllerAssignableButton) -> Void) -> Void,
        onRequestControllerActionButtonCapture: @escaping (@escaping (ControllerAssignableButton) -> Void) -> Void,
        onCancelControllerCapture: @escaping () -> Void,
        onRestartOnboarding: @escaping () -> Void,
        onUpdateWindowSize: @escaping () -> Void,
        onTriggerHaptics: @escaping () -> Void,
        permissionIsAuthorized: @escaping @MainActor () -> Bool = InputMonitoringPermission.isAuthorized,
        requestPermissionAuthorization: @escaping @MainActor () -> Bool = InputMonitoringPermission.requestAuthorization
    ) {
        self.settings = settings
        self.joystick = joystick
        self.onRequestControllerBindingCapture = onRequestControllerBindingCapture
        self.onRequestControllerActionButtonCapture = onRequestControllerActionButtonCapture
        self.onCancelControllerCapture = onCancelControllerCapture
        self.onRestartOnboarding = onRestartOnboarding
        self.onUpdateWindowSize = onUpdateWindowSize
        self.onTriggerHaptics = onTriggerHaptics
        self.permissionIsAuthorized = permissionIsAuthorized
        self.requestPermissionAuthorization = requestPermissionAuthorization
        self.isAccessibilityTrusted = self.permissionIsAuthorized()
        self.leftStickDeadzone = settings.leftStickDeadzone
        self.rightStickDeadzone = settings.rightStickDeadzone
        self.mouseSensitivity = settings.mouseSensitivity
        self.mouseSmoothing = settings.mouseSmoothing
        self.invertMouseX = settings.invertMouseX
        self.invertMouseY = settings.invertMouseY
        self.invertScrollX = settings.invertScrollX
        self.invertScrollY = settings.invertScrollY
        self.keyboardMovementStyle = settings.keyboardMovementStyle
        
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        joystick.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        if let keyboardKeyDownMonitor {
            NSEvent.removeMonitor(keyboardKeyDownMonitor)
        }
        if let keyboardFlagsMonitor {
            NSEvent.removeMonitor(keyboardFlagsMonitor)
        }
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
    
    /// Triggers a callback to restart the onboarding flow.
    func restartOnboarding() {
        onRestartOnboarding()
    }
    
    /// Resets settings to their default values, except for the "open on startup" setting. This method updates both the `AppSettings` model and the local state properties to ensure the UI reflects the changes immediately.
    func resetDefaults() {
        // Reset all settings except open on startup
        settings.restoreDefaults(onlyHotkeys: false)
        
        // Update local state to reflect changes
        keyboardMovementStyle = settings.keyboardMovementStyle
        leftStickDeadzone = settings.leftStickDeadzone
        rightStickDeadzone = settings.rightStickDeadzone
        mouseSensitivity = settings.mouseSensitivity
        mouseSmoothing = settings.mouseSmoothing
        invertMouseX = settings.invertMouseX
        invertMouseY = settings.invertMouseY
        scrollSpeed = settings.scrollSpeed
        invertScrollX = settings.invertScrollX
        invertScrollY = settings.invertScrollY
    }
    
    // MARK: - Permission handling
    /// Requests input-monitoring permission from the OS and begins polling for changes.
    func requestPermission() {
        _ = requestPermissionAuthorization()
        isAwaitingPermissionGrant = true
        startPermissionPollingIfNeeded()
        refreshAccessibilityStatus()
    }
    
    private func startPermissionPollingIfNeeded() {
        guard permissionPollTimer == nil else { return }
        
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshAccessibilityStatus()
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }
    
    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        isAwaitingPermissionGrant = false
    }
    
    /// Refreshes the cached accessibility/input-monitoring state from the provided provider.
    private func refreshAccessibilityStatus() {
        let trusted = permissionIsAuthorized()
        let wasTrusted = isAccessibilityTrusted
        
        if wasTrusted != trusted {
            isAccessibilityTrusted = trusted
        }
        
        if trusted {
            stopPermissionPolling()
        }
    }
    
    // MARK: Computed Helpers
    /// A computed property that generates the display text for the keyboard hotkey recording state.
    var keyboardLiveRecordingText: String {
        if let keyboardPreviewShortcut {
            return keyboardPreviewShortcut.displayText
        }
        
        let activeModifiers = keyboardPressedModifiers.intersection([.control, .option, .command, .shift])
        if !activeModifiers.isEmpty {
            return modifierDisplayText(from: activeModifiers)
        }
        
        return waitingKeyboardText
    }
    
    /// A computed property that provides a description of the current keyboard movement style.
    var movementDescription: String {
        if settings.keyboardMovementStyle == KeyboardMovementMode.limited {
            return "In this style, the keyboard navigates like a D-pad."
        } else if settings.keyboardMovementStyle == KeyboardMovementMode.full {
            return "In this style, the keyboard nvaigates more freely, with diagonal movements."
        }
        
        return "This style doesn't exist"
    }
    
    // MARK: - Keyboard hotkey recording
    /// Begins the process of recording a new keyboard hotkey by setting up local event monitors for key presses and modifier changes. It ensures that any ongoing recordings for controller bindings or action pickers are cancelled to avoid conflicts. The method updates the relevant state properties to reflect that recording is in progress and captures the user's input to update the settings accordingly.
    func beginKeyboardHotkeyRecording() {
        if !isRecordingKeyboardHotkey {
            // Require input-monitoring permission before installing global/local event monitors.
            // If permission isn't granted, trigger the request flow and avoid attaching monitors that will never fire.
            if !isAccessibilityTrusted {
                requestPermission()
                return
            }
            if isRecordingControllerHotkey { endControllerToggleRecording() }
            if activeControllerActionPicker != nil { endControllerActionPicker() }
            isRecordingKeyboardHotkey = true
            keyboardPreviewShortcut = nil
            keyboardPressedModifiers = []
            
            keyboardFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self = self, self.isRecordingKeyboardHotkey else { return event }
                self.keyboardPressedModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.keyboardPreviewShortcut = nil
                return nil
            }
            
            keyboardKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isRecordingKeyboardHotkey else { return event }
                if event.keyCode == 53 {
                    self.endKeyboardHotkeyRecording()
                    return nil
                }
                self.keyboardPressedModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard let shortcut = KeyboardHotkeyManager.shortcut(from: event) else {
                    return nil
                }
                self.keyboardPreviewShortcut = shortcut
                self.settings.keyboardHotkey = shortcut
                self.endKeyboardHotkeyRecording()
                return nil
            }
        }
    }
    
    /// Ends the keyboard hotkey recording process by removing the local event monitors and resetting the relevant state properties. If the recording was cancelled (e.g., by pressing the Escape key), it ensures that any temporary state is cleared without updating the settings.
    func endKeyboardHotkeyRecording() {
        isRecordingKeyboardHotkey = false
        keyboardPreviewShortcut = nil
        keyboardPressedModifiers = []
        
        if let keyboardKeyDownMonitor {
            NSEvent.removeMonitor(keyboardKeyDownMonitor)
            self.keyboardKeyDownMonitor = nil
        }
        
        if let keyboardFlagsMonitor {
            NSEvent.removeMonitor(keyboardFlagsMonitor)
            self.keyboardFlagsMonitor = nil
        }
    }
    
    /// A computed property that provides a `Binding<Bool>` for the keyboard hotkey recording state. The setter of the binding ensures that starting or stopping the recording process is handled correctly based on the new value.
    private var keyboardRecordingPresentedBinding: Binding<Bool> {
        Binding(
            get: { self.isRecordingKeyboardHotkey },
            set: { [self] isPresented in
                if isPresented {
                    beginKeyboardHotkeyRecording()
                } else {
                    endKeyboardHotkeyRecording()
                }
            }
        )
    }
    
    // MARK: - Controller toggle recording
    /// Begins the process of recording a new controller toggle binding by triggering a callback to request input capture. It ensures that any ongoing recordings for keyboard hotkeys or controller action pickers are cancelled to avoid conflicts. The method updates the relevant state properties to reflect that recording is in progress and captures the user's input to update the settings accordingly.
    /// - Parameter toggle: The specific `ControllerToggleBinding` that is being recorded
    func beginControllerToggleRecording(for toggle: ControllerToggleBinding) {
        if !isRecordingControllerHotkey {
            if isRecordingKeyboardHotkey { endKeyboardHotkeyRecording() }
            if activeControllerActionPicker != nil { endControllerActionPicker() }
            isRecordingControllerHotkey = true
            activeControllerTogglePicker = toggle
            onRequestControllerBindingCapture { [weak self] binding in
                guard let self = self else { return }
                self.settings.controllerToggleBindings.setBinding(binding, for: toggle)
                self.endControllerToggleRecording(cancelCapture: false)
            }
        }
    }
    
    /// Ends the controller toggle recording process by resetting the relevant state properties and triggering a callback to cancel any ongoing input capture. If the recording was cancelled, it ensures that any temporary state is cleared without updating the settings.
    /// - Parameter cancelCapture: A boolean indicating whether to trigger the cancellation callback
    func endControllerToggleRecording(cancelCapture: Bool = true) {
        let wasRecording = isRecordingControllerHotkey
        isRecordingControllerHotkey = false
        activeControllerTogglePicker = nil
        if cancelCapture && wasRecording {
            onCancelControllerCapture()
        }
    }
    
    // MARK: - Controller action picker
    /// Begins the process of picking a new controller action button by triggering a callback to request input capture. It ensures that any ongoing recordings for keyboard hotkeys or controller toggle bindings are cancelled to avoid conflicts. The method updates the relevant state properties to reflect that the picker is active and captures the user's input to update the settings accordingly.
    /// - Parameter action: The `ControllerActionBinding` that is being configured
    func beginControllerActionPicker(for action: ControllerActionBinding) {
        endControllerToggleRecording()
        endKeyboardHotkeyRecording()
        
        activeControllerActionPicker = action
        armControllerActionButtonCapture(for: action)
    }
    
    /// Arms the controller action button capture by triggering the appropriate callback to listen for controller input. It checks if the active picker is still the same action to avoid
    /// - Parameter action: The `ControllerActionBinding` that is currently being configured
    private func armControllerActionButtonCapture(for action: ControllerActionBinding) {
        guard activeControllerActionPicker == action else { return }
        
        onRequestControllerActionButtonCapture { [weak self] button in
            guard let self = self else { return }
            guard self.activeControllerActionPicker == action else { return }
            self.setControllerActionButton(button, for: action)
            self.armControllerActionButtonCapture(for: action)
        }
    }
    
    /// Ends the controller action picker process by resetting the relevant state properties and triggering a callback to cancel any ongoing input capture. If the picker was active, it ensures that any temporary state is cleared without updating the settings.
    func endControllerActionPicker() {
        let wasActive = activeControllerActionPicker != nil
        activeControllerActionPicker = nil
        
        if wasActive {
            onCancelControllerCapture()
        }
    }
    
    /// Sets the controller action button for a specific action binding in the settings. This method updates the `controllerActionBindings` property of the settings and ensures that the view is updated to reflect the change.
    /// - Parameters:
    ///   - button: The `ControllerAssignableButton` that was captured for the action binding
    ///   - action: The `ControllerActionBinding` that is being configured
    func setControllerActionButton(_ button: ControllerAssignableButton, for action: ControllerActionBinding) {
        var updated = settings.controllerActionBindings
        updated.setButton(button, for: action)
        settings.controllerActionBindings = updated
        objectWillChange.send()
    }
    
    // MARK: - Utilities
    /// Sets the axis action type for a given axis input based on user selection. This method handles both addition and removal of input types, ensuring that mutually exclusive types (like keyboard vs mouse inputs) are managed correctly. It updates the appropriate settings property for the specified axis input and triggers a view update to reflect the changes.
    /// - Parameters:
    ///   - inputType: The `AxisActionType` that the user has selected or deselected for the axis input
    ///   - fromKeyboard: A `Bool` indicating whether the input type being set is a keyboard input type (true) or a mouse input type (false)
    ///   - axisInput: The `AxisInput` (e.g., left stick, right stick, or pad) for which the axis action type is being configured
    func setAxisActionType(_ inputType: AxisActionType, fromKeyboard: Bool, for axisInput: AxisInput) {
        // Get current input types for the axis
        let currentInputTypes: [AxisActionType]
        switch axisInput {
        case .leftStick:
            currentInputTypes = settings.leftStickInputType
        case .rightStick:
            currentInputTypes = settings.rightStickInputType
        case .pad:
            currentInputTypes = settings.padInputType
        }
        
        var updated = currentInputTypes
        
        if inputType == .none {
            // Removal case
            if fromKeyboard {
                // Remove both keyboard input types
                updated.removeAll { $0 == .overlayMovement || $0 == .arrowKeys }
            } else {
                // Remove both mouse input types
                updated.removeAll { $0 == .mouseMovement || $0 == .scrollWheel }
            }
        } else {
            // Addition case - enforce mutual exclusivity for keyboard types
            if inputType == .overlayMovement {
                // Remove arrowKeys if adding overlayMovement
                updated.removeAll { $0 == .arrowKeys }
                // Add overlayMovement if not already present
                if !updated.contains(.overlayMovement) {
                    updated.append(.overlayMovement)
                }
            } else if inputType == .arrowKeys {
                // Remove overlayMovement if adding arrowKeys
                updated.removeAll { $0 == .overlayMovement }
                // Add arrowKeys if not already present
                if !updated.contains(.arrowKeys) {
                    updated.append(.arrowKeys)
                }
            } else if inputType == .mouseMovement {
                // Remove scrollWheel if adding mouseMovement
                updated.removeAll { $0 == .scrollWheel }
                // Add mouseMovement if not already present
                if !updated.contains(.mouseMovement) {
                    updated.append(.mouseMovement)
                }
            } else if inputType == .scrollWheel {
                // Remove scrollWheel if adding mouseMovement
                updated.removeAll { $0 == .mouseMovement }
                // Add mouseMovement if not already present
                if !updated.contains(.scrollWheel) {
                    updated.append(.scrollWheel)
                }
            }
        }
        
        // Update the appropriate settings property
        switch axisInput {
        case .leftStick:
            settings.leftStickInputType = updated
        case .rightStick:
            settings.rightStickInputType = updated
        case .pad:
            settings.padInputType = updated
        }
        
        self.objectWillChange.send()
    }
    
    /// Checks for potential conflicts in axis input bindings based on the current settings and the type of input being configured. This method evaluates whether the selected input types for a given axis input may conflict with each other (e.g., if both keyboard and mouse inputs are assigned to the same axis) and returns an appropriate `ConflictStatus` to indicate whether there is a conflict and what the user should do to resolve it.
    /// - Parameters:
    ///   - axis: The `AxisInput` for which to check for input conflicts
    ///   - fromKeyboard: A `Bool` indicating whether the input type being checked is a keyboard input type (true) or a mouse input type (false), which affects how conflicts are evaluated and what messages are returned in the `ConflictStatus`.
    /// - Returns: A `ConflictStatus` indicating whether there is a conflict with the current axis input bindings and providing a message to guide the user in resolving it if necessary.
    func warnAxisInputConflict(for axis: AxisInput, fromKeyboard: Bool) -> ConflictStatus {
        if !settings.enableMouseInKeyboard {
            return .normal
        }
        
        let axisInputType =
        switch axis {
        case .leftStick: settings.leftStickInputType
        case .rightStick: settings.rightStickInputType
        case .pad: settings.padInputType
        }
        
        
        if (axisInputType.contains(.overlayMovement) || axisInputType.contains(.arrowKeys)) && (axisInputType.contains(.mouseMovement) || axisInputType.contains(.scrollWheel)) {
            if fromKeyboard {
                if settings.prioritizeMouseOverKeyboard {
                    return .warn(message: "This input is also assigned to the mouse and is being overriden. Disable mouse controls in the keyboard or change the input of either keyboard or mouse controls.")
                } else {
                    return .warn(message: "This input is overriding mouse control. Disable mouse controls in the keyboard or change the input of either keyboard or mouse controls.")
                }
            } else {
                if settings.prioritizeMouseOverKeyboard {
                    return .warn(message: "This input is overriding a keyboard control. Disable mouse controls in the keyboard or change the input of either mouse or keyboard controls.")
                } else {
                    return .warn(message: "This input is also assigned to the keyboard and is being overriden. Disable mouse controls in the keyboard or change the input of either keyboard or mouse controls.")
                }
            }
        }
        
        return .normal
    }
    
    /// Checks for potential conflicts in controller button bindings across all actions based on the current settings. This method iterates through all controller action bindings and compares the assigned button for the specified action with the buttons assigned to other actions. If it detects that the same button is assigned to multiple actions.
    /// - Parameter controllerButton: The `ControllerActionBinding` for which to check for button conflicts.
    /// - Returns: A `ConflictStatus` indicating the conflict status and solution message.
    func warnControllerButtonConflict(for controllerButton: ControllerActionBinding) -> ConflictStatus {
        for action in ControllerActionBinding.allCases {
            let controllerActionBindings = settings.controllerActionBindings.button(for: controllerButton)
            let forActionBindings = settings.controllerActionBindings.button(for: action)
            let actionName = action.title
            
            if action == controllerButton || controllerActionBindings == .none {
                continue
            }
            
            if forActionBindings == controllerActionBindings {
                if (ControllerActionBinding.keyboardActions.contains(controllerButton)
                    && ControllerActionBinding.mouseActions.contains(action)) {
                    if !settings.enableMouseInKeyboard {
                        return .normal
                    }
                    
                    if settings.prioritizeMouseOverKeyboard {
                        return .warn(message:"This button is also assigned to \(actionName) and is being overriden. Disable mouse controls in the keyboard or change the button of either controls.")
                    } else {
                        return .warn(message:"This button is also assigned to \(actionName) and is overriding it. Disable mouse controls in the keyboard or change the button of either controls.")
                    }
                } else if (ControllerActionBinding.mouseActions.contains(controllerButton)
                           && ControllerActionBinding.keyboardActions.contains(action)) {
                    if !settings.enableMouseInKeyboard {
                        return .normal
                    }
                    
                    if settings.prioritizeMouseOverKeyboard {
                        return .warn(message:"This button is also assigned to \(actionName) and is overriding it. Disable mouse controls in the keyboard or change the button of either controls.")
                    } else {
                        return .warn(message:"This button is also assigned to \(actionName) and is being overriden. Disable mouse controls in the keyboard or change the button of either controls.")
                    }
                }
                
                return .explicit(message: "This button is also assigned to \(actionName). Change the button for one of these actions.")
            }
        }
        
        return .normal
    }
    
    /// Generates a display string for the currently active modifier keys based on the provided `NSEvent.ModifierFlags`. This method checks for the presence of common modifier flags (Control, Option, Command, Shift) and constructs a user-friendly string representation of the active modifiers.
    /// - Parameter modifiers: The `NSEvent.ModifierFlags` containing the active modifier keys to be displayed.
    /// - Returns: A `String` representing the active modifier keys, formatted for display in the UI.
    func modifierDisplayText(from modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        return parts.joined(separator: " + ")
    }
    
    /// Generates an ordered list of `ControllerAssignableButton` based on the provided set of pressed buttons. This method filters the complete list of assignable buttons to include only those that are currently pressed, while maintaining a consistent order for display purposes in the UI.
    /// - Parameter pressedButtons: A `Set<ControllerAssignableButton>` representing the buttons that are currently pressed and should be included in the resulting list.
    /// - Returns: An ordered array of `ControllerAssignableButton` that are currently pressed, filtered from the complete list of assignable buttons.
    func orderedButtons(from pressedButtons: Set<ControllerAssignableButton>) -> [ControllerAssignableButton] {
        ControllerAssignableButton.allCases.filter { pressedButtons.contains($0) }
    }
    
    /// Generates a list of `ControllerGuideButton` to be displayed in the UI based on the detected controller's capabilities. If the detected controller does not have any specific guide buttons defined, it defaults to showing the menu button as a guide. This method ensures that the UI provides appropriate guidance for the user based on the controller they are using.
    /// - Parameter detectedController: The `DetectedController` object containing information about the currently detected controller, including its supported guide buttons.
    /// - Returns: An array of `ControllerGuideButton` that should be displayed in the UI as guides for the detected controller. If the controller has no specific guide buttons, it returns an array containing only the menu button.
    func displayedGuideButtons(for detectedController: DetectedController) -> [ControllerGuideButton] {
        if detectedController.guideButtons.isEmpty {
            return [.menu]
        }
        return detectedController.guideButtons
    }
    
    /// Generates a SwiftUI `Button` view that serves as the trigger for the axis input picker popover. This button displays the currently selected input type for the specified axis input and provides visual feedback on potential conflicts with other input types. When tapped, it toggles the visibility of the axis input picker popover, allowing the user to select a different input type for that axis.
    /// - Parameters:
    ///   - input: The `AxisInput` (e.g., left stick, right stick, or pad) for which the input picker button is being generated. This parameter determines which axis input's current selection and conflict status will be displayed on the button.
    ///   - forKeyboard: A `Bool` indicating whether the input picker button is for selecting a keyboard input type (true) or a mouse input type (false). This parameter affects how the selected input type is determined and how conflicts are evaluated and displayed on the button.
    /// - Returns: A SwiftUI `Button` view that displays the current selection for the specified axis input and toggles the axis input picker popover when tapped.
    func axisInputPickerButton(for input: AxisInput, forKeyboard: Bool) -> some View {
        let selected = selectedAxisActionType(for: input, forKeyboard: forKeyboard)
        let conflictStatus = warnAxisInputConflict(for: input, fromKeyboard: forKeyboard)
        
        return Button { [self] in
            if activeAxisInputPicker == input {
                endAxisInputPicker()
            } else {
                beginAxisInputPicker(for: input)
            }
        } label: {
            HStack(spacing: 8) {
                Text(selected.title)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 244, alignment: .leading)
            .frame(minHeight: 24)
        }
        .buttonStyle(.bordered)
        .help(conflictStatus.message ?? "")
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(conflictStatus.color, lineWidth: conflictStatus.isConflicting ? 1.5 : 0)
                .animation(.easeInOut, value: conflictStatus.isConflicting)
        )
        .popover(isPresented: axisInputPickerPopoverBinding(for: input), arrowEdge: .bottom) { [self] in
            axisInputPickerPopOver(for: input, selected: selected, forKeyboard: forKeyboard)
        }
    }
    
    
    /// Determines the currently selected `AxisActionType` for a given `AxisInput` based on the settings. This method checks the assigned input types for the specified axis input and returns the appropriate `AxisActionType` that should be displayed in the UI. It prioritizes certain input types over others to ensure that the most relevant selection is shown to the user, especially when multiple input types may be assigned to the same axis.
    /// - Parameters:
    ///   - input: The `AxisInput` for which to determine the selected `AxisActionType`
    ///   - forKeyboard: A `Bool` indicating whether to check for keyboard input types (true) or mouse input types (false)
    /// - Returns: The `AxisActionType` that is currently selected for the specified `AxisInput` based on the settings
    private func selectedAxisActionType(for input: AxisInput, forKeyboard: Bool) -> AxisActionType {
        let current: [AxisActionType]
        switch input {
        case .leftStick: current = settings.leftStickInputType
        case .rightStick: current = settings.rightStickInputType
        case .pad: current = settings.padInputType
        }
        
        if forKeyboard {
            if current.contains(.overlayMovement) { return .overlayMovement }
            if current.contains(.arrowKeys) { return .arrowKeys }
            return .none
        } else {
            if current.contains(.mouseMovement) { return .mouseMovement }
            if current.contains(.scrollWheel) { return .scrollWheel }
            return .none
        }
    }
    
    /// Begins the axis input picker process for a specified `AxisInput` by resetting any ongoing recordings or pickers for controller bindings, keyboard hotkeys, and controller actions. This method sets the `activeAxisInputPicker` state to the specified input, which triggers the display of the axis input picker popover in the UI, allowing the user to select a new input type for that axis.
    /// - Parameter input: The `AxisInput` for which to begin the input picker process
    private func beginAxisInputPicker(for input: AxisInput) {
        endControllerToggleRecording()
        endKeyboardHotkeyRecording()
        endControllerActionPicker()
        activeAxisInputPicker = input
    }
    
    /// Ends the axis input picker process by resetting the `activeAxisInputPicker` state to nil and triggering a callback to cancel any ongoing controller input capture. This method ensures that if the picker was active, any temporary state related to input selection is cleared and the UI is updated accordingly.
    private func endAxisInputPicker() {
        let wasActive = activeAxisInputPicker != nil
        activeAxisInputPicker = nil
        if wasActive {
            onCancelControllerCapture()
        }
    }
    
    /// Generates a `Binding<Bool>` for the presentation state of the axis input picker popover for a specific `AxisInput`. The getter of the binding checks if the currently active axis input picker matches the specified input, while the setter handles the logic for beginning or ending the axis input picker process based on the new value.
    /// - Parameter input: The `AxisInput` for which to generate the binding for the input picker popover presentation state
    /// - Returns: A `Binding<Bool>` that indicates whether the axis input picker popover for the specified `AxisInput` is currently presented, and handles the logic for showing or hiding the popover when the value changes.
    private func axisInputPickerPopoverBinding(for input: AxisInput) -> Binding<Bool> {
        Binding(
            get: { self.activeAxisInputPicker == input },
            set: { [self] isPresented in
                if isPresented {
                    beginAxisInputPicker(for: input)
                } else if activeAxisInputPicker == input {
                    endAxisInputPicker()
                }
            }
        )
    }
    
    /// Generates the content for the axis input picker popover, which allows the user to select a new input type for a specific `AxisInput`. This view displays the available input options based on whether the picker is for keyboard or mouse inputs, and provides visual feedback on the currently selected input type.
    /// - Parameters:
    ///   - input: The `AxisInput` for which the input picker popover content is being generated
    ///   - selected: The currently selected `AxisActionType` for the specified `AxisInput`
    ///   - forKeyboard: A `Bool` indicating whether the input picker is for selecting a keyboard input type (true) or a mouse input type (false).
    /// - Returns: A SwiftUI view that represents the content of the axis input picker popover.
    @ViewBuilder
    private func axisInputPickerPopOver(for input: AxisInput, selected: AxisActionType, forKeyboard: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Input")
                .font(.headline)
            
            Text(forKeyboard ? "Select a keyboard input type." : "Select a mouse input type.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            let options = forKeyboard ? AxisActionType.keyboardOptions : AxisActionType.mouseOptions
            
            ForEach(options) { [self] type in
                let isSelected = type == selected
                
                Button {
                    self.setAxisActionType(type, fromKeyboard: forKeyboard, for: input)
                } label: {
                    HStack {
                        Text(type.title)
                        Spacer(minLength: 8)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") { [self] in
                    endAxisInputPicker()
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
    
    /// Generates a SwiftUI `Button` view that serves as the trigger for the controller action picker popover for a specific `ControllerActionBinding`. This button displays the currently assigned controller button for the specified action and provides visual feedback on potential conflicts with other action bindings. When tapped, it toggles the visibility of the controller action picker popover, allowing the user to select a different controller button for that action.
    /// - Parameter action: The `ControllerActionBinding` for which the controller action picker button is being generated
    /// - Returns: A SwiftUI `Button` view that displays the current controller button assigned to the specified action
    func controllerActionPickerButton(for action: ControllerActionBinding) -> some View {
        let selectedButton = settings.controllerActionBindings.button(for: action)
        let conflictStatus = warnControllerButtonConflict(for: action)
        
        return Button { [self] in
            if activeControllerActionPicker == action {
                endControllerActionPicker()
            } else {
                beginControllerActionPicker(for: action)
            }
        } label: {
            HStack(spacing: 8) {
                buttonGlyph(selectedButton)
                Text(selectedButton.displayTitle(for: settings.controllerGlyphStyle))
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 230, alignment: .leading)
            .frame(minHeight: 24)
        }
        .buttonStyle(.bordered)
        .help(conflictStatus.message ?? "")
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(conflictStatus.color, lineWidth: conflictStatus.isConflicting ? 1.5 : 0)
                .animation(.easeInOut, value: conflictStatus.isConflicting)
        )
        .popover(isPresented: controllerActionPickerPresentedBinding(for: action), arrowEdge: .bottom) { [self] in
            controllerActionPickerPopover(for: action, selected: selectedButton)
        }
    }
    
    /// Generates the content for the controller action picker popover, which allows the user to select a new controller button for a specific `ControllerActionBinding`. This view displays a list of all available controller buttons, highlighting the currently selected button and allowing the user to choose a different one. It also provides instructions for how to select a button using the controller input.
    /// - Parameters:
    ///   - action: The `ControllerActionBinding` for which the controller action picker popover content is being generated
    ///   - selected: The currently selected `ControllerAssignableButton` for the specified action
    /// - Returns: A SwiftUI view that represents the content of the controller action picker popover
    @ViewBuilder
    func controllerActionPickerPopover(for action: ControllerActionBinding, selected: ControllerAssignableButton) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Controller Button")
                .font(.headline)
            
            Text("Press a controller button or click an option below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            ForEach(ControllerAssignableButton.allCases) { [self] button in
                let isSelected = selected == button
                
                Button {
                    self.setControllerActionButton(button, for: action)
                } label: {
                    HStack {
                        HStack(spacing: 8) {
                            buttonGlyph(button)
                            Text(button.displayTitle(for: settings.controllerGlyphStyle))
                        }
                        
                        Spacer(minLength: 8)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") { [self] in
                    endControllerActionPicker()
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
    
    /// Generates a generic guide glyph button that can be used as a fallback when a specific guide button asset is not available for the detected controller. This button displays a default game controller icon and the text "Guide" to indicate its purpose as a guide button in the UI.
    /// - Parameter size: A `CGFloat` value that specifies the size of the glyph badge to be displayed on the button
    /// - Returns: A SwiftUI view that represents a generic guide glyph button
    func genericGuideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size
        )
    }
    
    /// Generates a SwiftUI view that displays the appropriate glyphs for a given `ControllerGuideButton` based on the current controller glyph style settings. If a specific asset is available for the button and glyph style, it uses the `ControllerGlyphBadge` to display it. Otherwise, it falls back to displaying a text representation of the button with styling to indicate that it is a guide button.
    /// - Parameters:
    ///   - button: The `ControllerGuideButton` for which to generate the glyph view
    ///   - size: A `CGFloat` value that specifies the size of the glyph badge or text to be displayed for the guide button
    /// - Returns: A SwiftUI view that represents the glyphs for the specified `ControllerGuideButton`
    @ViewBuilder
    func controllerGuideGlyphs(_ button: ControllerGuideButton, size: CGFloat = 20) -> some View {
        let title = button.displayTitle(for: settings.controllerGlyphStyle)
        if let assetName = button.glyphAssetName(for: settings.controllerGlyphStyle) {
            ControllerGlyphBadge(
                assetName: assetName,
                fallbackText: title,
                size: size
            )
        } else {
            Text(title)
                .font(.system(size: max(10, size * 0.45), weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, max(4, size * 0.24))
                .frame(height: size)
                .background(
                    RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .accessibilityLabel(Text(title))
        }
    }
    
    /// Generates a SwiftUI view that displays the glyph for a given `ControllerAssignableButton` based on the current controller glyph style settings. If a specific asset is available for the button and glyph style, it uses `ControllerGlyphBadge` to display it.
    /// - Parameters:
    ///   - button: The `ControllerAssignableButton` for which to generate the glyph view
    ///   - size: The size of the glyph badge in `CGFloat`
    /// - Returns: A SwiftUI view that represents the glyph for the specified `ControllerAssignableButton`
    private func buttonGlyph(_ button: ControllerAssignableButton, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: button.glyphAssetName(for: settings.controllerGlyphStyle),
            fallbackText: button.fallbackGlyphText,
            size: size
        )
    }
    
    /// Generates a `Binding<Bool>` for the presentation state of the controller action picker popover for a specific `ControllerActionBinding`. The getter of the binding checks if the currently active controller action picker matches the specified action, while the setter handles the logic for beginning or ending the controller action picker process based on the new value.
    /// - Parameter action: The `ControllerActionBinding` for which to generate the binding for the controller action picker popover presentation state
    /// - Returns: A `Binding<Bool>` that indicates whether the controller action picker popover for the specified `ControllerActionBinding` is currently presented and handles the logic for showing or hiding the popover when the value changes
    private func controllerActionPickerPresentedBinding(for action: ControllerActionBinding) -> Binding<Bool> {
        Binding(
            get: { self.activeControllerActionPicker == action },
            set: { [self] isPresented in
                if isPresented {
                    beginControllerActionPicker(for: action)
                } else if activeControllerActionPicker == action {
                    endControllerActionPicker()
                }
            }
        )
    }
    
    /// Generates a SwiftUI `Button` view that serves as the trigger for the controller toggle picker popover for a specific `ControllerToggleBinding`. This button displays the currently assigned controller button for the specified toggle action and provides visual feedback on potential conflicts with other toggle bindings. When tapped, it toggles the visibility of the controller toggle picker popover, allowing the user to select a different controller button for that toggle action.
    /// - Parameter toggle: The `ControllerToggleBinding` for which the controller toggle picker button is being generated
    /// - Returns: A SwiftUI `Button` view that displays the current controller button assigned to the specified toggle action
    func controllerTogglePickerButton(for toggle: ControllerToggleBinding) -> some View {
        let selectedButton = settings.controllerToggleBindings.binding(for: toggle)
        
        return Button { [self] in
            if activeControllerTogglePicker == toggle {
                endControllerToggleRecording()
            } else {
                beginControllerToggleRecording(for: toggle)
            }
        } label: {
            HStack(spacing: 8) {
                genericGuideGlyph(size: 20)
                Text("+")
                    .foregroundStyle(.secondary)
                buttonGlyph(selectedButton, size: 20)
                Text(selectedButton.displayTitle(for: settings.controllerGlyphStyle))
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 230, alignment: .leading)
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: controllerToggleRecordingPresentedBinding(for: toggle), arrowEdge: .bottom) { [self] in
            controllerTogglePopover(for: toggle)
        }
    }
    
    /// Generates a `Binding<Bool>` for the presentation state of the controller toggle picker popover for a specific `ControllerToggleBinding`. The getter of the binding checks if the currently active controller toggle picker matches the specified toggle, while the setter handles the logic for beginning or ending the controller toggle recording process based on the new value.
    /// - Parameter toggle: The `ControllerToggleBinding` for which to generate the binding for the controller toggle picker popover presentation state
    /// - Returns: A `Binding<Bool>` that indicates whether the controller toggle picker popover for the specified `ControllerToggleBinding` is currently presented and handles the logic for showing or hiding the popover when the value changes
    private func controllerToggleRecordingPresentedBinding(for toggle: ControllerToggleBinding) -> Binding<Bool> {
        Binding(
            get: { self.activeControllerTogglePicker == toggle },
            set: { [self] isPresented in
                if !isPresented {
                    endControllerToggleRecording()
                } else {
                    beginControllerToggleRecording(for: toggle)
                }
            }
        )
    }
    
    /// Generates the content for the controller toggle picker popover, which allows the user to select a new controller button for a specific `ControllerToggleBinding`. This view displays instructions for how to select a button using the controller input, shows the currently pressed buttons on the controller, and provides an example of what the input should look like when properly recorded.
    /// - Parameter toggle: The `ControllerToggleBinding` for which the controller toggle picker popover content is being generated
    /// - Returns: A SwiftUI view that represents the content of the controller toggle picker popover
    @ViewBuilder
    private func controllerTogglePopover(for toggle: ControllerToggleBinding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Press Controller Shortcut")
                .font(.headline)
            
            Text(toggle.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            RecordingDisplayContainer {
                ControllerChordView(
                    guidePressed: settings.controllerCaptureState.isGuidePressed,
                    buttons: orderedButtons(from: settings.controllerCaptureState.pressedButtons),
                    waitingText: waitingControllerText,
                    controllerGlyphStyle: settings.controllerGlyphStyle
                )
            }
            
            Divider()
            
            Text("Example")
                .font(.subheadline.weight(.semibold))
            
            ControllerChordView(
                guidePressed: true,
                buttons: [.west],
                waitingText: waitingControllerText,
                controllerGlyphStyle: settings.controllerGlyphStyle
            )
            .foregroundStyle(.secondary)
            
            HStack {
                Spacer()
                Button("Cancel") { [self] in
                    endControllerToggleRecording()
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }
    
    // MARK: - UI Variables
    /// A button that serves as the trigger for the keyboard hotkey recording popover.
    var keyboardShortcutButton: some View {
        Button { [self] in
            beginKeyboardHotkeyRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
                Text(settings.keyboardHotkey.displayText)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 230, alignment: .leading)
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: keyboardRecordingPresentedBinding, arrowEdge: .bottom) {
            self.keyboardShortcutPopover
        }
    }
    
    /// A button that displays the currently assigned keyboard shortcut for a specific action and provides visual feedback on potential conflicts with other keyboard bindings.
    private var keyboardShortcutPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Press Keyboard Shortcut")
                .font(.headline)
            
            RecordingDisplayContainer {
                Text(keyboardLiveRecordingText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(keyboardLiveRecordingText == waitingKeyboardText ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            Text("Example")
                .font(.subheadline.weight(.semibold))
            
            Text(defaultKeyboardShortcut.displayText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Text("Press Esc to cancel.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 300)
    }
    
    /// A view that displays the current positions of the left and right sticks on the controller, along with sliders to adjust the deadzone radius for each stick and a visual representation of the deadzone area. This view allows users to configure the stick deadzone settings while providing real-time feedback on how the stick inputs are being registered in relation to the configured deadzone.
    var stickDeadzoneConfig: some View {
        VStack(alignment: .leading) {
            Text("Left Stick")
                .font(.headline)
            HStack(spacing: 24) {
                StickDeadzoneVisualizer(
                    stickPosition: joystick.leftStick,
                    deadzoneRadius: settings.leftStickDeadzone,
                    size: 100
                )
                
                stickSliders(localDeadzone: Binding(get: { self.leftStickDeadzone }, set: { [self] newVal in
                    leftStickDeadzone = newVal
                    settings.leftStickDeadzone = newVal
                }), settingsDeadzone: Binding(
                    get: { self.settings.leftStickDeadzone },
                    set: { self.settings.leftStickDeadzone = $0 }
                ))
                
                Text(Decimal.FormatStyle.FormatInput(leftStickDeadzone), format: twoDecimalFormatter)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            
            Divider()
            
            Text("Right Stick")
                .font(.headline)
            HStack(spacing: 24) {
                StickDeadzoneVisualizer(
                    stickPosition: joystick.rightStick,
                    deadzoneRadius: settings.rightStickDeadzone,
                    size: 100
                )
                
                stickSliders(localDeadzone: Binding(get: { self.rightStickDeadzone }, set: { [self] newVal in
                    rightStickDeadzone = newVal
                    settings.rightStickDeadzone = newVal
                }), settingsDeadzone: Binding(
                    get: { self.settings.rightStickDeadzone },
                    set: { self.settings.rightStickDeadzone = $0 }
                ))
                
                Text(Decimal.FormatStyle.FormatInput(rightStickDeadzone), format: twoDecimalFormatter)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
        }
    }
    
    /// A view that contains sliders and toggles for configuring mouse sensitivity, mouse smoothing, and axis inversion settings. This view allows users to adjust their mouse input preferences while providing real-time feedback on the current values of these settings.
    var mouseConfig: some View {
        Group {
            HStack {
                Slider(value: Binding(
                    get: { self.mouseSensitivity },
                    set: { self.mouseSensitivity = $0.rounded() }
                ), in: 100...1000, step: 50) {
                    Text("Sensitivity")
                }
                .onChange(of: self.mouseSensitivity) { [self] in
                    settings.mouseSensitivity = mouseSensitivity
                }
                
                Text(mouseSensitivity, format: .number)
                    .frame(width: 40, alignment: .trailing)
            }
            
            HStack {
                Slider(value: Binding<Double>(
                    get: { Double(self.mouseSmoothing) },
                    set: { self.mouseSmoothing = CGFloat(($0 * 100).rounded() / 100) }
                ), in: 0.0...0.8, step: 0.05) {
                    Text("Smoothing")
                }
                .onChange(of: self.mouseSmoothing) { [self] in
                    settings.mouseSmoothing = mouseSmoothing
                }
                
                Text(Decimal.FormatStyle.FormatInput(mouseSmoothing), format: twoDecimalFormatter)
                    .frame(width: 40, alignment: .trailing)
            }
            
            Toggle("Invert mouse X-axis", isOn: Binding(
                get: { self.invertMouseX },
                set: { self.invertMouseX = $0 }
            ))
            .onChange(of: self.invertMouseX) { [self] in
                settings.invertMouseX = invertMouseX
            }
            
            Toggle("Invert mouse Y-axis", isOn: Binding(
                get: { self.invertMouseY },
                set: { self.invertMouseY = $0 }
            ))
            .onChange(of: self.invertMouseY) { [self] in
                settings.invertMouseY = invertMouseY
            }
        }
    }
    
    /// A view that contains a slider for configuring the scroll speed setting, as well as toggles for inverting the scroll direction on the X and Y axes. This view allows users to adjust their scroll input preferences while providing real-time feedback on the current values of these settings.
    var scrollConfig: some View {
        Group {
            HStack {
                Slider(value: Binding<Double>(
                    get: { Double(self.scrollSpeed) },
                    set: { self.scrollSpeed = $0.rounded() }
                ), in: 100...2000, step: 100) {
                    Text("Scrolling Speed")
                }
                .onChange(of: self.scrollSpeed) { [self] in
                    settings.scrollSpeed = scrollSpeed
                }
                
                Text(scrollSpeed, format: .number)
                    .frame(width: 40, alignment: .trailing)
            }
            
            Toggle("Invert scroll X-axis", isOn: Binding(
                get: { self.invertScrollX },
                set: { self.invertScrollX = $0 }
            ))
            .onChange(of: self.invertScrollX) { [self] in
                settings.invertScrollX = invertScrollX
            }
            
            Toggle("Invert scroll Y-axis", isOn: Binding(
                get: { self.invertScrollY },
                set: { self.invertScrollY = $0 }
            ))
            .onChange(of: self.invertScrollY) { [self] in
                settings.invertScrollY = invertScrollY
            }
        }
    }
    
    // MARK: - UI Structs
    /// A container view that provides consistent styling for displaying the current input being recorded for controller toggles and keyboard hotkeys. This view uses a rounded rectangle background with a subtle stroke to create a distinct area for showing the live recording feedback, and it accepts any content view that represents the current input state.
    /// - Parameter content: A view builder closure that generates the content to be displayed inside the recording display container
    /// - Returns: A SwiftUI view that represents the styled container for displaying the current input being recorded for controller toggles and keyboard hotkeys
    @ViewBuilder
    func RecordingDisplayContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }
    
    /// Generates a SwiftUI view that displays the appropriate combination of controller glyphs for a given controller toggle input, including the guide button and any additional buttons that are currently pressed on the controller. If no buttons are currently pressed and the guide button is not active, it displays a waiting text message instead. This view provides real-time feedback on the current state of the controller inputs during the recording process for controller toggles.
    /// - Parameters:
    ///   - guidePressed: A `Bool` indicating whether the guide button is currently pressed on the controller
    ///   - buttons: An array of `ControllerAssignableButton` values representing the additional buttons that are currently pressed on the controller
    ///   - waitingText: A `String` value that specifies the text to be displayed when no buttons are currently pressed
    ///   - controllerGlyphStyle: The `ControllerGlyphStyle` that should be used to determine which glyph assets to display
    /// - Returns: A SwiftUI view that represents the combination of controller glyphs for the current state of the controller inputs during the recording process for controller toggles
    @ViewBuilder func ControllerChordView(
        guidePressed: Bool,
        buttons: [ControllerAssignableButton],
        waitingText: String,
        controllerGlyphStyle: ControllerGlyphStyle
    ) -> some View {
        if !guidePressed && buttons.isEmpty {
            Text(waitingText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                if guidePressed {
                    HStack(spacing: 6) {
                        genericGuideGlyph(size: 20)
                        Text("Guide")
                    }
                    
                    if !buttons.isEmpty {
                        Text("+")
                            .foregroundStyle(.secondary)
                    }
                }
                
                ForEach(Array(buttons.enumerated()), id: \.element) {
                    index,
                    button in
                    if index > 0 {
                        Text("+")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        ControllerGlyphBadge(
                            assetName: button.glyphAssetName(
                                for: controllerGlyphStyle
                            ),
                            fallbackText: button.fallbackGlyphText,
                            size: 20
                        )
                        Text(button.displayTitle(for: controllerGlyphStyle))
                    }
                }
            }
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    /// Generates a visual representation of the joystick stick position and deadzone area for a given stick input. This view displays an outer circle representing the maximum range of the joystick, an inner circle representing the configured deadzone radius, and a dot indicating the current position of the stick. The color of the deadzone circle changes based on whether the stick is currently outside of the deadzone, providing real-time feedback on how the stick inputs are being registered in relation to the configured deadzone settings.
    /// - Parameters:
    ///   - stickPosition: The `CGVector` representing the current position of the joystick stick
    ///   - deadzoneRadius: The `CGFloat` value representing the radius of the deadzone area for the stick
    ///   - size: The `CGFloat` value representing the overall size of the visualizer view (default is 100)
    /// - Returns: A SwiftUI view that visually represents the joystick stick position and deadzone area based on the provided parameters
    @ViewBuilder func StickDeadzoneVisualizer(
        stickPosition: CGVector,
        deadzoneRadius: CGFloat,
        size: CGFloat = 100
    ) -> some View {
        let length = sqrt(stickPosition.dx * stickPosition.dx + stickPosition.dy * stickPosition.dy)
        let stick = if length > 1.0 {
            CGVector(dx: stickPosition.dx / length, dy: stickPosition.dy / length)
        } else {
            stickPosition
        }
        
        let isOutsideDeadzone = length > deadzoneRadius
        
        ZStack {
            // Outer circle (joystick range)
            Circle()
                .stroke(Color.primary.opacity(0.3), lineWidth: 2)
                .frame(width: size, height: size)
            // Deadzone circle
            Circle()
                .stroke(isOutsideDeadzone ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.5), lineWidth: 2)
                .frame(width: size * deadzoneRadius, height: size * deadzoneRadius)
            // Stick dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 14, height: 14)
                .offset(x: stick.dx * (size/2 - 7), y: -stick.dy * (size/2 - 7))
                .shadow(radius: 2)
        }
        .onChange(of: isOutsideDeadzone) {
            self.onTriggerHaptics()
        }
        .frame(width: size, height: size)
    }
    
    /// Generates a SwiftUI view that contains a slider for adjusting the deadzone radius of a joystick stick, along with an `onChange` handler that updates the corresponding deadzone setting in the view model whenever the slider value changes. This view allows users to configure the stick deadzone settings while providing real-time feedback on how the changes affect the stick input registration.
    /// - Parameters:
    ///   - localDeadzone: A `Binding<CGFloat>` that represents the local state of the deadzone radius for the stick being configured
    ///   - settingsDeadzone: A `Binding<CGFloat>` that represents the deadzone setting
    /// - Returns: A SwiftUI view that contains a slider for adjusting the deadzone radius of a joystick stick and updates the corresponding setting in the view model when the value changes
    @ViewBuilder
    func stickSliders(localDeadzone: Binding<CGFloat>, settingsDeadzone: Binding<CGFloat>) -> some View {
        Slider(
            value: Binding<Double>(
                get: { Double(localDeadzone.wrappedValue) },
                set: { localDeadzone.wrappedValue = CGFloat(($0 * 100).rounded() / 100) }
            ),
            in: 0.0...0.8
        ) {
            Text("Deadzone")
        }
        .onChange(of: localDeadzone.wrappedValue) {
            settingsDeadzone.wrappedValue = localDeadzone.wrappedValue
        }
    }
}

#Preview {
    let vm = SettingsViewModel(
        settings: AppSettings(),
        joystick: JoystickInputModel(manager: ControllerInputManager()),
        onRequestControllerBindingCapture: { _ in },
        onRequestControllerActionButtonCapture: { _ in },
        onCancelControllerCapture: {},
        onRestartOnboarding: {},
        onUpdateWindowSize: {},
        onTriggerHaptics: {}
    )
    
    SettingsView(viewModel: vm)
}
