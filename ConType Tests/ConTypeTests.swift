import AppKit
import Testing
@testable import ConType

@MainActor
struct AppSettingsLogicTests {
    @Test func shortcutDisplayTextFormatsModifiersAndSpecialKeys() async throws {
        try await TestSupport.withTemporarySettingsURL {
            #expect(Shortcut(key: "k", modifiers: [.command]).displayText == "Command + K")
            #expect(Shortcut(key: " ", modifiers: [.shift, .option]).displayText == "Option + Shift + Space")
            #expect(Shortcut(key: "\r", modifiers: [.control]).displayText == "Ctrl + Return")
        }
    }
    
    @Test func controllerGlyphStyleDetectionAndDisplayTitlesMatchKnownControllers() async throws {
        try await TestSupport.withTemporarySettingsURL {
            #expect(ControllerGlyphStyle.detect(vendorName: "Sony", productCategory: nil) == .playStation)
            #expect(ControllerGlyphStyle.detect(vendorName: nil, productCategory: "Nintendo Switch Pro Controller") == .nintendoSwitch)
            #expect(ControllerGlyphStyle.detect(vendorName: "Microsoft", productCategory: "Xbox Wireless Controller") == .generic)
            
            #expect(ControllerAssignableButton.south.displayTitle(for: .playStation) == "Cross Button")
            #expect(ControllerAssignableButton.west.glyphAssetName(for: .nintendoSwitch) == "X")
            #expect(ControllerAssignableButton.none.fallbackGlyphText == "nosign")
        }
    }
    
    @Test func windowSizeHelpersReturnExpectedPresetsAndDimensions() async throws {
        try await TestSupport.withTemporarySettingsURL {
            #expect(!WindowSize.small.isCustom)
            #expect(WindowSize.custom.isCustom)
            #expect(WindowSize.small.windowDimensions() == NSSize(width: 800, height: 300))
            #expect(WindowSize.preset(for: NSSize(width: 1001, height: 380)) == .medium)
            #expect(WindowSize.custom.largerPreset(using: NSSize(width: 1300, height: 450)) == .xLarge)
            #expect(WindowSize.custom.smallerPreset(using: NSSize(width: 1300, height: 450)) == .large)
            #expect(WindowSize.small.largerPreset() == .medium)
            #expect(WindowSize.xLarge.smallerPreset() == .large)
        }
    }
    
    @Test func controllerBindingsRoundTripThroughLookupAndMutation() async throws {
        try await TestSupport.withTemporarySettingsURL {
            var toggleBindings = ControllerToggleBindings.default
            toggleBindings.setBinding(.leftTrigger, for: .mouseToggle)
            #expect(toggleBindings.binding(for: .mouseToggle) == .leftTrigger)
            #expect(toggleBindings.shortcutText(for: .keyboardToggle, style: .generic) == "Guide + X Button")
            
            var actionBindings = ControllerActionBindings.default
            actionBindings.setButton(.north, for: .accept)
            #expect(actionBindings.button(for: .accept) == .north)
            #expect(actionBindings.button(for: .shrinkWindow) == .leftTrigger)
        }
    }
    
    @Test func restoreDefaultsPreservesLaunchPreferenceWhileResettingEverythingElse() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            settings.openAppOnStartup = true
            settings.keyboardHotkey = Shortcut(key: "x", modifiers: [.command, .shift])
            settings.keyboardMovementStyle = .full
            settings.leftStickDeadzone = 0.1
            settings.rightStickDeadzone = 0.9
            settings.mouseSensitivity = 777
            settings.scrollSpeed = 123
            settings.invertMouseX = true
            settings.invertScrollY = true
            settings.keyboardWindowSize = .xLarge
            settings.keyboardWindowPosition = NSPoint(x: 44, y: 55)
            settings.mouseWindowPosition = NSPoint(x: 66, y: 77)
            
            settings.restoreDefaults(onlyHotkeys: false)
            
