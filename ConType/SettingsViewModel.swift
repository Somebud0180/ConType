//
//  Settingsswift
//  ConType
//
//  Created by Ethan John Lagera on 4/18/26.
//

import AppKit
import SwiftUI
import Combine

enum ConflictStatus {
    case normal
    case warn(message: String)
    case explicit(message: String)
    
    var isConflicting: Bool {
        switch self {
        case .normal: return false
        case .warn, .explicit: return true
        }
    }
    
    var color: Color {
        switch self {
        case .normal: return .clear
        case .warn: return Color.yellow
        case .explicit: return Color.red
        }
    }
    
    var message: String? {
        switch self {
        case .normal: return nil
        case .warn(let message), .explicit(let message): return message
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    // Dependencies
    let settings: AppSettings
    let joystick: JoystickInputModel
    private var cancellables = Set<AnyCancellable>()
    
    // Callbacks
    private let onRequestControllerBindingCapture: (@escaping (ControllerToggleBinding) -> Void) -> Void
    private let onRequestControllerActionButtonCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    private let onCancelControllerCapture: () -> Void
    private let onRestartOnboarding: () -> Void
    
    // Published UI state
    @Published var isAccessibilityTrusted: Bool
    
    @Published var isAxisInputPopoverOpen: Bool = false
    @Published var activeAxisInputPicker: AxisInput?
    
    @Published var isRecordingKeyboardHotkey = false
    @Published var keyboardPreviewShortcut: KeyboardHotkeyManager.Shortcut?
    @Published var keyboardPressedModifiers: NSEvent.ModifierFlags = []
    
    @Published var isRecordingControllerHotkey = false
    @Published var activeControllerActionPicker: ControllerActionBinding?
    @Published var keyboardMovementStyle = KeyboardMovementMode.limited
    @Published var leftStickDeadzone: CGFloat
    @Published var rightStickDeadzone: CGFloat
    @Published var mouseSensitivity: CGFloat = 500
    @Published var mouseSmoothing: CGFloat = 0.5
    
    // Event monitors (not @Published)
    private var keyboardKeyDownMonitor: Any?
    private var keyboardFlagsMonitor: Any?
    
    // Constants
    let waitingKeyboardText = "Waiting for keyboard input..."
    let waitingControllerText = "Waiting for controller input..."
    let defaultKeyboardShortcut = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])
    let twoDecimalFormatter = Decimal.FormatStyle().precision(.fractionLength(2))
    
