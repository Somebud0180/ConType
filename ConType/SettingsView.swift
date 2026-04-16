import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onRequestControllerBindingCapture: (@escaping (ControllerToggleBinding) -> Void) -> Void
    let onRequestControllerActionButtonCapture: (@escaping (ControllerAssignableButton) -> Void) -> Void
    let onCancelControllerCapture: () -> Void
    let onRestartOnboarding: () -> Void

    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted()
    @State private var keyboardKeyDownMonitor: Any?
    @State private var keyboardFlagsMonitor: Any?
    @State private var isRecordingKeyboardHotkey = false
    @State private var keyboardValidationMessage: String?
    @State private var keyboardPreviewShortcut: KeyboardHotkeyManager.Shortcut?
    @State private var keyboardPressedModifiers: NSEvent.ModifierFlags = []

    @State private var isRecordingControllerHotkey = false
    @State private var activeControllerActionPicker: ControllerActionBinding?
    @State private var stickMovementStyle = JoystickMovementMode.limited

    private let waitingKeyboardText = "Waiting for keyboard input..."
    private let waitingControllerText = "Waiting for controller input..."
    private let defaultKeyboardShortcut = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])

    var body: some View {
        Form {
            Section("Your Controller") {
                if let detectedController = settings.detectedController {
                    let guideButtons = displayedGuideButtons(for: detectedController)

                    HStack {
                        Text("Detected Controller:")
                        Spacer()
                        Text(detectedController.name)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Your controller's guide ")
                        Image(systemName: "gamecontroller.circle.fill")
                            .foregroundStyle(.primary)
                        Text(" \(guideButtons.count == 1 ? "button" : "buttons"):")

                        Spacer()

                        HStack(spacing: 6) {
                            ForEach(Array(guideButtons.enumerated()), id: \.offset) { _, guideButton in
                                guideButtonGlyph(guideButton)
                            }
                        }
                    }
                } else {
                    Text("No controller detected")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("General") {
                LabeledContent("Keyboard Shortcut") {
                    keyboardShortcutButton
                }

                LabeledContent("Controller Shortcut") {
                        controllerToggleButton
                }

                if let keyboardValidationMessage {
                    Text(keyboardValidationMessage)
                        .foregroundStyle(.red)
                }
                
                Toggle("Shift hotkey cycles to Caps Lock", isOn: $settings.shiftShortcutCyclesToCapsLock)
                Toggle("Dismiss with guide button", isOn: $settings.dismissWithGuideButton)
                Toggle("Open app on startup", isOn: $settings.openAppOnStartup)
                
                VStack(alignment: .leading) {
                    Picker("Keyboard stick movement style", selection: $stickMovementStyle) {
                        Text("4 Directional").tag(JoystickMovementMode.limited)
                        Text("8 Directional").tag(JoystickMovementMode.full)
                    }
                    .onSubmit {
                        settings.stickMovementStyle = stickMovementStyle
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    
                    Text(movementDecription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut)
                }
            }

            Section("Controller Hotkeys") {
                ForEach(ControllerActionBinding.allCases) { action in
                    LabeledContent(action.title) {
                        controllerActionPickerButton(for: action)
                    }
                }

                HStack {
                    Button("Reset Hotkeys") {
                        settings.keyboardHotkey = defaultKeyboardShortcut
                        settings.controllerToggleBinding = .default
                        settings.controllerActionBindings = .default
                    }

                    Button("Reset Defaults") {
                        settings.keyboardHotkey = defaultKeyboardShortcut
                        settings.controllerToggleBinding = .default
                        settings.controllerActionBindings = .default
                        settings.shiftShortcutCyclesToCapsLock = true
                    }
                }
            }

            Section("Others") {
                HStack {
                    Text("Accessibility Permissions: ")
                    Spacer()
                    Text(isAccessibilityTrusted ? "Granted" : "Not Granted")
                        .foregroundStyle(isAccessibilityTrusted ? .green : .red)
                }
                HStack {
                    Button("Restart Onboarding") {
                        onRestartOnboarding()
                    }
                }
            }
        }
        .onDisappear {
            endKeyboardHotkeyRecording()
            endControllerToggleRecording()
            endControllerActionPicker()
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }
    
    private var movementDecription: String {
        if $settings.stickMovementStyle.wrappedValue == JoystickMovementMode.limited {
            return "In this style, the joystick navigates the keyboard like a d-pad."
        } else if $settings.stickMovementStyle.wrappedValue == JoystickMovementMode.full {
            return "In this style, the joystick nvaigates the keyboard more freely, with diagonal movements."
        }
        
        return "This style doesn't exist"
    }

    private var keyboardShortcutButton: some View {
        Button {
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
            keyboardShortcutPopover
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

    private var controllerToggleButton: some View {
        Button {
            beginControllerToggleRecording()
        } label: {
            HStack(spacing: 8) {
                guideGlyph(size: 26)
                Text("+")
                    .foregroundStyle(.secondary)
                buttonGlyph(settings.controllerToggleBinding.button, size: 26)
            }
            .frame(width: 230, alignment: .leading)
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: controllerToggleRecordingPresentedBinding, arrowEdge: .bottom) {
            controllerTogglePopover
        }
    }

    private var controllerTogglePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Press Controller Shortcut")
                .font(.headline)

            RecordingDisplayContainer {
                controllerChordView(
                    guidePressed: settings.controllerCaptureState.isGuidePressed,
                    buttons: orderedButtons(from: settings.controllerCaptureState.pressedButtons),
                    waitingText: waitingControllerText
                )
            }

            Divider()

            Text("Example")
                .font(.subheadline.weight(.semibold))

            controllerChordView(
                guidePressed: true,
                buttons: [.west],
                waitingText: waitingControllerText
            )
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    endControllerToggleRecording()
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func controllerActionPickerButton(for action: ControllerActionBinding) -> some View {
        let selectedButton = settings.controllerActionBindings.button(for: action)

        return Button {
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
        .popover(isPresented: controllerActionPickerPresentedBinding(for: action), arrowEdge: .bottom) {
            controllerActionPickerPopover(for: action)
        }
    }

    private func controllerActionPickerPopover(for action: ControllerActionBinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Controller Button")
                .font(.headline)

            Text("Press a controller button or click an option below.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(ControllerAssignableButton.allCases) { button in
                let isSelected = settings.controllerActionBindings.button(for: action) == button

                Button {
                    setControllerActionButton(button, for: action)
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
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    endControllerActionPicker()
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var keyboardRecordingPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                isRecordingKeyboardHotkey
            },
            set: { isPresented in
                if !isPresented {
                    endKeyboardHotkeyRecording()
                }
            }
        )
    }

    private var controllerToggleRecordingPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                isRecordingControllerHotkey
            },
            set: { isPresented in
                if !isPresented {
                    endControllerToggleRecording()
                }
            }
        )
    }

    private var keyboardLiveRecordingText: String {
        if let keyboardPreviewShortcut {
            return keyboardPreviewShortcut.displayText
        }

        let activeModifiers = keyboardPressedModifiers.intersection([.control, .option, .command, .shift])
        if !activeModifiers.isEmpty {
            return modifierDisplayText(from: activeModifiers)
        }

        return waitingKeyboardText
    }

    private func modifierDisplayText(from modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        return parts.joined(separator: " + ")
    }

    private func orderedButtons(from pressedButtons: Set<ControllerAssignableButton>) -> [ControllerAssignableButton] {
        ControllerAssignableButton.allCases.filter { pressedButtons.contains($0) }
    }

    private func displayedGuideButtons(for detectedController: DetectedController) -> [ControllerGuideButton] {
        if detectedController.guideButtons.isEmpty {
            return [.menu]
        }
        return detectedController.guideButtons
    }

    @ViewBuilder
    private func controllerChordView(
        guidePressed: Bool,
        buttons: [ControllerAssignableButton],
        waitingText: String
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
                        guideGlyph()
                        Text("Guide")
                    }

                    if !buttons.isEmpty {
                        Text("+")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(Array(buttons.enumerated()), id: \.element) { index, button in
                    if index > 0 {
                        Text("+")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        buttonGlyph(button)
                        Text(button.displayTitle(for: settings.controllerGlyphStyle))
                    }
                }
            }
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func guideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            systemAsset: true,
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size
        )
    }

    @ViewBuilder
    private func guideButtonGlyph(_ button: ControllerGuideButton, size: CGFloat = 20) -> some View {
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

    private func beginKeyboardHotkeyRecording() {
        endKeyboardHotkeyRecording()
        endControllerToggleRecording()
        endControllerActionPicker()

        isRecordingKeyboardHotkey = true
        keyboardValidationMessage = nil
        keyboardPreviewShortcut = nil
        keyboardPressedModifiers = []

        keyboardFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            guard isRecordingKeyboardHotkey else { return event }

            keyboardPressedModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            keyboardPreviewShortcut = nil
            keyboardValidationMessage = nil
            return nil
        }

        keyboardKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingKeyboardHotkey else { return event }

            if event.keyCode == 53 {
                endKeyboardHotkeyRecording()
                return nil
            }

            keyboardPressedModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            guard let shortcut = KeyboardHotkeyManager.shortcut(from: event) else {
                return nil
            }

            keyboardPreviewShortcut = shortcut

            guard KeyboardHotkeyManager.isValidShortcut(shortcut) else {
                keyboardValidationMessage = "Use at least one modifier key (Command/Option/Control/Shift)."
                return nil
            }

            keyboardValidationMessage = nil
            settings.keyboardHotkey = shortcut
            endKeyboardHotkeyRecording()
            return nil
        }
    }

    private func endKeyboardHotkeyRecording() {
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

    private func beginControllerToggleRecording() {
        endControllerToggleRecording()
        endKeyboardHotkeyRecording()
        endControllerActionPicker()

        isRecordingControllerHotkey = true

        onRequestControllerBindingCapture { binding in
            DispatchQueue.main.async {
                settings.controllerToggleBinding = binding
                endControllerToggleRecording(cancelCapture: false)
            }
        }
    }

    private func endControllerToggleRecording(cancelCapture: Bool = true) {
        let wasRecording = isRecordingControllerHotkey
        isRecordingControllerHotkey = false

        if cancelCapture && wasRecording {
            onCancelControllerCapture()
        }
    }

    private func controllerActionPickerPresentedBinding(for action: ControllerActionBinding) -> Binding<Bool> {
        Binding(
            get: {
                activeControllerActionPicker == action
            },
            set: { isPresented in
                if isPresented {
                    beginControllerActionPicker(for: action)
                } else if activeControllerActionPicker == action {
                    endControllerActionPicker()
                }
            }
        )
    }

    private func beginControllerActionPicker(for action: ControllerActionBinding) {
        endControllerToggleRecording()
        endKeyboardHotkeyRecording()

        activeControllerActionPicker = action
        armControllerActionButtonCapture(for: action)
    }

    private func armControllerActionButtonCapture(for action: ControllerActionBinding) {
        guard activeControllerActionPicker == action else { return }

        onRequestControllerActionButtonCapture { button in
            DispatchQueue.main.async {
                guard activeControllerActionPicker == action else { return }
                setControllerActionButton(button, for: action)
                armControllerActionButtonCapture(for: action)
            }
        }
    }

    private func endControllerActionPicker() {
        let wasActive = activeControllerActionPicker != nil
        activeControllerActionPicker = nil

        if wasActive {
            onCancelControllerCapture()
        }
    }

    private func setControllerActionButton(_ button: ControllerAssignableButton, for action: ControllerActionBinding) {
        var updated = settings.controllerActionBindings
        updated.setButton(button, for: action)
        settings.controllerActionBindings = updated
    }
}

private struct RecordingDisplayContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            content
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
}

private struct ControllerGlyphBadge: View {
    var systemAsset: Bool = false
    let assetName: String
    let fallbackText: String
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            if systemAsset {
                Image(systemName: assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(max(2, size * 0.1))
            } else {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .colorMultiply(Color.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(fallbackText))
    }
}

#Preview {
    SettingsView(
        settings: AppSettings(),
        onRequestControllerBindingCapture: { _ in },
        onRequestControllerActionButtonCapture: { _ in },
        onCancelControllerCapture: {},
        onRestartOnboarding: {}
    )
}
