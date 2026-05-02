import AppKit
import Combine
import Foundation

enum AxisInput: String, Identifiable {
    case leftStick
    case rightStick
    case pad
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .leftStick: return "Left Stick"
        case .rightStick: return "Right Stick"
        case .pad: return "D-pad"
        }
    }
}

enum AxisInputType: String, CaseIterable, Identifiable, Hashable {
    case none
    case overlayMovement
    case mouseMovement
    case arrowKeys
    
    static let keyboardOptions: [AxisInputType] = [.none, .overlayMovement, .arrowKeys]
    
    static let mouseOptions: [AxisInputType] = [.none, .mouseMovement]
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .none: return "None"
        case .overlayMovement: return "Control Keyboard"
        case .mouseMovement: return "Control Mouse"
        case .arrowKeys: return "Arrow Keys"
        }
    }
}

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
    case none

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
        case .none: return "Disabled"
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
        case .none:
            return "Disabled"
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
        case .none: return "nosign"
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
        case .none:
            return "nosign"
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
    case moveCaretLeft
    case moveCaretRight
    case mouseLeftClick
    case mouseRightClick
    case enlargeWindow
    case shrinkWindow

    static let keyboardActions: [ControllerActionBinding] = [.acceptType, .backspace, .space, .enter, .shift, .capsLock, .moveCaretLeft, .moveCaretRight, .shrinkWindow, .enlargeWindow]
    
    static let mouseActions: [ControllerActionBinding] = [.mouseLeftClick, .mouseRightClick]
    
    var id: String { rawValue }

    var title: String {
        switch self {
        case .acceptType: return "Accept/Type"
        case .backspace: return "Backspace"
        case .space: return "Space"
        case .enter: return "Enter"
        case .shift: return "Shift"
        case .capsLock: return "Caps Lock"
        case .moveCaretLeft: return "Move Text Cursor Left"
        case .moveCaretRight: return "Move Text Cursor Right"
        case .mouseLeftClick: return "Left Click"
        case .mouseRightClick: return "Right Click"
        case .enlargeWindow: return "Enlarge Keyboard"
        case.shrinkWindow: return "Shrink Keyboard"
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
    var moveCaretLeft: ControllerAssignableButton
    var moveCaretRight: ControllerAssignableButton
    var mouseLeftClick: ControllerAssignableButton
    var mouseRightClick: ControllerAssignableButton
    var enlargeWindow: ControllerAssignableButton
    var shrinkWindow: ControllerAssignableButton

    static let `default` = ControllerActionBindings(
        acceptType: .south,
        backspace: .east,
        space: .north,
        enter: .west,
        shift: .leftStickPress,
        capsLock: .rightStickPress,
        moveCaretLeft: .leftShoulder,
        moveCaretRight: .rightShoulder,
        mouseLeftClick: .leftTrigger,
        mouseRightClick: .rightTrigger,
        enlargeWindow: .none,
        shrinkWindow: .none
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
        case .moveCaretLeft:
            return moveCaretLeft
        case .moveCaretRight:
            return moveCaretRight
        case .mouseLeftClick:
            return mouseLeftClick
        case .mouseRightClick:
            return mouseRightClick
        case .enlargeWindow:
            return enlargeWindow
        case .shrinkWindow:
            return shrinkWindow
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
        case .moveCaretLeft:
            moveCaretLeft = button
        case .moveCaretRight:
            moveCaretRight = button
        case .mouseLeftClick:
            mouseLeftClick = button
        case .mouseRightClick:
            mouseRightClick = button
        case .enlargeWindow:
            enlargeWindow = button
        case .shrinkWindow:
            shrinkWindow = button
        }
    }
}