    init(
        settings: AppSettings,
        joystick: JoystickInputModel,
        onRequestControllerBindingCapture: @escaping (@escaping (ControllerToggleBinding) -> Void) -> Void,
        onRequestControllerActionButtonCapture: @escaping (@escaping (ControllerAssignableButton) -> Void) -> Void,
        onCancelControllerCapture: @escaping () -> Void,
        onRestartOnboarding: @escaping () -> Void
    ) {
        self.settings = settings
        self.joystick = joystick
        self.onRequestControllerBindingCapture = onRequestControllerBindingCapture
        self.onRequestControllerActionButtonCapture = onRequestControllerActionButtonCapture
        self.onCancelControllerCapture = onCancelControllerCapture
        self.onRestartOnboarding = onRestartOnboarding
        self.isAccessibilityTrusted = InputMonitoringPermission.isAuthorized()
        self.leftStickDeadzone = settings.leftStickDeadzone
        self.rightStickDeadzone = settings.rightStickDeadzone
        self.mouseSensitivity = settings.mouseSensitivity
        self.mouseSmoothing = settings.mouseSmoothing
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
    
    func restartOnboarding() {
        onRestartOnboarding()
    }
    
    func resetDefaults() {
        // Reset all settings except open on startup
        settings.keyboardHotkey = defaultKeyboardShortcut
        settings.controllerToggleBinding = .default
        settings.controllerActionBindings = .default
        settings.keyboardLayout = .QWERTY
        settings.leftStickInputType = [.overlayMovement]
        settings.rightStickInputType = [.mouseMovement]
        settings.padInputType = [.overlayMovement]
        settings.shiftShortcutCyclesToCapsLock = true
        settings.dismissWithGuideButton = true
        settings.keyboardMovementStyle = .limited
        settings.leftStickDeadzone = 0.2
        settings.rightStickDeadzone = 0.2
        settings.mouseSensitivity = 300
        settings.mouseSmoothing = 0.5
        settings.windowSize = .small
        settings.windowPosition = .zero
        
        // Update local state to reflect changes
        keyboardMovementStyle = settings.keyboardMovementStyle
        leftStickDeadzone = settings.leftStickDeadzone
        rightStickDeadzone = settings.rightStickDeadzone
        mouseSensitivity = settings.mouseSensitivity
        mouseSmoothing = settings.mouseSmoothing
    }
    
    deinit {
        if let keyboardKeyDownMonitor {
            NSEvent.removeMonitor(keyboardKeyDownMonitor)
        }
        if let keyboardFlagsMonitor {
            NSEvent.removeMonitor(keyboardFlagsMonitor)
        }
    }
    
    // Computed helpers
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
    
    var movementDescription: String {
        if settings.keyboardMovementStyle == KeyboardMovementMode.limited {
            return "In this style, the keyboard navigates like a D-pad."
        } else if settings.keyboardMovementStyle == KeyboardMovementMode.full {
            return "In this style, the keyboard nvaigates more freely, with diagonal movements."
        }
        
        return "This style doesn't exist"
    }
    
    // MARK: - Keyboard hotkey recording
    
    func beginKeyboardHotkeyRecording() {
        if !isRecordingKeyboardHotkey {
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
    
    func endKeyboardHotkeyRecording() {
        DispatchQueue.main.async {
            self.isRecordingKeyboardHotkey = false
            self.keyboardPreviewShortcut = nil
            self.keyboardPressedModifiers = []
        }
        
        if let keyboardKeyDownMonitor {
            NSEvent.removeMonitor(keyboardKeyDownMonitor)
            self.keyboardKeyDownMonitor = nil
        }
        
        if let keyboardFlagsMonitor {
            NSEvent.removeMonitor(keyboardFlagsMonitor)
            self.keyboardFlagsMonitor = nil
        }
    }
    
    // MARK: - Controller toggle recording
    func beginControllerToggleRecording() {
        if !isRecordingControllerHotkey {
            if isRecordingKeyboardHotkey { endKeyboardHotkeyRecording() }
            if activeControllerActionPicker != nil { endControllerActionPicker() }
            isRecordingControllerHotkey = true
            onRequestControllerBindingCapture { [weak self] binding in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.settings.controllerToggleBinding = binding
                    self.endControllerToggleRecording(cancelCapture: false)
                }
            }
        }
    }
    
    func endControllerToggleRecording(cancelCapture: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let wasRecording = self.isRecordingControllerHotkey
            self.isRecordingControllerHotkey = false
            if cancelCapture && wasRecording {
                self.onCancelControllerCapture()
            }
        }
    }
    
    // MARK: - Controller action picker
    
    func beginControllerActionPicker(for action: ControllerActionBinding) {
        endControllerToggleRecording()
        endKeyboardHotkeyRecording()
        
        activeControllerActionPicker = action
        armControllerActionButtonCapture(for: action)
    }
    
    private func armControllerActionButtonCapture(for action: ControllerActionBinding) {
        guard activeControllerActionPicker == action else { return }
        
        onRequestControllerActionButtonCapture { [weak self] button in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.activeControllerActionPicker == action else { return }
                self.setControllerActionButton(button, for: action)
                self.armControllerActionButtonCapture(for: action)
            }
        }
    }
    
    func endControllerActionPicker() {
        let wasActive = activeControllerActionPicker != nil
        activeControllerActionPicker = nil
        
        if wasActive {
            onCancelControllerCapture()
        }
    }
    