            #expect(settings.openAppOnStartup)
            #expect(settings.keyboardHotkey == Shortcut(key: "k", modifiers: [.command]))
            #expect(settings.keyboardMovementStyle == .limited)
            #expect(settings.leftStickDeadzone == 0.4)
            #expect(settings.rightStickDeadzone == 0.4)
            #expect(settings.mouseSensitivity == 300.0)
            #expect(settings.scrollSpeed == 600.0)
            #expect(settings.invertMouseX == false)
            #expect(settings.invertScrollY == false)
            #expect(settings.keyboardWindowSize == .small)
            #expect(settings.keyboardWindowPosition == .zero)
            #expect(settings.mouseWindowPosition == .zero)
        }
    }
    
    @Test func restoreHotkeysLeavesPreferencesUntouched() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            settings.openAppOnStartup = true
            settings.keyboardHotkey = Shortcut(key: "x", modifiers: [.shift])
            settings.controllerToggleBindings.setBinding(.leftTrigger, for: .keyboardToggle)
            settings.keyboardMovementStyle = .full
            
            settings.restoreDefaults(onlyHotkeys: true)
            
            #expect(settings.openAppOnStartup)
            #expect(settings.keyboardHotkey == Shortcut(key: "k", modifiers: [.command]))
            #expect(settings.controllerToggleBindings == .default)
            #expect(settings.keyboardMovementStyle == .full)
        }
    }
    
    @Test func settingsSaveAndLoadRoundTripThroughTemporaryFile() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let initial = AppSettings()
            initial.keyboardHotkey = Shortcut(key: "m", modifiers: [.command, .option])
            initial.controllerToggleBindings.setBinding(.rightTrigger, for: .mouseToggle)
            initial.controllerActionBindings.setButton(.north, for: .capsLock)
            initial.enableMouseInKeyboard = false
            initial.keyboardLayout = .alignedQWERTY
            initial.keyboardWindowSize = .custom
            initial.keyboardCustomDimensions = NSSize(width: 1234, height: 432)
            initial.keyboardWindowPosition = NSPoint(x: 11, y: 22)
            initial.mouseWindowPosition = NSPoint(x: 33, y: 44)
            initial.save()
            
            let restored = AppSettings()
            #expect(restored.keyboardHotkey == Shortcut(key: "m", modifiers: [.command, .option]))
            #expect(restored.controllerToggleBindings.binding(for: .mouseToggle) == .rightTrigger)
            #expect(restored.controllerActionBindings.button(for: .capsLock) == .north)
            #expect(restored.enableMouseInKeyboard == false)
            #expect(restored.keyboardLayout == .alignedQWERTY)
            #expect(restored.keyboardWindowSize == .custom)
            #expect(restored.keyboardCustomDimensions == NSSize(width: 1234, height: 432))
            #expect(restored.keyboardWindowPosition == NSPoint(x: 11, y: 22))
            #expect(restored.mouseWindowPosition == NSPoint(x: 33, y: 44))
        }
    }
}

@MainActor
struct KeyboardOverlayViewModelLogicTests {
    @Test func movementWrapsOnDiscretePressAndStaysPutOnHoldRepeat() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let viewModel = KeyboardOverlayViewModel(settings: AppSettings())
            
            #expect(viewModel.move(.left, trigger: .press))
            #expect(viewModel.selectedRow == 0)
            #expect(viewModel.selectedColumn == viewModel.rows[0].count - 1)
            
            #expect(viewModel.move(.up, trigger: .press))
            #expect(viewModel.selectedRow == viewModel.rows.count - 1)
            #expect(viewModel.selectedColumn == viewModel.rows[viewModel.selectedRow].count - 1)
            
