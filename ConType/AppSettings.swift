import AppKit
import Combine
import Foundation

enum ControllerGlyphStyle: Equatable {
    case generic
    case playStation
    case nintendoSwitch

    static func detect(vendorName: String?, productCategory: String?) -> ControllerGlyphStyle {
        let parts = [vendorName, productCategory]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if parts.contains("dualsense")
            || parts.contains("dualshock")
            || parts.contains("playstation")
            || parts.contains("sony")
            || (parts.contains("wireless controller") && !parts.contains("xbox")) {
            return .playStation
        }

        if parts.contains("nintendo")
            || parts.contains("switch")
            || parts.contains("joy-con")
            || parts.contains("joycon")
            || parts.contains("pro controller") {
            return .nintendoSwitch
        }

        return .generic
    }

    var guideGlyphAssetName: String {
        switch self {
        case .generic:
            return "Menu"
        case .playStation:
            return "Menu_PS"
        case .nintendoSwitch:
            return "Menu_Switch"
        }
    }
}

enum ControllerGuideButton: String, CaseIterable, Equatable {
    case menu
    case home
    case options

    func displayTitle(for style: ControllerGlyphStyle) -> String {
        switch (style, self) {
        case (.nintendoSwitch, .menu):
            return "+"
        case (.nintendoSwitch, .options):
            return "-"
        case (.nintendoSwitch, .home):
            return "Home"
        case (.playStation, .menu):
            return "Create"
        case (.playStation, .home):
            return "PS"
        case (.playStation, .options):
            return "Options"
        case (_, .menu):
            return "Menu"
        case (_, .home):
            return "Home"
        case (_, .options):
            return "Options"
        }
    }

    func glyphAssetName(for style: ControllerGlyphStyle) -> String? {
        switch (style, self) {
        case (.playStation, .menu):
            return "Menu_PS"
        case (.playStation, .options):
            return "Options_PS"
        case (.nintendoSwitch, .menu):
            return "Menu_Switch"
        case (.nintendoSwitch, .options):
            return "Options_Switch"
        case (_, .menu):
            return "Menu"
        case (_, .options):
            return "Options"
        case (_, .home):
            return nil
        }
    }
}

struct DetectedController: Equatable {
    var name: String
    var guideButtons: [ControllerGuideButton]
}

struct ControllerToggleBinding: Equatable {
    var button: ControllerAssignableButton

    static let `default` = ControllerToggleBinding(button: .west)

    func title(for style: ControllerGlyphStyle) -> String {
        "Guide + \(button.displayTitle(for: style))"
    }

    var title: String {
        title(for: .generic)
    }
}

enum ControllerAssignableButton: String, CaseIterable, Identifiable {
    case south
    case east
    case west
    case north
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case leftStickPress
    case rightStickPress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .south: return "A"
        case .east: return "B"
        case .west: return "X"
        case .north: return "Y"
        case .leftShoulder: return "Left Shoulder"
        case .rightShoulder: return "Right Shoulder"
        case .leftTrigger: return "Left Trigger"
        case .rightTrigger: return "Right Trigger"
        case .leftStickPress: return "Left Stick Press"
        case .rightStickPress: return "Right Stick Press"
        }
    }

    func displayTitle(for style: ControllerGlyphStyle) -> String {
        switch self {
        case .south:
            return style == .playStation ? "Cross Button" : "A Button"
        case .east:
            return style == .playStation ? "Circle Button" : "B Button"
        case .west:
            return style == .playStation ? "Square Button" : "X Button"
        case .north:
            return style == .playStation ? "Triangle Button" : "Y Button"
        case .leftShoulder:
            return "Left Shoulder"
        case .rightShoulder:
            return "Right Shoulder"
        case .leftTrigger:
            return "Left Trigger"
        case .rightTrigger:
            return "Right Trigger"
        case .leftStickPress:
            return "Left Stick Press"
        case .rightStickPress:
            return "Right Stick Press"
        }
    }

    var fallbackGlyphText: String {
        switch self {
        case .south: return "A"
        case .east: return "B"
        case .west: return "X"
        case .north: return "Y"
        case .leftShoulder: return "LB"
        case .rightShoulder: return "RB"
        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"
        case .leftStickPress: return "L3"
        case .rightStickPress: return "R3"
        }
    }

    func glyphAssetName(for style: ControllerGlyphStyle) -> String {
        switch self {
        case .south:
            return style == .playStation ? "A_PS" : "A"
        case .east:
            return style == .playStation ? "B_PS" : "B"
        case .west:
            return style == .playStation ? "X_PS" : "X"
        case .north:
            return style == .playStation ? "Y_PS" : "Y"
        case .leftShoulder:
            return style == .nintendoSwitch ? "LShoulder_Switch" : "LShoulder"
        case .rightShoulder:
            return style == .nintendoSwitch ? "RShoulder_Switch" : "RShoulder"
        case .leftTrigger:
            return style == .nintendoSwitch ? "LTrigger_Switch" : "LTrigger"
        case .rightTrigger:
            return style == .nintendoSwitch ? "RTrigger_Switch" : "RTrigger"
        case .leftStickPress:
            return "LStick_Press"
        case .rightStickPress:
            return "RStick_Press"
        }
    }
}

struct ControllerCaptureState: Equatable {
    var isGuidePressed = false
    var pressedButtons: Set<ControllerAssignableButton> = []

    static let empty = ControllerCaptureState()
}

enum ControllerActionBinding: String, CaseIterable, Identifiable {
    case acceptType
    case backspace
    case space
    case enter
    case shift
    case capsLock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acceptType: return "Accept/Type"
        case .backspace: return "Backspace"
        case .space: return "Space"
        case .enter: return "Enter"
        case .shift: return "Shift"
        case .capsLock: return "Caps Lock"
        }
    }
}

struct ControllerActionBindings: Equatable {
    var acceptType: ControllerAssignableButton
    var backspace: ControllerAssignableButton
    var space: ControllerAssignableButton
    var enter: ControllerAssignableButton
    var shift: ControllerAssignableButton
    var capsLock: ControllerAssignableButton

    static let `default` = ControllerActionBindings(
        acceptType: .south,
        backspace: .east,
        space: .north,
        enter: .west,
        shift: .leftStickPress,
        capsLock: .rightStickPress
    )

    func button(for action: ControllerActionBinding) -> ControllerAssignableButton {
        switch action {
        case .acceptType:
            return acceptType
        case .backspace:
            return backspace
        case .space:
            return space
        case .enter:
            return enter
        case .shift:
            return shift
        case .capsLock:
            return capsLock
        }
    }

    mutating func setButton(_ button: ControllerAssignableButton, for action: ControllerActionBinding) {
        switch action {
        case .acceptType:
            acceptType = button
        case .backspace:
            backspace = button
        case .space:
            space = button
        case .enter:
            enter = button
        case .shift:
            shift = button
        case .capsLock:
            capsLock = button
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var keyboardHotkey = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])
    @Published var controllerToggleBinding: ControllerToggleBinding = .default
    @Published var controllerActionBindings: ControllerActionBindings = .default
    @Published var shiftShortcutCyclesToCapsLock = true
    @Published var dismissWithGuideButton = true
    @Published var openAppOnStartup = false
    @Published var controllerGlyphStyle: ControllerGlyphStyle = .generic
    @Published var controllerCaptureState: ControllerCaptureState = .empty
    @Published var detectedController: DetectedController?
}
