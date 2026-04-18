import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    private var settings: AppSettings { viewModel.settings }
    private var joystick: JoystickInputModel { viewModel.joystick }
    
    var body: some View {
        NavigationStack {
            TabView {
                Tab("Main", systemImage: "gearshape") {
                    Form {
                        Section("Your Controller") {
                            if let detectedController = settings.detectedController {
                                let guideButtons = viewModel.displayedGuideButtons(for: detectedController)
                                
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
                                            viewModel.controllerGuideGlyphs(guideButton)
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
                                viewModel.keyboardShortcutButton
                            }
                            
                            LabeledContent("Controller Shortcut") {
                                viewModel.controllerToggleButton
                            }
                            
                            if let keyboardValidationMessage = viewModel.keyboardValidationMessage {
                                Text(keyboardValidationMessage)
                                    .foregroundStyle(.red)
                            }
                            
                            Toggle("Open app on startup", isOn: Binding(
                                get: { viewModel.settings.openAppOnStartup },
                                set: { viewModel.settings.openAppOnStartup = $0 }
                            ))
                        }
                        
                        Section("Others") {
                            HStack {
                                Text("Accessibility Permissions: ")
                                Spacer()
                                Text(viewModel.isAccessibilityTrusted ? "Granted" : "Not Granted")
                                    .foregroundStyle(viewModel.isAccessibilityTrusted ? .green : .red)
                            }
                            HStack {
                                Button("Restart Onboarding") {
                                    viewModel.restartOnboarding()
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                
                Tab("Input", systemImage: "gamecontroller") {
                    Form {
                        Section("Controller Configuration") {
                            HStack {
                                SettingsViewModel.ControllerGlyphBadge(
                                    assetName: "LS",
                                    fallbackText: "LS",
                                    size: 24
                                )
                                
                                Picker("Left Stick", selection: Binding(
                                    get: { viewModel.settings.leftStickInputType },
                                    set: { viewModel.settings.leftStickInputType = $0 }
                                )) {
                                    ForEach(AxisInputType.allCases) { type in
                                        Text(type.title).tag(type)
                                    }
                                }
                            }
                            
                            HStack {
                                SettingsViewModel.ControllerGlyphBadge(
                                    assetName: "RS",
                                    fallbackText: "RS",
                                    size: 24
                                )
                                
                                Picker("Right Stick", selection: Binding(
                                    get: { viewModel.settings.rightStickInputType },
                                    set: { viewModel.settings.rightStickInputType = $0 }
                                )) {
                                    ForEach(AxisInputType.allCases) { type in
                                        Text(type.title).tag(type)
                                    }
                                }
                            }
                            
                            HStack {
                                SettingsViewModel.ControllerGlyphBadge(
                                    assetName: "DPad",
                                    fallbackText: "DPad",
                                    size: 24
                                )
                                
                                Picker("D-pad", selection: Binding(
                                    get: { viewModel.settings.padInputType },
                                    set: { viewModel.settings.padInputType = $0 }
                                )) {
                                    ForEach(AxisInputType.allCases) { type in
                                        Text(type.title).tag(type)
                                    }
                                }
                            }
                            
                            NavigationLink(destination: HotkeySettingsView(viewModel: viewModel)) {
                                Text("Hotkey Actions")
                            }
                            
                            Toggle("Shift hotkey cycles to Caps Lock", isOn: Binding(
                                get: { viewModel.settings.shiftShortcutCyclesToCapsLock },
                                set: { viewModel.settings.shiftShortcutCyclesToCapsLock = $0 }
                            ))
                            Toggle("Dismiss with guide button", isOn: Binding(
                                get: { viewModel.settings.dismissWithGuideButton },
                                set: { viewModel.settings.dismissWithGuideButton = $0 }
                            ))
                            
                            VStack(alignment: .leading) {
                                Picker("Keyboard movement style", selection: $viewModel.keyboardMovementStyle) {
                                    Text("4 Directional").tag(KeyboardMovementMode.limited)
                                    Text("8 Directional").tag(KeyboardMovementMode.full)
                                }
                                .onSubmit {
                                    settings.keyboardMovementStyle = viewModel.keyboardMovementStyle
                                }
                                .pickerStyle(.segmented)
                                .listRowSeparator(.hidden)
                                
                                Text(viewModel.movementDescription)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .animation(.easeInOut)
                            }
                        }
                        
                        Section("Joystick Deadzone") {
                            viewModel.stickDeadzoneConfig
                        }
                        
                        Section("Mouse Configuration") {
                            viewModel.mouseConfig
                        }
                        
                        Section("Others") {
                            
                            HStack {
                                Button("Reset Hotkeys") {
                                    settings.keyboardHotkey = viewModel.defaultKeyboardShortcut
                                    settings.controllerToggleBinding = .default
                                    settings.controllerActionBindings = .default
                                }
                                
                                Button("Reset Defaults") {
                                    settings.keyboardHotkey = viewModel.defaultKeyboardShortcut
                                    settings.controllerToggleBinding = .default
                                    settings.controllerActionBindings = .default
                                    settings.shiftShortcutCyclesToCapsLock = true
                                    settings.dismissWithGuideButton = true
                                    settings.keyboardMovementStyle = .limited
                                    settings.leftStickDeadzone = 0.2
                                    settings.rightStickDeadzone = 0.2
                                    settings.mouseSensitivity = 300
                                    settings.mouseSmoothing = 0.5
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .onDisappear {
                viewModel.endKeyboardHotkeyRecording()
                viewModel.endControllerToggleRecording()
                viewModel.endControllerActionPicker()
            }
            .frame(width: 560, height: 520)
        }
    }
}

struct HotkeySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard Actions") {
                    ForEach(ControllerActionBinding.keyboardActions) { action in
                        LabeledContent(action.title) {
                            viewModel.controllerActionPickerButton(for: action)
                        }
                    }
                }
                Section("Mouse Actions") {
                    ForEach(ControllerActionBinding.mouseActions) { action in
                        LabeledContent(action.title) {
                            viewModel.controllerActionPickerButton(for: action)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Hotkey Actions")
        }
        .frame(width: 560, height: 520)
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