            let holdRepeatModel = KeyboardOverlayViewModel(settings: AppSettings())
            #expect(!holdRepeatModel.move(.left, trigger: .holdRepeat))
            #expect(holdRepeatModel.selectedRow == 0)
            #expect(holdRepeatModel.selectedColumn == 0)
            #expect(!holdRepeatModel.move(.up, trigger: .holdRepeat))
            #expect(holdRepeatModel.selectedRow == 0)
            #expect(holdRepeatModel.selectedColumn == 0)
        }
    }
    
    @Test func selectIgnoresOutOfBoundsIndices() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let viewModel = KeyboardOverlayViewModel(settings: AppSettings())
            
            viewModel.select(row: 2, column: 1)
            #expect(viewModel.selectedRow == 2)
            #expect(viewModel.selectedColumn == 1)
            
            viewModel.select(row: 999, column: 999)
            #expect(viewModel.selectedRow == 2)
            #expect(viewModel.selectedColumn == 1)
        }
    }
    
    @Test func activationEmitsExpectedFlagsAndClearsShiftForAlphanumericKeys() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let viewModel = KeyboardOverlayViewModel(settings: AppSettings())
            viewModel.select(row: 2, column: 1)
            viewModel.cycleShiftShortcut(cyclesToCapsLock: false)
            
            var emittedKey: VirtualKey?
            var emittedFlags: CGEventFlags = []
            viewModel.activateSelected { key, flags in
                emittedKey = key
                emittedFlags = flags
            }
            
            #expect(emittedKey?.baseLabel == "a")
            #expect(emittedFlags.contains(.maskShift))
            #expect(!viewModel.isModifierActive(.shift))
        }
    }
    
    @Test func modifierActivationTogglesStateAndShiftCyclingFollowsExpectedStates() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let viewModel = KeyboardOverlayViewModel(settings: AppSettings())
            viewModel.select(row: 3, column: 0)
            
            viewModel.activateSelected { _, _ in }
            #expect(viewModel.isModifierActive(.shift))
            
            viewModel.activateSelected { _, _ in }
            #expect(!viewModel.isModifierActive(.shift))
            
            viewModel.cycleShiftShortcut(cyclesToCapsLock: true)
            #expect(viewModel.isModifierActive(.shift))
            viewModel.cycleShiftShortcut(cyclesToCapsLock: true)
            #expect(viewModel.isModifierActive(.capsLock))
            viewModel.toggleCapsLockShortcut()
            #expect(!viewModel.isModifierActive(.capsLock))
        }
    }
    
    @Test func setKeyboardLayoutResetsSelectionAndModifierState() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let viewModel = KeyboardOverlayViewModel(settings: AppSettings())
            viewModel.select(row: 2, column: 1)
            viewModel.cycleShiftShortcut(cyclesToCapsLock: false)
            
            viewModel.setKeyboardLayout(.alignedQWERTY)
            
            #expect(viewModel.selectedRow == 0)
            #expect(viewModel.selectedColumn == 0)
            #expect(viewModel.activeModifierKeys.isEmpty)
            #expect(viewModel.keyRefs.isEmpty)
        }
    }
    
    @Test func moveHistoryIsTrimmedToFiveEntries() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let viewModel = KeyboardOverlayViewModel(settings: AppSettings())
            
            for _ in 0..<6 {
                _ = viewModel.move(.right)
            }
            
            #expect(viewModel.lastKeys.count == 5)
        }
    }
}

@MainActor
struct SettingsViewModelLogicTests {
    @Test func restartOnboardingForwardsThroughCallback() async throws {
        try await TestSupport.withTemporarySettingsURL {
            var restartCount = 0
            let viewModel = SettingsViewModel(
                settings: AppSettings(),
                joystick: JoystickInputModel(manager: ControllerInputManager()),
                onRequestControllerBindingCapture: { _ in },
                onRequestControllerActionButtonCapture: { _ in },
                onCancelControllerCapture: {},
                onRestartOnboarding: { restartCount += 1 },
                onUpdateWindowSize: {},
                onTriggerHaptics: {},
                permissionIsAuthorized: { false }
            )
            
            viewModel.restartOnboarding()
            #expect(restartCount == 1)
        }
    }
    
    @Test func controllerToggleRecordingCapturesAndCompletesBinding() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            var requestedCapture: ((ControllerAssignableButton) -> Void)?
            var cancelCount = 0
            
            let viewModel = SettingsViewModel(
                settings: settings,
                joystick: JoystickInputModel(manager: ControllerInputManager()),
                onRequestControllerBindingCapture: { requestedCapture = $0 },
                onRequestControllerActionButtonCapture: { _ in },
                onCancelControllerCapture: { cancelCount += 1 },
                onRestartOnboarding: {},
                onUpdateWindowSize: {},
                onTriggerHaptics: {},
                permissionIsAuthorized: { false }
            )
            
            viewModel.beginControllerToggleRecording(for: .keyboardToggle)
            #expect(viewModel.isRecordingControllerHotkey)
            #expect(viewModel.activeControllerTogglePicker == .keyboardToggle)
            #expect(requestedCapture != nil)
            
            requestedCapture?(.leftTrigger)
            await TestSupport.drainMainQueue()
            
