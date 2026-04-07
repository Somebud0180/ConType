import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isOverlayVisible = false
    let settings = AppSettings()

    private let overlayController = OverlayWindowController()
    private lazy var settingsController = SettingsWindowController(
        settings: settings,
        onRequestControllerBindingCapture: { [weak self] onCaptured in
            self?.controllerInputManager.captureNextToggleBinding(onCaptured)
        }
    )
    private let hotkeyManager = KeyboardHotkeyManager()
    private let controllerInputManager = ControllerInputManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay()
            }
        }

        controllerInputManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay()
            }
        }

        controllerInputManager.onMove = { [weak self] direction in
            Task { @MainActor in
                guard let self, self.overlayController.isVisible else { return }
                // Ensure we don't activate our app due to controller input
                NSApp.deactivate()
                self.overlayController.moveSelection(direction)
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

        settingsController.onClose = { [weak self] in
            Task { @MainActor in
                self?.setAccessoryMode()
            }
        }

        hotkeyManager.shortcut = settings.keyboardHotkey
        controllerInputManager.toggleBinding = settings.controllerToggleBinding
        controllerInputManager.invertControllerFaceButtons = settings.invertControllerFaceButtons

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

        settings.$invertControllerFaceButtons
            .sink { [weak self] value in
                self?.controllerInputManager.invertControllerFaceButtons = value
            }
            .store(in: &cancellables)

        setAccessoryMode()
        hotkeyManager.start()
        controllerInputManager.start()
    }

    func toggleOverlay() {
        if overlayController.isVisible {
            overlayController.hide()
            isOverlayVisible = false
            if !settingsController.isVisible {
                setAccessoryMode()
            }
            return
        }

        if !settingsController.isVisible {
            setAccessoryMode()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOverlayVisible = self.overlayController.show()
            // Ensure our app doesn't steal focus from the target app
            NSApp.deactivate()
        }
    }

    func openSettings() {
        setRegularMode()
        settingsController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func setAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func setRegularMode() {
        NSApp.setActivationPolicy(.regular)
    }
}