enum WindowSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case xLarge
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xLarge: return "Extra Large"
        }
    }
    
    var windowDimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small:
            return (800, 300)
        case .medium:
            return (1000, 375)
        case .large:
            return (1200, 450)
        case .xLarge:
            return (1440, 540)
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    // Onboarding
    @Published var restartedFromPermissionScreen = false
    
    // Bindings
    @Published var keyboardHotkey = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])
    @Published var controllerToggleBinding: ControllerToggleBinding = .default
    @Published var controllerActionBindings: ControllerActionBindings = .default
    
    // Preferences
    @Published var enableMouseInKeyboard: Bool = true
    @Published var prioritizeMouseOverKeyboard: Bool = true
    @Published var keyboardLayout: KeyboardLayout = .QWERTY
    @Published var leftStickInputType: [AxisInputType] = [.overlayMovement]
    @Published var rightStickInputType: [AxisInputType] = [.mouseMovement]
    @Published var padInputType: [AxisInputType] = [.overlayMovement]
    @Published var shiftShortcutCyclesToCapsLock = true
    @Published var dismissWithGuideButton = true
    @Published var openAppOnStartup = false
    @Published var keyboardMovementStyle: KeyboardMovementMode = .limited
    @Published var leftStickDeadzone: CGFloat = 0.4
    @Published var rightStickDeadzone: CGFloat = 0.4
    @Published var mouseSensitivity: CGFloat = 300.0
    @Published var mouseSmoothing: CGFloat = 0.5
    
    // Overlay
    @Published var inMouseMode: Bool = false
    @Published var windowSize: WindowSize = .small
    @Published var windowPosition: NSPoint = .zero
    
    // App state (Does not persist)
    @Published var controllerGlyphStyle: ControllerGlyphStyle = .generic
    @Published var controllerCaptureState: ControllerCaptureState = .empty
    @Published var detectedController: DetectedController?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        load()
        
        $restartedFromPermissionScreen
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $keyboardHotkey
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $controllerToggleBinding
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $controllerActionBindings
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $enableMouseInKeyboard
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $prioritizeMouseOverKeyboard
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $keyboardLayout
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $leftStickInputType
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $rightStickInputType
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $padInputType
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $shiftShortcutCyclesToCapsLock
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $dismissWithGuideButton
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $openAppOnStartup
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $keyboardMovementStyle
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $leftStickDeadzone
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $rightStickDeadzone
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $mouseSensitivity
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $mouseSmoothing
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $inMouseMode
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $windowSize
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        $windowPosition
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
        // The remaining variables doesn't persist/need to be saved
    }
    
    // MARK: - Save Code
    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ConType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }
    
    func save() {
        let codable = AppSettingsCodable(
            restartedFromPermissionScreen: restartedFromPermissionScreen,
            keyboardHotkey: keyboardHotkey,
            controllerToggleBinding: controllerToggleBinding,
            controllerActionBindings: controllerActionBindings,
            enableMouseInKeyboard: enableMouseInKeyboard,
            prioritizeMouseOverKeyboard: prioritizeMouseOverKeyboard,
            keyboardLayoutName: keyboardLayout.name,
            leftStickInputType: leftStickInputType,
            rightStickInputType: rightStickInputType,
            padInputType: padInputType,
            shiftShortcutCyclesToCapsLock: shiftShortcutCyclesToCapsLock,
            dismissWithGuideButton: dismissWithGuideButton,
            openAppOnStartup: openAppOnStartup,
            keyboardMovementStyle: keyboardMovementStyle,
            leftStickDeadzone: leftStickDeadzone,
            rightStickDeadzone: rightStickDeadzone,
            mouseSensitivity: mouseSensitivity,
            mouseSmoothing: mouseSmoothing,
            inMouseMode: inMouseMode,
            windowSize: windowSize,
            windowPosition: CodablePoint(windowPosition)
        )
        do {
            debugPrint("[AppSettings] Saving app settings to file...")
            let data = try JSONEncoder().encode(codable)
            try data.write(to: Self.settingsURL, options: [.atomic])
        } catch {
            debugPrint("[AppSettings] Failed to save settings: \(error)")
        }
    }
    
    func load() {
        let url = Self.settingsURL
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            debugPrint("[AppSettings] Restoring app settings from file...")
            let codable = try JSONDecoder().decode(AppSettingsCodable.self, from: data)
            self.restartedFromPermissionScreen = codable.restartedFromPermissionScreen
            self.keyboardHotkey = codable.keyboardHotkey
            self.controllerToggleBinding = codable.controllerToggleBinding
            self.controllerActionBindings = codable.controllerActionBindings
            self.enableMouseInKeyboard = codable.enableMouseInKeyboard
            self.prioritizeMouseOverKeyboard = codable.prioritizeMouseOverKeyboard
            
            // Restore layout by name
            if let layout = KeyboardLayout.all.first(where: { $0.name == codable.keyboardLayoutName }) {
                self.keyboardLayout = layout
            }
            
            self.leftStickInputType = codable.leftStickInputType
            self.rightStickInputType = codable.rightStickInputType
            self.padInputType = codable.padInputType
            self.shiftShortcutCyclesToCapsLock = codable.shiftShortcutCyclesToCapsLock
            self.dismissWithGuideButton = codable.dismissWithGuideButton
            self.openAppOnStartup = codable.openAppOnStartup
            self.keyboardMovementStyle = codable.keyboardMovementStyle
            self.leftStickDeadzone = codable.leftStickDeadzone
            self.rightStickDeadzone = codable.rightStickDeadzone
            self.mouseSensitivity = codable.mouseSensitivity
            self.mouseSmoothing = codable.mouseSmoothing
            self.inMouseMode = codable.inMouseMode
            self.windowSize = codable.windowSize
            self.windowPosition = codable.windowPosition.nsPoint
        } catch {
            debugPrint("[AppSettings] Failed to load settings: \(error)")
        }
    }
}

