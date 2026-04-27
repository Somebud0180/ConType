import AppKit
import SwiftUI
import Combine
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    private var settings: AppSettings { viewModel.settings }
    private var joystick: JoystickInputModel { viewModel.joystick }
    
    // Remove old reset state
    //@State var isResettingHotkeys: Bool = false
    //@State var isResettingDefaults: Bool = false
    
    // New state for confirmation dialogs
    @State private var showResetHotkeysDialog = false
    @State private var showResetDefaultsDialog = false
    
    // Intermediate state for keyboard movement style picker
    @State private var keyboardMovementStyleSelection: KeyboardMovementMode = .limited
    
    var body: some View {
        NavigationStack {
            TabView {
                Tab("General", systemImage: "gearshape") {
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
                                Button("Reset Hotkeys", role: .destructive) {
                                    showResetHotkeysDialog = true
                                }
                                Button("Reset Defaults", role: .destructive) {
                                    showResetDefaultsDialog = true
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
                            
                            Toggle("Shift hotkey cycles to Caps Lock", isOn: Binding(
                                get: { viewModel.settings.shiftShortcutCyclesToCapsLock },
                                set: { viewModel.settings.shiftShortcutCyclesToCapsLock = $0 }
                            ))
                            Toggle("Dismiss with guide button", isOn: Binding(
                                get: { viewModel.settings.dismissWithGuideButton },
                                set: { viewModel.settings.dismissWithGuideButton = $0 }
                            ))
                            
                            VStack(alignment: .leading) {
                                Picker("Keyboard movement style", selection: Binding(
                                    get: { viewModel.settings.keyboardMovementStyle },
                                    set: { viewModel.settings.keyboardMovementStyle = $0 }
                                )) {
                                    Text("4 Directional").tag(KeyboardMovementMode.limited)
                                    Text("8 Directional").tag(KeyboardMovementMode.full)
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
                    }
                    .formStyle(.grouped)
                }
                
                Tab("Keyboard", systemImage: "keyboard") {
                    Form {
                        Section("Keyboard Layout") {
                            Picker("Keyboard Layout", selection: Binding(
                                get: { viewModel.settings.keyboardLayout },
                                set: { viewModel.settings.keyboardLayout = $0 }
                            )) {
                                ForEach(KeyboardLayout.all) { layout in
                                    Text(layout.name).tag(layout)
                                }
                            }
                            
                            
                            KeyboardOverlayView(
                                settings: settings,
                                viewModel: KeyboardOverlayViewModel(settings: settings),
                                onKeyPressed: { _, _ in }
                            )
                            .frame(width: 500, height: 220)
                            .disabled(true)
                        }
                        
                        Section("Keyboard Actions") {
                            ForEach(ControllerActionBinding.keyboardActions) { action in
                                LabeledContent(action.title) {
                                    viewModel.controllerActionPickerButton(for: action)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                
                Tab("Mouse", systemImage: "computermouse") {
                    Form {
                        Section("Mouse Configuration") {
                            viewModel.mouseConfig
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
                }
            }
            .tabViewStyle(.tabBarOnly)
            .onAppear {
                keyboardMovementStyleSelection = viewModel.keyboardMovementStyle
            }
            .onDisappear {
                viewModel.endKeyboardHotkeyRecording()
                viewModel.endControllerToggleRecording()
                viewModel.endControllerActionPicker()
            }
            .frame(width: 560, height: 520)
            // Confirmation dialogs for reset actions
            .confirmationDialog("Reset Hotkeys?", isPresented: $showResetHotkeysDialog, titleVisibility: .visible) {
                Button("Reset Hotkeys", role: .destructive) {
                    // Reset hotkeys to default
                    settings.keyboardHotkey = viewModel.defaultKeyboardShortcut
                    settings.controllerToggleBinding = .default
                    settings.controllerActionBindings = .default
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset your keyboard and controller shortcuts and hotkeys to their default values. This action cannot be undone.")
            }
            .confirmationDialog("Reset All Settings?", isPresented: $showResetDefaultsDialog, titleVisibility: .visible) {
                Button("Reset Defaults", role: .destructive) {
                    viewModel.resetDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all your settings (except \"Open app on startup\") to their default values. This action cannot be undone.")
            }
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
