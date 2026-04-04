import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onRequestControllerBindingCapture: (@escaping (ControllerToggleBinding) -> Void) -> Void

    @State private var keyboardRecordMonitor: Any?
    @State private var isRecordingKeyboardHotkey = false
    @State private var keyboardValidationMessage: String?
    @State private var isRecordingControllerHotkey = false

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Keyboard") {
                    Button(isRecordingKeyboardHotkey ? "Press Shortcut..." : "Record Shortcut") {
                        beginKeyboardHotkeyRecording()
                    }
                    .frame(width: 190, alignment: .leading)
                }

                LabeledContent("Controller") {
                    Button(isRecordingControllerHotkey ? "Press Guide + Face..." : "Record Toggle") {
                        isRecordingControllerHotkey = true
                        onRequestControllerBindingCapture { binding in
                            DispatchQueue.main.async {
                                settings.controllerToggleBinding = binding
                                isRecordingControllerHotkey = false
                            }
                        }
                    }
                    .frame(width: 190, alignment: .leading)
                }

                Toggle("Invert A/B Face Buttons", isOn: $settings.invertControllerFaceButtons)

                HStack {
                    Button("Reset Keyboard") {
                        settings.keyboardHotkey = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])
                    }
                    Button("Reset Defaults") {
                        settings.keyboardHotkey = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])
                        settings.controllerToggleBinding = .default
                        settings.invertControllerFaceButtons = false
                    }
                }

                if let keyboardValidationMessage {
                    Text(keyboardValidationMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Permissions") {
                Text("Input Monitoring and Accessibility are required for global typing and hotkeys.")
                Text("Debug builds run unsandboxed for local input emulation testing.")
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            endKeyboardHotkeyRecording()
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 340)
    }

    private func beginKeyboardHotkeyRecording() {
        endKeyboardHotkeyRecording()
        isRecordingKeyboardHotkey = true
        keyboardValidationMessage = nil

        keyboardRecordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingKeyboardHotkey else { return event }

            if event.keyCode == 53 {
                endKeyboardHotkeyRecording()
                return nil
            }

            guard let shortcut = KeyboardHotkeyManager.shortcut(from: event) else {
                endKeyboardHotkeyRecording()
                return nil
            }

            guard KeyboardHotkeyManager.isValidShortcut(shortcut) else {
                keyboardValidationMessage = "Use at least one modifier key (Cmd/Option/Control/Shift)."
                endKeyboardHotkeyRecording()
                return nil
            }

            settings.keyboardHotkey = shortcut
            endKeyboardHotkeyRecording()
            return nil
        }
    }

    private func endKeyboardHotkeyRecording() {
        isRecordingKeyboardHotkey = false
        if let keyboardRecordMonitor {
            NSEvent.removeMonitor(keyboardRecordMonitor)
            self.keyboardRecordMonitor = nil
        }
    }
}
