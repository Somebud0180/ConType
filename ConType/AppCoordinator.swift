import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isOverlayVisible = false
    let settings = AppSettings()
    let joystick: JoystickInputModel
    
    private enum ToggleSource {
        case menuBar
        case keyboardShortcut
        case controllerShortcut
        
        var isShortcutActivation: Bool {
            switch self {
            case .menuBar:
                return false
            case .keyboardShortcut, .controllerShortcut:
                return true
            }
        }
    }
    
    private let hasLaunchedBeforeDefaultsKey = "ConType.hasLaunchedBefore"
    private let launchAtLoginService = SMAppService.mainApp
    
    private lazy var overlayController = OverlayWindowController(settings: settings)
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
        }
    )
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
                self?.toggleOverlay(source: .keyboardShortcut)
            }
        }
        
        controllerInputManager.onToggleKeyboard = { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay(source: .controllerShortcut, forMouse: false)
            }
        }
        
        controllerInputManager.onToggleMouse = { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay(source: .controllerShortcut, forMouse: true)
            }
        }
        
        controllerInputManager.onDismissWithGuideButton = { [weak self] in
            Task { @MainActor in
                self?.dismissOverlayViaGuideButtonIfNeeded()
            }
        }
        
        controllerInputManager.onMove = { [weak self] direction, trigger in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.moveSelection(direction, trigger: trigger)
            }
        }
        
        controllerInputManager.onMouseMove = { [weak self] delta in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                NSApp.deactivate()
                self.mouseEmitter.moveCursor(by: delta)
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
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateSelectedKey()
            }
        }
        
        controllerInputManager.onBackspace = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateBackspaceKey()
            }
        }
        
        controllerInputManager.onSpace = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateSpaceKey()
            }
        }
        
        controllerInputManager.onEnter = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateEnterKey()
            }
        }
        
        controllerInputManager.onShift = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateShiftShortcut(cyclesToCapsLock: self.settings.shiftShortcutCyclesToCapsLock)
            }
        }
        
        controllerInputManager.onCapsLock = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateCapsLockShortcut()
            }
        }
        
        controllerInputManager.onLeftClickDown = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                NSApp.deactivate()
                self.mouseEmitter.emit(button: .left, eventType: .leftMouseDown)
            }
        }
        
        controllerInputManager.onRightClickDown = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                NSApp.deactivate()
                self.mouseEmitter.emit(button: .right, eventType: .rightMouseDown)
            }
        }
        
        controllerInputManager.onLeftClickUp = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                NSApp.deactivate()
                self.mouseEmitter.emit(button: .left, eventType: .leftMouseUp)
            }
        }
        
        controllerInputManager.onRightClickUp = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                NSApp.deactivate()
                self.mouseEmitter.emit(button: .right, eventType: .rightMouseUp)
            }
        }
        
        controllerInputManager.onEnlarge = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                debugPrint("Keyboard Visibility: \(self.overlayController.isKeyboardVisible), Mouse Visibility: \(self.overlayController.isMouseVisible)")
                self.overlayController.enlargeWindow()
            }
        }
        
        controllerInputManager.onShrink = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isKeyboardVisible || self.overlayController.isMouseVisible else { return }
                self.overlayController.shrinkWindow()
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
        
        onboardingController.onAccessibilityTrustChanged = { [weak self] _ in
            Task { @MainActor in
                self?.refreshHotkeyManagerState()
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
    
    func toggleOverlay() {
        toggleOverlay(source: .menuBar)
    }
    
    func openSettings() {
        setRegularMode()
        settingsController.show()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func restartOnboardingFromSettings() {
        settingsController.close()
        presentOnboarding(startAtWelcome: true)
    }
    
    func quit() {
        NSApp.terminate(nil)
    }
    
    private func toggleOverlay(source: ToggleSource, forMouse: Bool = false) {
        refreshHotkeyManagerState()
        
        if source.isShortcutActivation {
            onboardingController.handleShortcutActivation()
        }
        
        if !InputMonitoringPermission.isAuthorized() {
            presentOnboarding(startAtWelcome: false)
        }
        
        if overlayController.isKeyboardVisible || overlayController.isMouseVisible {
            debugPrint("For Mouse: \(forMouse), In Mouse Mode: \(settings.inMouseMode)")
            if forMouse && !settings.inMouseMode {
                debugPrint("Switching to mouse overlay")
                overlayController.hide()
                settings.inMouseMode = true
                overlayController.show()
                return
            } else if !forMouse && settings.inMouseMode {
                debugPrint("Switching to keyboard overlay")
                overlayController.hide()
                settings.inMouseMode = false
                overlayController.show()
                return
            }
            
            overlayController.hide()
            isOverlayVisible = false
            controllerInputManager.isOverlayVisible = false
            refreshControllerOverlayVisibility()
            updateActivationPolicyForCurrentUIState()
            return
        }
        
        updateActivationPolicyForCurrentUIState()
        
        if forMouse {
            settings.inMouseMode = true
        } else {
            settings.inMouseMode = false
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOverlayVisible = self.overlayController.show()
            self.controllerInputManager.isOverlayVisible = self.isOverlayVisible
            self.refreshControllerOverlayVisibility()
            // Ensure our app doesn't steal focus from the target app
            NSApp.deactivate()
        }
    }
    
    private func dismissOverlayViaGuideButtonIfNeeded() {
        guard overlayController.isKeyboardVisible || overlayController.isMouseVisible else { return }
        overlayController.hide()
        isOverlayVisible = false
        controllerInputManager.isOverlayVisible = false
        refreshControllerOverlayVisibility()
        updateActivationPolicyForCurrentUIState()
    }
    
    private func refreshControllerOverlayVisibility() {
        controllerInputManager.isKeyboardOverlayVisible = overlayController.isKeyboardVisible
        controllerInputManager.isMouseOverlayVisible = overlayController.isMouseVisible
    }
    
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
    
    private func configureOpenAppOnStartup() {
        settings.openAppOnStartup = isLaunchAtLoginEnabled
        
        settings.$openAppOnStartup
            .removeDuplicates()
            .sink { [weak self] shouldEnable in
                self?.setLaunchAtLoginEnabled(shouldEnable)
            }
            .store(in: &cancellables)
    }
    
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
    
    private func updateActivationPolicyForCurrentUIState() {
        if settingsController.isVisible || onboardingController.isVisible {
            setRegularMode()
        } else {
            setAccessoryMode()
        }
    }
    
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
    
    private func setAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setRegularMode() {
        NSApp.setActivationPolicy(.regular)
    }
}
