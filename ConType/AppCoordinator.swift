import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isOverlayVisible = false
    let settings = AppSettings()

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

    private let overlayController = OverlayWindowController()
    private lazy var settingsController = SettingsWindowController(
        settings: settings,
        onRequestControllerBindingCapture: { [weak self] onCaptured in
            self?.controllerInputManager.captureNextToggleBinding(onCaptured)
        },
        onRequestControllerActionButtonCapture: { [weak self] onCaptured in
            self?.controllerInputManager.captureNextAssignableButton(onCaptured)
        },
        onCancelControllerCapture: { [weak self] in
            self?.controllerInputManager.cancelPendingCaptures()
        }
    )
    private lazy var onboardingController = OnboardingWindowController(settings: settings)
    private let hotkeyManager = KeyboardHotkeyManager()
    private let controllerInputManager = ControllerInputManager()
    private var cancellables = Set<AnyCancellable>()

    private var hasLaunchedBefore: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasLaunchedBeforeDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasLaunchedBeforeDefaultsKey)
        }
    }

    init() {
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay(source: .keyboardShortcut)
            }
        }

        controllerInputManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay(source: .controllerShortcut)
            }
        }

        controllerInputManager.onMove = { [weak self] direction, trigger in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                // Ensure we don't activate our app due to controller input
                NSApp.deactivate()
                self.overlayController.moveSelection(direction, trigger: trigger)
            }
        }

        controllerInputManager.onSelect = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                // Ensure we don't activate our app due to controller input
                NSApp.deactivate()
                self.overlayController.activateSelectedKey()
            }
        }

        controllerInputManager.onBackspace = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                // Ensure we don't activate our app due to controller input
                NSApp.deactivate()
                self.overlayController.activateBackspaceKey()
            }
        }

        controllerInputManager.onSpace = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateSpaceKey()
            }
        }

        controllerInputManager.onEnter = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateEnterKey()
            }
        }

        controllerInputManager.onShift = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateShiftShortcut(cyclesToCapsLock: self.settings.shiftShortcutCyclesToCapsLock)
            }
        }

        controllerInputManager.onCapsLock = { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                NSApp.deactivate()
                self.overlayController.activateCapsLockShortcut()
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

        settingsController.onClose = { [weak self] in
            Task { @MainActor in
                self?.updateActivationPolicyForCurrentUIState()
            }
        }

        onboardingController.onClose = { [weak self] in
            Task { @MainActor in
                self?.updateActivationPolicyForCurrentUIState()
            }
        }

        hotkeyManager.shortcut = settings.keyboardHotkey
        controllerInputManager.toggleBinding = settings.controllerToggleBinding
        controllerInputManager.actionBindings = settings.controllerActionBindings

        settings.$keyboardHotkey
            .sink { [weak self] value in
                self?.hotkeyManager.shortcut = value
            }
            .store(in: &cancellables)

        settings.$controllerToggleBinding
            .sink { [weak self] value in
                self?.controllerInputManager.toggleBinding = value
            }
            .store(in: &cancellables)

        settings.$controllerActionBindings
            .sink { [weak self] value in
                self?.controllerInputManager.actionBindings = value
            }
            .store(in: &cancellables)

        setAccessoryMode()
        hotkeyManager.start()
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

    func quit() {
        NSApp.terminate(nil)
    }

    private func toggleOverlay(source: ToggleSource) {
        if source.isShortcutActivation {
            onboardingController.handleShortcutActivation()
        }

        if !AccessibilityPermission.isTrusted() {
            presentOnboarding(startAtWelcome: false)
        }

        if overlayController.isVisible {
            overlayController.hide()
            isOverlayVisible = false
            updateActivationPolicyForCurrentUIState()
            return
        }

        updateActivationPolicyForCurrentUIState()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOverlayVisible = self.overlayController.show()
            // Ensure our app doesn't steal focus from the target app
            NSApp.deactivate()
        }
    }

    private func presentOnboardingIfNeededOnLaunch() {
        let isFirstLaunch = !hasLaunchedBefore
        if isFirstLaunch {
            hasLaunchedBefore = true
        }

        let shouldShowForMissingPermission = !AccessibilityPermission.isTrusted()

        guard isFirstLaunch || shouldShowForMissingPermission else { return }
        presentOnboarding(startAtWelcome: isFirstLaunch)
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

    private func setAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func setRegularMode() {
        NSApp.setActivationPolicy(.regular)
    }
}
