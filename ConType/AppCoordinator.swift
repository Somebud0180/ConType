//
//  AppCoordinator.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Represents the source of an overlay toggle action.
private enum ToggleSource {
    case menuBar
    case keyboardShortcut
    case controllerShortcut
    
    /// Differentiates the activation source between the menu bar toggle and a keyboard/controller shortcut.
    /// - Returns: `true` if activated via the keyboard or controller shortcut, `false` if activated via the menu bar.
    var isShortcutActivation: Bool {
        switch self {
        case .menuBar:
            return false
        case .keyboardShortcut, .controllerShortcut:
            return true
        }
    }
}

/// The central coordinator responsible for managing the app's windows, settings, and input handling.
@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isOverlayVisible = false
    let settings = AppSettings()
    let joystick: JoystickInputModel
    
    private let hasLaunchedBeforeDefaultsKey = "ConType.hasLaunchedBefore"
    private let launchAtLoginService = SMAppService.mainApp
    
    private lazy var settingsController = SettingsWindowController(
        settings: settings,
        joystick: joystick,
        onRequestControllerBindingCapture: { [weak self] onCaptured in
            self?.controllerInputManager.captureNextToggleBinding(onCaptured)
        },
        onRequestControllerActionButtonCapture: { [weak self] onCaptured in
            self?.controllerInputManager.captureNextAssignableButton(onCaptured)
        },
        onCancelControllerCapture: { [weak self] in
            self?.controllerInputManager.cancelPendingCaptures()
        },
        onRestartOnboarding: { [weak self] in
            self?.restartOnboardingFromSettings()
        },
        onUpdateWindowSize: { [weak self] in
            self?.overlayController.updateWindowSize()
        },
        onTriggerHaptics: { [weak self] in
            self?.controllerInputManager.playRumbleIfSupported()
        }
    )
    private lazy var tutorialController = TutorialWindowController(settings: settings)
    private lazy var overlayController = OverlayWindowController(settings: settings)
    private lazy var onboardingController = OnboardingWindowController(settings: settings)
    private let hotkeyManager = KeyboardHotkeyManager()
    private let controllerInputManager = ControllerInputManager()
    private let mouseEmitter = MouseEmitter()
    private var cancellables = Set<AnyCancellable>()
    private var isHotkeyManagerRunning = false
    
    private var hasLaunchedBefore: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasLaunchedBeforeDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasLaunchedBeforeDefaultsKey)
        }
    }
    
    init() {
        joystick = JoystickInputModel(manager: controllerInputManager)
        
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                guard let self, self.tutorialController.isVisible else { return }
                self.toggleOverlay(source: .keyboardShortcut)
            }
        }
        
        controllerInputManager.onToggleKeyboard = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.onKeyboardOverlayActivated()
                } else {
                    self.toggleOverlay(source: .controllerShortcut, forMouse: false)
                }
            }
        }
        
        controllerInputManager.onToggleMouse = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.onMouseOverlayActivated()
                } else {
                    self.toggleOverlay(source: .controllerShortcut, forMouse: true)
                }
            }
        }
        
        controllerInputManager.onDismissWithGuideButton = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.dismissOverlayViaGuideButtonIfNeeded()
                    self.refreshControllerOverlayVisibility()
                } else {
                    self.dismissOverlayViaGuideButtonIfNeeded()
                }
            }
        }
        
        controllerInputManager.onMove = { [weak self] direction, trigger in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.moveSelection(direction, trigger: trigger)
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate()
                    let didMove = self.overlayController.moveSelection(direction, trigger: trigger)
                    if didMove {
                        self.controllerInputManager.playRumbleIfSupported()
                    }
                }
            }
        }
        
        controllerInputManager.onMouseMove = { [weak self] delta in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.moveMouse(by: delta)
                } else if self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible {
                    NSApp.deactivate()
                    self.mouseEmitter.moveCursor(by: delta)
                }
            }
        }
        
        controllerInputManager.onScroll = { [weak self] delta in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                NSApp.deactivate()
                self.mouseEmitter.scroll(delta)
            }
        }
        
        controllerInputManager.onSelect = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateSelectedKey()
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate()
                    self.overlayController.activateSelectedKey()
                }
            }
        }
        
        controllerInputManager.onBackspace = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateBackspaceKey()
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate()
                    self.overlayController.activateBackspaceKey()
                }
            }
        }
        
        controllerInputManager.onSpace = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateSpaceKey()
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate ()
                    self.overlayController.activateSpaceKey()
                }
            }
        }
        
        controllerInputManager.onEnter = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateEnterKey()
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate()
                    self.overlayController.activateEnterKey()
                }
            }
        }
        
        controllerInputManager.onShift = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateShiftShortcut(cyclesToCapsLock: self.settings.shiftShortcutCyclesToCapsLock)
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate()
                    self.overlayController.activateShiftShortcut(cyclesToCapsLock: self.settings.shiftShortcutCyclesToCapsLock)
                }
            }
        }
        
        controllerInputManager.onCapsLock = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateCapsLockShortcut()
                } else if self.overlayController.isKeyboardVisible {
                    NSApp.deactivate()
                    self.overlayController.activateCapsLockShortcut()
                }
            }
        }
        
        controllerInputManager.onLeftClickDown = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateMouseButton(.leftMouseDown)
                } else if self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible {
                    NSApp.deactivate()
                    self.mouseEmitter.emit(button: .left, eventType: .leftMouseDown)
                }
            }
        }
        
        controllerInputManager.onRightClickDown = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateMouseButton(.rightMouseDown)
                } else if self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible {
                    NSApp.deactivate()
                    self.mouseEmitter.emit(button: .right, eventType: .rightMouseDown)
                }
            }
        }
        
        controllerInputManager.onLeftClickUp = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateMouseButton(.leftMouseUp)
                } else if self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible {
                    NSApp.deactivate()
                    self.mouseEmitter.emit(button: .left, eventType: .leftMouseUp)
                }
            }
        }
        
        controllerInputManager.onRightClickUp = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.tutorialController.isVisible {
                    self.tutorialController.activateMouseButton(.rightMouseUp)
                } else if self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible {
                    NSApp.deactivate()
                    self.mouseEmitter.emit(button: .right, eventType: .rightMouseUp)
                }
            }
        }
        
        controllerInputManager.onEnlarge = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                self.overlayController.enlargeWindow()
            }
        }
        
        controllerInputManager.onShrink = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                self.overlayController.shrinkWindow()
            }
        }
        
        controllerInputManager.onArrowMoveLeft = { [weak self] in
            Task { @MainActor in
                guard let self, self.tutorialController.isVisible else { return }
                self.tutorialController.moveCaretLeft()
            }
        }
        
        controllerInputManager.onArrowMoveRight = { [weak self] in
            Task { @MainActor in
                guard let self, self.tutorialController.isVisible else { return }
                self.tutorialController.moveCaretRight()
            }
        }
        
        controllerInputManager.onGlyphStyleChanged = { [weak self] style in
            Task { @MainActor in
                self?.settings.controllerGlyphStyle = style
            }
        }
        
        controllerInputManager.onCaptureStateChanged = { [weak self] captureState in
            Task { @MainActor in
                self?.settings.controllerCaptureState = captureState
            }
        }
        
        controllerInputManager.onDetectedControllerChanged = { [weak self] detectedController in
            Task { @MainActor in
                self?.settings.detectedController = detectedController
            }
        }
        
        settingsController.onClose = { [weak self] in
            Task { @MainActor in
                self?.updateActivationPolicyForCurrentUIState()
            }
        }
        
        onboardingController.onClose = { [weak self] in
            Task { @MainActor in
                self?.refreshHotkeyManagerState()
                self?.updateActivationPolicyForCurrentUIState()
            }
        }
        
        onboardingController.openSettings = { [weak self] in
            Task { @MainActor in
                self?.settingsController.show()
            }
        }
        
        onboardingController.openTutorial = { [weak self] in
            Task { @MainActor in
                self?.tutorialController.show()
                self?.refreshControllerOverlayVisibility()
            }
        }
        
        onboardingController.onAccessibilityTrustChanged = { [weak self] _ in
            Task { @MainActor in
                self?.refreshHotkeyManagerState()
            }
        }
        
        tutorialController.onClose = { [weak self] in
            Task { @MainActor in
                self?.updateActivationPolicyForCurrentUIState()
                self?.refreshControllerOverlayVisibility()
            }
        }
        
        tutorialController.openSettings = { [weak self] in
            Task { @MainActor in
                self?.settingsController.show()
            }
        }
        
        tutorialController.updateCoordinatorVisibility = { [weak self] in
            Task { @MainActor in
                self?.refreshControllerOverlayVisibility()
            }
        }
        
        hotkeyManager.shortcut = settings.keyboardHotkey
        controllerInputManager.toggleBindings = settings.controllerToggleBindings
        controllerInputManager.actionBindings = settings.controllerActionBindings
        controllerInputManager.leftStickInputType = settings.leftStickInputType
        controllerInputManager.rightStickInputType = settings.rightStickInputType
        controllerInputManager.padInputType = settings.padInputType
        controllerInputManager.dismissWithGuideButton = settings.dismissWithGuideButton
        controllerInputManager.isOverlayVisible = isOverlayVisible
        controllerInputManager.keyboardMovementStyle = settings.keyboardMovementStyle
        controllerInputManager.leftStickDeadzone = settings.leftStickDeadzone
        controllerInputManager.rightStickDeadzone = settings.rightStickDeadzone
        controllerInputManager.mouseSensitivity = settings.mouseSensitivity
        controllerInputManager.mouseSmoothingAlpha = settings.mouseSmoothing
        controllerInputManager.invertMouseX = settings.invertMouseX
        controllerInputManager.invertMouseY = settings.invertMouseY
        controllerInputManager.scrollSpeed = settings.scrollSpeed
        controllerInputManager.invertScrollX = settings.invertScrollX
        controllerInputManager.invertScrollY = settings.invertScrollY
        controllerInputManager.enableMouseInKeyboard = settings.enableMouseInKeyboard
        controllerInputManager.prioritizeMouseOverKeyboard = settings.prioritizeMouseOverKeyboard
        controllerInputManager.enableHaptics = settings.enableHaptics
        refreshControllerOverlayVisibility()
        
        settings.$keyboardHotkey
            .sink { [weak self] value in
                self?.hotkeyManager.shortcut = value
            }
            .store(in: &cancellables)
        
        settings.$controllerToggleBindings
            .sink { [weak self] value in
                self?.controllerInputManager.toggleBindings = value
            }
            .store(in: &cancellables)
        
        settings.$controllerActionBindings
            .sink { [weak self] value in
                self?.controllerInputManager.actionBindings = value
            }
            .store(in: &cancellables)
        
        settings.$leftStickInputType
            .sink { [weak self] value in
                self?.controllerInputManager.leftStickInputType = value
            }
            .store(in: &cancellables)
        
        settings.$rightStickInputType
            .sink { [weak self] value in
                self?.controllerInputManager.rightStickInputType = value
            }
            .store(in: &cancellables)
        
        settings.$padInputType
            .sink { [weak self] value in
                self?.controllerInputManager.padInputType = value
            }
            .store(in: &cancellables)
        
        settings.$dismissWithGuideButton
            .sink { [weak self] value in
                self?.controllerInputManager.dismissWithGuideButton = value
            }
            .store(in: &cancellables)
        
        settings.$keyboardMovementStyle
            .sink { [weak self] value in
                self?.controllerInputManager.keyboardMovementStyle = value
            }
            .store(in: &cancellables)
        
        settings.$leftStickDeadzone
            .sink { [weak self] value in
                self?.controllerInputManager.leftStickDeadzone = value
            }
            .store(in: &cancellables)
        
        settings.$rightStickDeadzone
            .sink { [weak self] value in
                self?.controllerInputManager.rightStickDeadzone = value
            }
            .store(in: &cancellables)
        
        settings.$mouseSensitivity
            .sink { [weak self] value in
                self?.controllerInputManager.mouseSensitivity = value
            }
            .store(in: &cancellables)
        
        settings.$mouseSmoothing
            .sink { [weak self] value in
                self?.controllerInputManager.mouseSmoothingAlpha = value
            }
            .store(in: &cancellables)
        
        settings.$invertMouseX
            .sink { [weak self] value in
                self?.controllerInputManager.invertMouseX = value
            }
            .store(in: &cancellables)
        
        settings.$invertMouseY
            .sink { [weak self] value in
                self?.controllerInputManager.invertMouseY = value
            }
            .store(in: &cancellables)
        
        settings.$scrollSpeed
            .sink { [weak self] value in
                self?.controllerInputManager.scrollSpeed = value
            }
            .store(in: &cancellables)
        
        settings.$invertScrollX
            .sink { [weak self] value in
                self?.controllerInputManager.invertScrollX = value
            }
            .store(in: &cancellables)
        
        settings.$invertScrollY
            .sink { [weak self] value in
                self?.controllerInputManager.invertScrollY = value
            }
            .store(in: &cancellables)
        
        settings.$enableMouseInKeyboard
            .sink { [weak self] value in
                self?.controllerInputManager.enableMouseInKeyboard = value
            }
            .store(in: &cancellables)
        
        settings.$prioritizeMouseOverKeyboard
            .sink { [weak self] value in
                self?.controllerInputManager.prioritizeMouseOverKeyboard = value
            }
            .store(in: &cancellables)
        
        settings.$enableHaptics
            .sink { [weak self] value in
                self?.controllerInputManager.enableHaptics = value
            }
            .store(in: &cancellables)
        
        settings.$inMouseMode
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshControllerOverlayVisibility()
                }
            }
            .store(in: &cancellables)
        
        configureOpenAppOnStartup()
        
        setAccessoryMode()
        refreshHotkeyManagerState()
        controllerInputManager.start()
        
        DispatchQueue.main.async { [weak self] in
            self?.presentOnboardingIfNeededOnLaunch()
        }
    }
    
    /// Opens the settings window and ensures the app is in regular activation mode so it can receive focus.
    func openSettings() {
        setRegularMode()
        settingsController.show()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Restarts the onboarding flow from the settings screen, with extra handling to ensure a fresh restart of the flow.
    private func restartOnboardingFromSettings() {
        settingsController.close()
        presentOnboarding(startAtWelcome: true)
    }
    
    /// Quits the app.
    func quit() {
        NSApp.terminate(nil)
    }
    
    /// Toggles the overlay visibility, treats the activation as coming from the menu bar.
    func toggleOverlay() {
        toggleOverlay(source: .menuBar)
    }
    
    /// Toggles the overlay visibility based on the source of the toggle action.
    ///   - source:  The source of the toggle action. Utilizes `ToggleSource` enum.
    ///   - forMouse: Indicates wether this shortcut activation is intended to toggle the mouse overlay.
    private func toggleOverlay(source: ToggleSource, forMouse: Bool = false) {
        guard !tutorialController.isVisible  else { return }
        
        refreshHotkeyManagerState()
        
        if source.isShortcutActivation {
            onboardingController.handleShortcutActivation()
        }
        
        if !InputMonitoringPermission.isAuthorized() {
            presentOnboarding(startAtWelcome: false)
        }
        
        if overlayController.isKeyboardVisible || overlayController.isMouseVisible {
            if forMouse && !settings.inMouseMode {
                /// If the toggle is for the mouse overlay, and the app is not currently in mouse mode, switch to the mouse overlay.
                overlayController.hide()
                settings.inMouseMode = true
                overlayController.show()
                refreshControllerOverlayVisibility()
                return
            } else if !forMouse && settings.inMouseMode {
                /// If the toggle is for the keyboard overlay, and the app is currently in mouse mode, switch to the keyboard overlay.
                overlayController.hide()
                settings.inMouseMode = false
                overlayController.show()
                refreshControllerOverlayVisibility()
                return
            }
            
            /// If the overlay is currently visible and the toggle action doesn't indicate a mode switch, hide the overlay.
            overlayController.hide()
            isOverlayVisible = false
            controllerInputManager.isOverlayVisible = false
            refreshControllerOverlayVisibility()
            updateActivationPolicyForCurrentUIState()
            return
        }
        
        updateActivationPolicyForCurrentUIState()
        
        /// Enable the appropriate overlay mode based on the toggle source and intent, then show the overlay.
        if forMouse {
            settings.inMouseMode = true
        } else {
            settings.inMouseMode = false
        }
        
        DispatchQueue.main.async { [weak self] in
            /// Show the overlay and deactivate to ensure focus is not stolen from the front app.
            guard let self else { return }
            self.isOverlayVisible = self.overlayController.show()
            self.controllerInputManager.isOverlayVisible = self.isOverlayVisible
            self.refreshControllerOverlayVisibility()
            NSApp.deactivate()
        }
    }
    
    /// Dismisses the overlay if it's currently visible and the user presses the guide button on their controller (if enabled in settings).
    private func dismissOverlayViaGuideButtonIfNeeded() {
        guard overlayController.isKeyboardVisible || overlayController.isMouseVisible else { return }
        overlayController.hide()
        isOverlayVisible = false
        controllerInputManager.isOverlayVisible = false
        refreshControllerOverlayVisibility()
        updateActivationPolicyForCurrentUIState()
    }
    
    /// Refreshes the visibility state of the keyboard and mouse overlays in the controller input manager based on the current visibility of the overlays in the overlay controller.
    private func refreshControllerOverlayVisibility() {
        let tutorialVisible = tutorialController.isVisible
        controllerInputManager.isTutorialVisible = tutorialVisible
        controllerInputManager.isKeyboardOverlayVisible = tutorialVisible ? tutorialController.isKeboardVisible : overlayController.isKeyboardVisible
        controllerInputManager.isMouseOverlayVisible = tutorialVisible ? tutorialController.isMouseVisible : overlayController.isMouseVisible
    }
    
    // MARK: - Onboarding Handling
    /// Determines wether the onboarding flow needs to be presented on app launch.
    /// Conditions include:
    ///  - First app launch ever
    ///  - Missing input monitoring permission
    ///  - Returning to the app after restarting from the permisison screen
    private func presentOnboardingIfNeededOnLaunch() {
        let isFirstLaunch = !hasLaunchedBefore
        if isFirstLaunch {
            hasLaunchedBefore = true
        }
        
        let shouldShowForMissingPermission = !InputMonitoringPermission.isAuthorized()
        let shouldShowAfterRestart = settings.restartedFromPermissionScreen
        
        guard isFirstLaunch || shouldShowForMissingPermission || shouldShowAfterRestart else { return }
        presentOnboarding(startAtWelcome: isFirstLaunch)
    }
    
    /// Presents the onboarding flow, with the option to start at the welcome screen or a later step based on the context of why the onboarding is being shown.
    private func presentOnboarding(startAtWelcome: Bool) {
        guard !onboardingController.isVisible else {
            setRegularMode()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        setRegularMode()
        onboardingController.show(startAtWelcome: startAtWelcome)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Launch at Login Configuration
    /// Updates the launch-at-login setting based on the current state of the system and user preferences, and sets up a listener to keep them in sync.
    private func configureOpenAppOnStartup() {
        settings.openAppOnStartup = isLaunchAtLoginEnabled
        
        settings.$openAppOnStartup
            .removeDuplicates()
            .sink { [weak self] shouldEnable in
                self?.setLaunchAtLoginEnabled(shouldEnable)
            }
            .store(in: &cancellables)
    }
    
    /// Checks the current status of the launch-at-login service to determine if launch-at-login is effectively enabled.
    private var isLaunchAtLoginEnabled: Bool {
        switch launchAtLoginService.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Enables or disables launch-at-login based on the provided boolean, and ensures the app's settings reflect the effective state of the launch-at-login service after the change.
    /// - Parameter shouldEnable: A boolean indicating whether launch-at-login should be enabled or disabled.
    private func setLaunchAtLoginEnabled(_ shouldEnable: Bool) {
        guard isLaunchAtLoginEnabled != shouldEnable else { return }
        
        do {
            if shouldEnable {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
        } catch {
            debugPrint("[AppSettings] Failed to update launch-at-login setting:", error)
        }
        
        let resolvedValue = isLaunchAtLoginEnabled
        if settings.openAppOnStartup != resolvedValue {
            settings.openAppOnStartup = resolvedValue
        }
    }
    
    // MARK: - Miscellaneous
    /// Updates the app's activation policy based on the current visibility of the settings and onboarding windows. If either is visible, the app should be in regular mode to allow interaction. If both are hidden, the app can switch to accessory mode to stay out of the way.
    private func updateActivationPolicyForCurrentUIState() {
        if settingsController.isVisible || onboardingController.isVisible || tutorialController.isVisible {
            setRegularMode()
        } else {
            setAccessoryMode()
        }
    }
    
    /// Updates the state of the hotkey manager based on whether the app has the necessary input monitoring permissions. The hotkey manager is only active when permissions are granted, and is stopped when permissions are revoked to prevent issues with unauthorized event taps.
    private func refreshHotkeyManagerState() {
        let shouldRunHotkeyManager = InputMonitoringPermission.isAuthorized()
        
        if shouldRunHotkeyManager {
            guard !isHotkeyManagerRunning else { return }
            hotkeyManager.start()
            isHotkeyManagerRunning = true
            return
        }
        
        guard isHotkeyManagerRunning else { return }
        hotkeyManager.stop()
        isHotkeyManagerRunning = false
    }
    
    /// Sets the app's activation policy to accessory mode, which hides the app from the Dock and app switcher, allowing it to run in the background without stealing focus.
    private func setAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    /// Sets the app's activation policy to regular mode, which allows the app to appear in the Dock and app switcher, and receive focus for user interaction.
    private func setRegularMode() {
        NSApp.setActivationPolicy(.regular)
    }
}
