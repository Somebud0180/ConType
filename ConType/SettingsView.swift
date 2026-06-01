//
//  OnboardingWindowController.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// A view struct holding the settings view of the app, containing multiple tabs for different categories of settings and configurations. It observes the SettingsViewModel for data and actions, and provides UI for changing app settings, configuring controller bindings, and viewing app information.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    private var settings: AppSettings { viewModel.settings }
    private var joystick: JoystickInputModel { viewModel.joystick }
    
    let version: String =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
    as? String ?? "1.0"
    let build: String =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    ?? "1"
    
    // New state for confirmation dialogs
    @State private var showResetHotkeysDialog = false
    @State private var showResetDefaultsDialog = false
    
    // Intermediate state for keyboard movement style picker
    @State private var keyboardMovementStyleSelection: KeyboardMovementMode =
        .limited
    
    var body: some View {
        NavigationStack {
            TabView {
                Tab("General", systemImage: "gearshape") {
                    Form {
                        Section("Your Controller") {
                            if let detectedController = settings
                                .detectedController
                            {
                                let guideButtons =
                                viewModel.displayedGuideButtons(
                                    for: detectedController
                                )
                                
                                HStack {
                                    Text("Detected Controller:")
                                    Spacer()
                                    Text(detectedController.name)
                                        .multilineTextAlignment(.trailing)
                                }
                                
                                HStack {
                                    Text("Your controller's guide ")
                                    Image(
                                        systemName: "gamecontroller.circle.fill"
                                    )
                                    .foregroundStyle(.primary)
                                    Text(
                                        " \(guideButtons.count == 1 ? "button" : "buttons"):"
                                    )
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 6) {
                                        ForEach(
                                            Array(guideButtons.enumerated()),
                                            id: \.offset
                                        ) { _, guideButton in
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
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(ControllerToggleBinding.allCases) { toggle in
                                    LabeledContent(toggle.title) {
                                        viewModel.controllerTogglePickerButton(
                                            for: toggle
                                        )
                                    }
                                    
                                    if toggle != ControllerToggleBinding.allCases.last {
                                        Divider()
                                    }
                                }
                            }
                            
                            Toggle(
                                "Open app on startup",
                                isOn: Binding(
                                    get: { viewModel.settings.openAppOnStartup },
                                    set: { viewModel.settings.openAppOnStartup = $0 }
                                )
                            )
                            
                            Toggle(
                                "IOHID",
                                isOn: Binding(
                                    get: { viewModel.settings.controllerInputBackendMode == .hybridIOHID },
                                    set: { viewModel.settings.controllerInputBackendMode = $0 ? .hybridIOHID : .gameController })
                                )
                        }
                        
                        Section("Overlay") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Overlay Sizing")
                                    .font(.headline)
                                
                                HStack {
                                    Text("Keyboard Size")
                                    Spacer()
                                    Menu {
                                        ForEach(WindowSize.selectableCases) { size in
                                            Button(size.name) {
                                                viewModel.settings.keyboardWindowSize = size
                                                viewModel.onUpdateWindowSize()
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(viewModel.settings.keyboardWindowSize.name)
                                        }
                                        .frame(width: 160, alignment: .leading)
                                    }
                                }
                                
                                if viewModel.settings.keyboardWindowSize == .custom {
                                    Text("Custom size was set by manually resizing the keyboard window.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                
                                ForEach(ControllerActionBinding.overlayActions) { action in
                                    Divider()
                                    LabeledContent(action.title) {
                                        viewModel.controllerActionPickerButton(
                                            for: action
                                        )
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Overlay Controls")
                                    .font(.headline)
                                
                                Toggle(
                                    "Dismiss overlay with guide button",
                                    isOn: Binding(
                                        get: {
                                            viewModel.settings
                                                .dismissWithGuideButton
                                        },
                                        set: {
                                            viewModel.settings
                                                .dismissWithGuideButton = $0
                                        }
                                    )
                                )
                                
                                Divider()
                                
                                Toggle(
                                    "Show guide bar",
                                    isOn: Binding(
                                        get: { viewModel.settings.showGuideBar },
                                        set: { viewModel.settings.showGuideBar = $0 }
                                    )
                                )
                                
                                Divider()
                                
                                Toggle(
                                    "Enables mouse controls in keyboard overlay",
                                    isOn: Binding(
                                        get: { viewModel.settings.enableMouseInKeyboard },
                                        set: { viewModel.settings.enableMouseInKeyboard = $0 }
                                    )
                                )
                                
                                Divider()
                                
                                Toggle(
                                    "Prioritize mouse controls while in keyboard overlay",
                                    isOn: Binding(
                                        get: { viewModel.settings.prioritizeMouseOverKeyboard },
                                        set: { viewModel.settings.prioritizeMouseOverKeyboard = $0 }
                                    )
                                )
                                .disabled(!viewModel.settings.enableMouseInKeyboard)
                            }
                        }
                        
                        Section(
                            header: Text("Others"),
                            footer:
                                VStack(spacing: 2) {
                                    Link(
                                        destination: URL(
                                            string: "https://hackclub.com/"
                                        )!
                                    ) {
                                        HStack(spacing: 0) {
                                            Text("Made with ")
                                            Image(systemName: "heart.fill")
                                            Text(" Hack Club")
                                        }
                                    }
                                    Link(
                                        "Source Code on GitHub",
                                        destination: URL(
                                            string:
                                                "https://github.com/Somebud0180/ConType"
                                        )!
                                    )
                                    .underline()
                                    HStack {
                                        Text("Version \(version) (\(build))")
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        ) {
                            HStack {
                                Text("Accessibility Permissions: ")
                                Spacer()
                                Text(
                                    viewModel.isAccessibilityTrusted
                                    ? "Granted" : "Not Granted"
                                )
                                .foregroundStyle(
                                    viewModel.isAccessibilityTrusted
                                    ? .green : .red
                                )
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
                
                Tab("Keyboard", systemImage: "keyboard") {
                    Form {
                        Picker(
                            "Keyboard Layout",
                            selection: Binding(
                                get: { viewModel.settings.keyboardLayout },
                                set: {
                                    viewModel.settings.keyboardLayout = $0
                                }
                            )
                        ) {
                            ForEach(KeyboardLayout.all) { layout in
                                Text(layout.name).tag(layout)
                            }
                        }
                        
                        KeyboardOverlayView(
                            viewModel: KeyboardOverlayViewModel(
                                settings: settings
                            ),
                            onKeyPressed: { _, _ in }
                        )
                        .frame(width: 500, height: 210)
                        .disabled(true)
                        
                        Section("Controller Configuration") {
                            HStack {
                                ControllerGlyphBadge(
                                    assetName: "LS",
                                    fallbackText: "LS",
                                    size: 24
                                )
                                Text("Left Stick")
                                Spacer()
                                viewModel.axisInputPickerButton(for: .leftStick, forKeyboard: true)
                            }
                            
                            HStack {
                                ControllerGlyphBadge(
                                    assetName: "RS",
                                    fallbackText: "RS",
                                    size: 24
                                )
                                Text("Right Stick")
                                Spacer()
                                viewModel.axisInputPickerButton(for: .rightStick, forKeyboard: true)
                            }
                            
                            HStack {
                                ControllerGlyphBadge(
                                    assetName: "DPad",
                                    fallbackText: "DPad",
                                    size: 24
                                )
                                Text("D-pad")
                                Spacer()
                                viewModel.axisInputPickerButton(for: .pad, forKeyboard: true)
                            }
                            
                            Toggle(
                                "Shift hotkey cycles to Caps Lock",
                                isOn: Binding(
                                    get: {
                                        viewModel.settings
                                            .shiftShortcutCyclesToCapsLock
                                    },
                                    set: {
                                        viewModel.settings
                                            .shiftShortcutCyclesToCapsLock = $0
                                    }
                                )
                            )
                            
                            VStack(alignment: .leading) {
                                Picker(
                                    "Keyboard movement style",
                                    selection: Binding(
                                        get: {
                                            viewModel.settings
                                                .keyboardMovementStyle
                                        },
                                        set: {
                                            viewModel.settings
                                                .keyboardMovementStyle = $0
                                        }
                                    )
                                ) {
                                    Text("4 Directional").tag(
                                        KeyboardMovementMode.limited
                                    )
                                    Text("8 Directional").tag(
                                        KeyboardMovementMode.full
                                    )
                                }
                                .pickerStyle(.segmented)
                                .listRowSeparator(.hidden)
                                
                                Text(viewModel.movementDescription)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .animation(.easeInOut)
                            }
                        }
                        
                        Section("Keyboard Actions") {
                            ForEach(ControllerActionBinding.keyboardActions) {
                                action in
                                LabeledContent(action.title) {
                                    viewModel.controllerActionPickerButton(
                                        for: action
                                    )
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                
                Tab("Mouse", systemImage: "computermouse") {
                    Form {
                        Section("Controller Configuration") {
                            HStack {
                                ControllerGlyphBadge(
                                    assetName: "LS",
                                    fallbackText: "LS",
                                    size: 24
                                )
                                Text("Left Stick")
                                Spacer()
                                viewModel.axisInputPickerButton(for: .leftStick, forKeyboard: false)
                            }
                            
                            HStack {
                                ControllerGlyphBadge(
                                    assetName: "RS",
                                    fallbackText: "RS",
                                    size: 24
                                )
                                Text("Right Stick")
                                Spacer()
                                viewModel.axisInputPickerButton(for: .rightStick, forKeyboard: false)
                            }
                            
                            HStack {
                                ControllerGlyphBadge(
                                    assetName: "DPad",
                                    fallbackText: "DPad",
                                    size: 24
                                )
                                Text("D-pad")
                                Spacer()
                                viewModel.axisInputPickerButton(for: .pad, forKeyboard: false)
                            }
                        }
                        
                        Section("Mouse Configuration") {
                            viewModel.mouseConfig
                        }
                        
                        Section("Scroll Configuration") {
                            viewModel.scrollConfig
                        }
                        
                        Section("Mouse Actions") {
                            ForEach(ControllerActionBinding.mouseActions) {
                                action in
                                LabeledContent(action.title) {
                                    viewModel.controllerActionPickerButton(
                                        for: action
                                    )
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                
                Tab("Controller", systemImage: "gamecontroller") {
                    Form {
                        Section("General") {
                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings.enableHaptics },
                                    set: { viewModel.settings.enableHaptics = $0 }
                                    ),
                                label: {
                                    Text("Enable Controller Haptics")
                                })
                        }
                        
                        Section("Joystick Deadzone") {
                            viewModel.stickDeadzoneConfig
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
            .confirmationDialog(
                "Reset Hotkeys?",
                isPresented: $showResetHotkeysDialog,
                titleVisibility: .visible
            ) {
                Button("Reset Hotkeys", role: .destructive) {
                    // Reset hotkeys to default
                    settings.restoreDefaults(onlyHotkeys: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will reset your keyboard and controller shortcuts and hotkeys to their default values. This action cannot be undone."
                )
            }
            .confirmationDialog(
                "Reset All Settings?",
                isPresented: $showResetDefaultsDialog,
                titleVisibility: .visible
            ) {
                Button("Reset Defaults", role: .destructive) {
                    viewModel.resetDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will reset all your settings (except \"Open app on startup\") to their default values. This action cannot be undone."
                )
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
        onRestartOnboarding: {},
        onUpdateWindowSize: {},
        onTriggerHaptics: {}
    )
    
    SettingsView(viewModel: vm)
}