            #expect(settings.controllerToggleBindings.binding(for: .keyboardToggle) == .leftTrigger)
            #expect(!viewModel.isRecordingControllerHotkey)
            #expect(viewModel.activeControllerTogglePicker == nil)
            #expect(cancelCount == 0)
        }
    }
    
    @Test func controllerToggleRecordingCancelsAndRequestsCancellationWhenDismissed() async throws {
        try await TestSupport.withTemporarySettingsURL {
            var cancelCount = 0
            let viewModel = SettingsViewModel(
                settings: AppSettings(),
                joystick: JoystickInputModel(manager: ControllerInputManager()),
                onRequestControllerBindingCapture: { _ in },
                onRequestControllerActionButtonCapture: { _ in },
                onCancelControllerCapture: { cancelCount += 1 },
                onRestartOnboarding: {},
                onUpdateWindowSize: {},
                onTriggerHaptics: {},
                permissionIsAuthorized: { false }
            )
            
            viewModel.beginControllerToggleRecording(for: .mouseToggle)
            viewModel.endControllerToggleRecording(cancelCapture: true)
            await TestSupport.drainMainQueue()
            
            #expect(!viewModel.isRecordingControllerHotkey)
            #expect(viewModel.activeControllerTogglePicker == nil)
            #expect(cancelCount == 1)
        }
    }
    
    @Test func controllerActionPickerUpdatesBindingsThroughCapturedSelection() async throws {
        try await TestSupport.withTemporarySettingsURL {
            var requestedCapture: ((ControllerAssignableButton) -> Void)?
            let settings = AppSettings()
            let viewModel = SettingsViewModel(
                settings: settings,
                joystick: JoystickInputModel(manager: ControllerInputManager()),
                onRequestControllerBindingCapture: { _ in },
                onRequestControllerActionButtonCapture: { requestedCapture = $0 },
                onCancelControllerCapture: {},
                onRestartOnboarding: {},
                onUpdateWindowSize: {},
                onTriggerHaptics: {},
                permissionIsAuthorized: { false }
            )
            
            viewModel.beginControllerActionPicker(for: .accept)
            #expect(viewModel.activeControllerActionPicker == .accept)
            #expect(requestedCapture != nil)
            
            requestedCapture?(.north)
            await TestSupport.drainMainQueue()
            
            #expect(settings.controllerActionBindings.button(for: .accept) == .north)
            #expect(viewModel.activeControllerActionPicker == .accept)
            
            viewModel.endControllerActionPicker()
            #expect(viewModel.activeControllerActionPicker == nil)
        }
    }
    
    @Test func axisInputTypeSelectionEnforcesMutualExclusivity() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            let viewModel = SettingsViewModel(
                settings: settings,
                joystick: JoystickInputModel(manager: ControllerInputManager()),
                onRequestControllerBindingCapture: { _ in },
                onRequestControllerActionButtonCapture: { _ in },
                onCancelControllerCapture: {},
                onRestartOnboarding: {},
                onUpdateWindowSize: {},
                onTriggerHaptics: {},
                permissionIsAuthorized: { false }
            )
            
            viewModel.setAxisActionType(.arrowKeys, fromKeyboard: true, for: .leftStick)
            #expect(settings.leftStickInputType.contains(.arrowKeys))
            #expect(!settings.leftStickInputType.contains(.overlayMovement))
            
            viewModel.setAxisActionType(.none, fromKeyboard: true, for: .leftStick)
            #expect(settings.leftStickInputType == [.scrollWheel])
            
            viewModel.setAxisActionType(.scrollWheel, fromKeyboard: false, for: .rightStick)
            #expect(settings.rightStickInputType == [.scrollWheel])
            
            viewModel.setAxisActionType(.none, fromKeyboard: false, for: .rightStick)
            #expect(settings.rightStickInputType.isEmpty)
        }
    }
    
    @Test func resetDefaultsSynchronizesViewStateWithSettings() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            let viewModel = SettingsViewModel(
                settings: settings,
                joystick: JoystickInputModel(manager: ControllerInputManager()),
                onRequestControllerBindingCapture: { _ in },
                onRequestControllerActionButtonCapture: { _ in },
                onCancelControllerCapture: {},
                onRestartOnboarding: {},
                onUpdateWindowSize: {},
                onTriggerHaptics: {},
                permissionIsAuthorized: { false }
            )
            
            viewModel.keyboardMovementStyle = .full
            viewModel.leftStickDeadzone = 0.1
            viewModel.rightStickDeadzone = 0.9
            viewModel.mouseSensitivity = 999
            viewModel.mouseSmoothing = 0.2
            viewModel.invertMouseX = true
            viewModel.invertScrollY = true
            settings.keyboardMovementStyle = .full
            settings.leftStickDeadzone = 0.1
            settings.rightStickDeadzone = 0.9
            settings.mouseSensitivity = 999
            settings.mouseSmoothing = 0.2
            settings.invertMouseX = true
            settings.invertScrollY = true
            
            viewModel.resetDefaults()
            
            #expect(viewModel.keyboardMovementStyle == .limited)
            #expect(viewModel.leftStickDeadzone == 0.4)
            #expect(viewModel.rightStickDeadzone == 0.4)
            #expect(viewModel.mouseSensitivity == 300)
            #expect(viewModel.mouseSmoothing == 0.4)
            #expect(viewModel.invertMouseX == false)
            #expect(viewModel.invertScrollY == false)
            #expect(settings.keyboardMovementStyle == .limited)
            #expect(settings.leftStickDeadzone == 0.4)
            #expect(settings.mouseSensitivity == 300)
        }
    }
}