    func setControllerActionButton(_ button: ControllerAssignableButton, for action: ControllerActionBinding) {
        DispatchQueue.main.async {
            var updated = self.settings.controllerActionBindings
            updated.setButton(button, for: action)
            self.settings.controllerActionBindings = updated
            // Force view update if needed
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Utilities
    func setAxisInputType(_ inputType: AxisInputType, fromKeyboard: Bool, for axisInput: AxisInput) {
        // Get current input types for the axis
        let currentInputTypes: [AxisInputType]
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
    
    func modifierDisplayText(from modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        return parts.joined(separator: " + ")
    }
    
    func orderedButtons(from pressedButtons: Set<ControllerAssignableButton>) -> [ControllerAssignableButton] {
        ControllerAssignableButton.allCases.filter { pressedButtons.contains($0) }
    }
    
    func displayedGuideButtons(for detectedController: DetectedController) -> [ControllerGuideButton] {
        if detectedController.guideButtons.isEmpty {
            return [.menu]
        }
        return detectedController.guideButtons
    }
    
    func axisInputPickerButton(for input: AxisInput, forKeyboard: Bool) -> some View {
        let selected = selectedAxisInputType(for: input, forKeyboard: forKeyboard)
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
    
    // Helpers for axis input picker
    private func selectedAxisInputType(for input: AxisInput, forKeyboard: Bool) -> AxisInputType {
        let current: [AxisInputType]
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
    
    private func beginAxisInputPicker(for input: AxisInput) {
        endControllerToggleRecording()
        endKeyboardHotkeyRecording()
        endControllerActionPicker()
        activeAxisInputPicker = input
    }
    
    private func endAxisInputPicker() {
        let wasActive = activeAxisInputPicker != nil
        activeAxisInputPicker = nil
        if wasActive {
            onCancelControllerCapture()
        }
    }
    
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
    
    @ViewBuilder
    private func axisInputPickerPopOver(for input: AxisInput, selected: AxisInputType, forKeyboard: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Input")
                .font(.headline)
            
            Text(forKeyboard ? "Select a keyboard input type." : "Select a mouse input type.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            let options = forKeyboard ? AxisInputType.keyboardOptions : AxisInputType.mouseOptions
            
            ForEach(options) { [self] type in
                let isSelected = type == selected
                
                Button {
                    self.setAxisInputType(type, fromKeyboard: forKeyboard, for: input)
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
    
    func genericGuideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size
        )
    }
    
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
    
    private func buttonGlyph(_ button: ControllerAssignableButton, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: button.glyphAssetName(for: settings.controllerGlyphStyle),
            fallbackText: button.fallbackGlyphText,
            size: size
        )
    }
    
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
    
    // MARK: - UI Variables
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
    
    var controllerToggleButton: some View {
        Button { [self] in
            beginControllerToggleRecording()
        } label: {
            HStack(spacing: 8) {
                genericGuideGlyph(size: 26)
                Text("+")
                    .foregroundStyle(.secondary)
                buttonGlyph(settings.controllerToggleBinding.button, size: 26)
            }
            .frame(width: 230, alignment: .leading)
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: controllerToggleRecordingPresentedBinding, arrowEdge: .bottom) {
            self.controllerTogglePopover
        }
    }
    
    private var controllerTogglePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Press Controller Shortcut")
                .font(.headline)
            
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
    
    private var keyboardRecordingPresentedBinding: Binding<Bool> {
        Binding(
            get: { self.isRecordingKeyboardHotkey },
            set: { [self] isPresented in
                if !isPresented {
                    endKeyboardHotkeyRecording()
                }
            }
        )
    }
    
    private var controllerToggleRecordingPresentedBinding: Binding<Bool> {
        Binding(
            get: { self.isRecordingControllerHotkey },
            set: { [self] isPresented in
                if !isPresented {
                    endControllerToggleRecording()
                }
            }
        )
    }
    
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
        }
    }
    
    // MARK: - UI Structs
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
    
    struct ControllerGlyphBadge: View {
        let assetName: String
        let fallbackText: String
        var size: CGFloat = 20
        
        var body: some View {
            let finalName = assetName.isEmpty ? "questionmark.circle.fill" : assetName
            let hasAsset = NSImage(named: finalName) != nil
            
            ZStack {
                if hasAsset {
                    Image(finalName)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .colorMultiply(Color.primary)
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
    
    @ViewBuilder
    func ControllerChordView(
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
    
    @ViewBuilder
    func StickDeadzoneVisualizer(
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
        
        ZStack {
            // Outer circle (joystick range)
            Circle()
                .stroke(Color.primary.opacity(0.3), lineWidth: 2)
                .frame(width: size, height: size)
            // Deadzone circle
            Circle()
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                .frame(width: size * deadzoneRadius, height: size * deadzoneRadius)
            // Stick dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 14, height: 14)
                .offset(x: stick.dx * (size/2 - 7), y: -stick.dy * (size/2 - 7))
                .shadow(radius: 2)
        }
        .onChange(of: stickPosition) {
            // Haptic feedback when crossing deadzone boundary
            let distance = sqrt(stickPosition.dx * stickPosition.dx + stickPosition.dy * stickPosition.dy)
            if (distance < deadzoneRadius && distance > deadzoneRadius - 0.05) ||
                (distance > deadzoneRadius && distance < deadzoneRadius + 0.05) {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
        .frame(width: size, height: size)
    }
    
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
        onRestartOnboarding: {}
    )
    
    SettingsView(viewModel: vm)
}