// MARK: - Codable helpers
extension KeyboardHotkeyManager.Shortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        let modifiersRaw = try container.decode(UInt.self, forKey: .modifiers)
        self.init(key: key, modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw))
    }
}
extension ControllerToggleBinding: Codable {}
extension ControllerActionBindings: Codable {}
extension ControllerAssignableButton: Codable {}
extension ControllerActionBinding: Codable {}
extension AxisInputType: Codable {}
extension WindowSize: Codable {
    enum CodingKeys: String, CodingKey {
        case value
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .small: try container.encode("small", forKey: .value)
        case .medium: try container.encode("medium", forKey: .value)
        case .large: try container.encode("large", forKey: .value)
        case .xLarge: try container.encode("xLarge", forKey: .value)
        }
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch value {
        case "small": self = .small
        case "medium": self = .medium
        case "large": self = .large
        default: self = .small
        }
    }
}
extension KeyboardMovementMode: Codable {
    enum CodingKeys: String, CodingKey { case value }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .limited: try container.encode("limited", forKey: .value)
        case .full: try container.encode("full", forKey: .value)
        case .mouse: try container.encode("mouse", forKey: .value)
        }
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch value {
        case "limited": self = .limited
        case "full": self = .full
        case "mouse": self = .mouse
        default: self = .limited
        }
    }
}

struct CodablePoint: Codable {
    var x: CGFloat
    var y: CGFloat
    
    init(_ point: NSPoint) {
        self.x = point.x
        self.y = point.y
    }
    var nsPoint: NSPoint { NSPoint(x: x, y: y) }
}

private struct AppSettingsCodable: Codable {
    var restartedFromPermissionScreen: Bool
    var keyboardHotkey: KeyboardHotkeyManager.Shortcut
    var controllerToggleBinding: ControllerToggleBinding
    var controllerActionBindings: ControllerActionBindings
    var enableMouseInKeyboard: Bool
    var prioritizeMouseOverKeyboard: Bool
    var keyboardLayoutName: String
    var leftStickInputType: [AxisInputType]
    var rightStickInputType: [AxisInputType]
    var padInputType: [AxisInputType]
    var shiftShortcutCyclesToCapsLock: Bool
    var dismissWithGuideButton: Bool
    var openAppOnStartup: Bool
    var keyboardMovementStyle: KeyboardMovementMode
    var leftStickDeadzone: CGFloat
    var rightStickDeadzone: CGFloat
    var mouseSensitivity: CGFloat
    var mouseSmoothing: CGFloat
    var inMouseMode: Bool
    var windowSize: WindowSize
    var windowPosition: CodablePoint
}