@MainActor
struct OnboardingViewModelLogicTests {
    @Test func prepareForPresentationHonorsWelcomeAndPermissionState() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            let viewModel = OnboardingViewModel(
                settings: settings,
                isPermissionAuthorized: { false },
                requestPermissionAuthorization: { false },
                restartApplication: {}
            )
            
            viewModel.prepareForPresentation(startAtWelcome: true)
            #expect(viewModel.step == 0)
            
            viewModel.prepareForPresentation(startAtWelcome: false)
            #expect(viewModel.step == 1)
            #expect(!viewModel.isAccessibilityTrusted)
        }
    }
    
    @Test func permissionButtonAdvancesWhenTrustedAndRequestsWhenNotTrusted() async throws {
        try await TestSupport.withTemporarySettingsURL {
            var granted = false
            var requestCount = 0
            var trustChanges: [Bool] = []
            
            let settings = AppSettings()
            let viewModel = OnboardingViewModel(
                settings: settings,
                isPermissionAuthorized: { granted },
                requestPermissionAuthorization: {
                    requestCount += 1
                    granted = true
                    return true
                },
                restartApplication: {}
            )
            viewModel.onAccessibilityTrustChanged = { trustChanges.append($0) }
            viewModel.prepareForPresentation(startAtWelcome: false)
            
            #expect(viewModel.step == 1)
            #expect(!viewModel.isAccessibilityTrusted)
            
            viewModel.handlePermissionButton()
            #expect(requestCount == 1)
            #expect(viewModel.step == 2)
            #expect(viewModel.isAccessibilityTrusted)
            #expect(viewModel.isAwaitingPermissionGrant)
            #expect(trustChanges == [true])
            
            viewModel.handlePermissionButton()
            #expect(viewModel.step == 2)
        }
    }
    
    @Test func permissionButtonUsesRestartFlowWhenAlreadyAwaitingGrant() async throws {
        try await TestSupport.withTemporarySettingsURL {
            var granted = false
            var requestCount = 0
            var restartCount = 0
            
            let settings = AppSettings()
            let viewModel = OnboardingViewModel(
                settings: settings,
                isPermissionAuthorized: { granted },
                requestPermissionAuthorization: {
                    requestCount += 1
                    return false
                },
                restartApplication: { restartCount += 1 }
            )
            viewModel.prepareForPresentation(startAtWelcome: false)
            viewModel.isAwaitingPermissionGrant = true
            
            viewModel.handlePermissionButton()
            
            #expect(settings.restartedFromPermissionScreen)
            #expect(restartCount == 1)
            #expect(requestCount == 0)
        }
    }
    
    @Test func shortcutActivationOnlyCompletesDuringActivationStep() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            var completionCount = 0
            let viewModel = OnboardingViewModel(
                settings: settings,
                isPermissionAuthorized: { true },
                requestPermissionAuthorization: { true },
                restartApplication: {}
            )
            viewModel.onComplete = { completionCount += 1 }
            
            viewModel.handleShortcutActivation()
            #expect(completionCount == 0)
            
            viewModel.advanceStep()
            viewModel.advanceStep()
            viewModel.advanceStep()
            #expect(viewModel.isAwaitingActivation)
            
            viewModel.handleShortcutActivation()
            #expect(completionCount == 1)
        }
    }
    
    @Test func goBackNeverMovesBeforeTheStartAndStopClearsPollingTimer() async throws {
        try await TestSupport.withTemporarySettingsURL {
            let settings = AppSettings()
            let viewModel = OnboardingViewModel(
                settings: settings,
                isPermissionAuthorized: { true },
                requestPermissionAuthorization: { true },
                restartApplication: {}
            )
            
            viewModel.goBack()
            #expect(viewModel.step == 0)
            
            viewModel.advanceStep()
            viewModel.goBack()
            #expect(viewModel.step == 0)
            
            viewModel.stop()
            #expect(!viewModel.isAwaitingPermissionGrant)
        }
    }
}
