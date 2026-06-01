//
//  AppSettings.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import AppKit
import Combine
import Foundation

/// An enum representing the different visual styles for controller glyphs.
/// Contains:
/// - Generic (Xbox-style)
/// - PlayStation
/// - Nintendo Switch
enum ControllerGlyphStyle: Equatable {
    case generic
    case playStation
    case nintendoSwitch
    
    
    /// Detects the appropriate controller glyph style based on the provided vendor name and product category.
    /// - Parameters:
    ///   - vendorName: The vendor name of the controller, typically provided by the system's device information.
    ///   - productCategory: The product category of the controller, which may include additional details about the controller model or type.
    /// - Returns: A `ControllerGlyphStyle` that best matches the provided information, allowing the app to display the correct button icons for the detected controller.
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
    
    /// The name of the asset to use for the guide button based on the glyph style.
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

/// An enum representing the guide buttons on a controller.
/// Contains:
/// - Menu
/// - Home
/// - Options
enum ControllerGuideButton: String, CaseIterable, Equatable {
    case menu
    case home
    case options
    
    /// Returns the display title for the guide button based on the controller glyph style.
    /// - Parameter style: The `ControllerGlyphStyle` to determine the appropriate title for the button.
    /// - Returns: A `String` representing the display title for the guide button, which may vary based on the controller type (e.g., "+" for Nintendo Switch menu button, "PS" for PlayStation home button).
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
    
    /// The name of the asset to use for the guide button based on the glyph style and button type.
    /// - Parameter style: The `ControllerGlyphStyle` to determine the appropriate asset name for the button.
    /// - Returns: An optional `String` representing the name of the asset to use for the guide button. Returns `nil` if there is no specific asset for the given style and button combination (e.g., no unique asset for the home button on non-PlayStation controllers).
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

/// A struct representing a detected controller, including its name and the guide buttons it has.
struct DetectedController: Equatable {
    var name: String
    var guideButtons: [ControllerGuideButton]
}

/// An enum representing the different types of input that can be mapped to controller axes.
/// Contains:
/// - Left Stick
/// - Right Stick
/// - D-pad
enum AxisInput: String, Identifiable {
    case leftStick
    case rightStick
    case pad
    
    /// Axis input identifier.
    var id: String { rawValue }
    
    /// Human readable title for the axis input.
    var title: String {
        switch self {
        case .leftStick: return "Left Stick"
        case .rightStick: return "Right Stick"
        case .pad: return "D-pad"
        }
    }
    
    /// The fallback text to be used when the glyph asset for the button is not available.
    var fallbackText: String {
        switch self {
        case .leftStick: return "Left Stick"
        case .rightStick: return "Right Stick"
        case .pad: return "D-pad"
        }
    }
    
    /// The asset name for the given axis input.
    var glyphAssetName: String {
        switch self {
        case .leftStick: return "LS"
        case .rightStick: return "RS"
        case .pad: return "DPad"
        }
    }
}

/// Selects which controller input backend to use for controller event sourcing.
enum ControllerInputBackendMode: String, CaseIterable, Identifiable, Codable {
    case gameController
    case hybridIOHID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gameController:
            return "GameController"
        case .hybridIOHID:
            return "Hybrid IOHID"
        }
    }
}

/// An enum representing the different actions an axis input can do
/// Contains:
/// - Control Overlay Movement
/// - Control Mouse Movement
/// - Arrow Keys
/// - Scroll Wheel
/// - None
enum AxisActionType: String, CaseIterable, Identifiable, Hashable {
    case none
    case overlayMovement
    case mouseMovement
    case arrowKeys
    case scrollWheel
    
    /// The keyboard axis actions
    static let keyboardOptions: [AxisActionType] = [.none, .overlayMovement, .arrowKeys]
    
    /// The mouse axis actions
    static let mouseOptions: [AxisActionType] = [.none, .mouseMovement, .scrollWheel]
    
    /// Axis action identifier
    var id: String { rawValue }
    
    /// Human readable title for the axis action
    var title: String {
        switch self {
        case .none: return "None"
        case .overlayMovement: return "Control Keyboard"
        case .mouseMovement: return "Control Mouse"
        case .arrowKeys: return "Arrow Keys"
        case .scrollWheel: return "Scroll Wheel"
        }
    }
}

/// An enum representing the different controller toggle bindings that can be configured in the app.
/// Contains:
/// - Keyboard Toggle (Guide Button + a face button to toggle keyboard overlay)
/// - Mouse Toggle (Guide Button + a face button to toggle mouse mode)
enum ControllerToggleBinding: String, CaseIterable, Identifiable {
    case keyboardToggle
    case mouseToggle
    
    /// Toggle identifier.
    var id: String { rawValue }
    
    /// A human-readable title for the toggle binding.
    var title: String {
        switch self {
        case .keyboardToggle: return "Keyboard Toggle"
        case .mouseToggle: return "Mouse Toggle"
        }
    }
    
    /// Returns a string for the toggle binding containing the set shortcut.
    /// - Parameters:
    ///   - binding: A `ControllerAssignableButton` representing the controller button that is combined with the guide button to perform the toggle action.
    ///   - style: The `ControllerGlyphStyle` to determine how the button should be displayed in the string.
    /// - Returns: A `String` that describes the toggle binding, formatted as "Guide + [Button Name]".
    func glyphName(_ binding: ControllerAssignableButton, for style: ControllerGlyphStyle) -> String {
        "Guide + \(binding.displayTitle(for: style))"
    }
}

/// A struct representing the controller toggle bindings for both keyboard and mouse modes.
struct ControllerToggleBindings: Equatable {
    var keyboardToggle: ControllerAssignableButton
    var mouseToggle: ControllerAssignableButton
    
    /// The default toggle bindings, which can be used to reset to defaults or as initial values when the app is first installed.
    static let `default` = ControllerToggleBindings(
        keyboardToggle: .west,
        mouseToggle: .north
    )
    
    /// Returns the toggle binding for a given `ControllerToggleBinding` type (keyboard or mouse).
    /// - Parameter shortcut: The `ControllerToggleBinding` type for which to retrieve the binding (either `.keyboardToggle` or `.mouseToggle`).
    /// - Returns: A `ControllerAssignableButton` representing the button that is currently set for the specified toggle binding type.
    func binding(for shortcut: ControllerToggleBinding) -> ControllerAssignableButton {
        switch shortcut {
        case .keyboardToggle:
            return keyboardToggle
        case .mouseToggle:
            return mouseToggle
        }
    }
    
    /// Sets the toggle binding for a given `ControllerToggleBinding` type (keyboard or mouse).
    /// - Parameters:
    ///  - binding: A `ControllerAssignableButton` representing the button to set for the toggle action.
    ///  - shortcut: The `ControllerToggleBinding` type for which to set the binding (either `.keyboardToggle` or `.mouseToggle`).
    mutating func setBinding(_ binding: ControllerAssignableButton, for shortcut: ControllerToggleBinding) {
        switch shortcut {
        case .keyboardToggle:
            keyboardToggle = binding
        case .mouseToggle:
            mouseToggle = binding
        }
    }
    
    /// Returns a string describing the shortcut for a given `ControllerToggleBinding` type, formatted as "Guide + [Button Name]".
    /// - Parameters:
    ///  - shortcut: The `ControllerToggleBinding` type for which to generate the shortcut text (either `.keyboardToggle` or `.mouseToggle`).
    ///  - style: The `ControllerGlyphStyle` to determine how the button should be displayed in the string.
    ///  - Returns: A `String` that describes the shortcut for the specified toggle binding type, formatted as "Guide + [Button Name]".
    func shortcutText(for shortcut: ControllerToggleBinding, style: ControllerGlyphStyle) -> String {
        let binding = binding(for: shortcut)
        return "Guide + \(binding.displayTitle(for: style))"
    }
}

/// An enum representing the buttons on a controller that can be assigned to actions in the app.
/// Contains:
/// - South (The ABXY/Shapes face button)
/// - Eas (The ABXY/Shapes face button)
/// - West (The ABXY/Shapes face button)
/// - North (The ABXY/Shapes face button)
/// - Left Shoulder
/// - Right Shoulder
/// - Left Trigger
/// - Right Trigger
/// - Left Stick Press
/// - Right Stick Press
/// - None
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
    
    /// Button identifier.
    var id: String { rawValue }
    
    /// A human-readable title for the button.
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
    
    /// Returns a display title for the button based on the controller glyph style.
    /// - Parameter style: The `ControllerGlyphStyle` to determine how the button should be displayed in the title.
    /// - Returns: A `String` representing the display title for the button, which may vary based on the controller type.
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
    
    /// The fallback text to be used when the glyph asset for the button is not available.
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
    
    /// Returns the name of the asset to use for the button based on the controller glyph style.
    /// - Parameter style: The `ControllerGlyphStyle` to determine the appropriate asset name for the button.
    /// - Returns: A `String` representing the name of the asset to use for the button, which may vary based on the controller type.
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

/// A struct representing the current state of controller input capture, including which buttons are currently pressed and whether the guide button is pressed.
struct ControllerCaptureState: Equatable {
    var isGuidePressed = false
    var pressedButtons: Set<ControllerAssignableButton> = []
    
    /// An empty capture state with no buttons pressed and the guide button not pressed.
    static let empty = ControllerCaptureState()
}

/// An enum representing the different controller action bindings that can be configured in the app.
/// Contains:
/// - Accept
/// - Backspace
/// - Space
/// - Enter
/// - Shift
/// - Caps Lock
/// - Move Caret Left
/// - Move Caret Right
/// - Mouse Left Click
/// - Mouse Right Click
/// - Enlarge Overlay
/// - Shrink Overlay
enum ControllerActionBinding: String, CaseIterable, Identifiable {
    case accept
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
    
    /// The controller action bindings related to overlay controls.
    static let overlayActions: [ControllerActionBinding] = [.shrinkWindow, .enlargeWindow]
    
    /// The controller action bindings related to keyboard input.
    static let keyboardActions: [ControllerActionBinding] = [.accept, .backspace, .space, .enter, .shift, .capsLock, .moveCaretLeft, .moveCaretRight]
    
    /// The controller action bindings related to mouse input.
    static let mouseActions: [ControllerActionBinding] = [.mouseLeftClick, .mouseRightClick]
    
    /// Controller action identifier.
    var id: String { rawValue }
    
    /// A human-readable title for the controller action binding.
    var title: String {
        switch self {
        case .accept: return "Accept"
        case .backspace: return "Backspace"
        case .space: return "Space"
        case .enter: return "Enter"
        case .shift: return "Shift"
        case .capsLock: return "Caps Lock"
        case .moveCaretLeft: return "Move Text Cursor Left"
        case .moveCaretRight: return "Move Text Cursor Right"
        case .mouseLeftClick: return "Left Click"
        case .mouseRightClick: return "Right Click"
        case .enlargeWindow: return "Enlarge Overlay"
        case .shrinkWindow: return "Shrink Overlay"
        }
    }
}

/// A struct representing the controller action bindings for various actions in the app.
struct ControllerActionBindings: Equatable {
    var accept: ControllerAssignableButton
    var backspace: ControllerAssignableButton
    var space: ControllerAssignableButton
    var enter: ControllerAssignableButton
    var shift: ControllerAssignableButton
    var capsLock: ControllerAssignableButton
    var moveCaretLeft: ControllerAssignableButton
    var moveCaretRight: ControllerAssignableButton
    var mouseLeftClick: ControllerAssignableButton
    var mouseRightClick: ControllerAssignableButton
    var shrinkWindow: ControllerAssignableButton
    var enlargeWindow: ControllerAssignableButton
    
    /// The default action bindings.
    static let `default` = ControllerActionBindings(
        // Keyboard Controls
        accept: .south,
        backspace: .east,
        space: .north,
        enter: .west,
        shift: .leftStickPress,
        capsLock: .rightStickPress,
        moveCaretLeft: .leftShoulder,
        moveCaretRight: .rightShoulder,
        
        // Mouse Controls
        mouseLeftClick: .leftShoulder,
        mouseRightClick: .rightShoulder,
        
        // Overlay Controls
        shrinkWindow: .leftTrigger,
        enlargeWindow: .rightTrigger
    )
    
    /// Returns the button binding for a given `ControllerActionBinding`.
    /// - Parameter action: The `ControllerActionBinding` for which to retrieve the button binding.
    /// - Returns: A `ControllerAssignableButton` representing the button that is currently set for the specified action binding.
    func button(for action: ControllerActionBinding) -> ControllerAssignableButton {
        switch action {
        case .accept:
            return accept
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
        case .shrinkWindow:
            return shrinkWindow
        case .enlargeWindow:
            return enlargeWindow
        }
    }
    
    /// Sets the button bidning for a given `ControllerActionBinding`.
    /// - Parameters:
    ///     - button: A `ControllerAssignableButton` representing the button to set for the action.
    ///     - action: The `ControllerActionBinding` for which to set the button binding
    mutating func setButton(_ button: ControllerAssignableButton, for action: ControllerActionBinding) {
        switch action {
        case .accept:
            accept = button
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

/// An enum representing the different preset window sizes for the keyboard overlay.
/// Contains:
/// - Small
/// - Medium
/// - Large
/// - Extra Large
/// - Custom
enum WindowSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case xLarge
    case custom
    
    /// Window size identifier
    var id: String { rawValue }
    
    /// A human-readable name for the window size.
    var name: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xLarge: return "Extra Large"
        case .custom: return "Custom"
        }
    }
    
    /// A boolean value indicating whether the window size is set to custom.
    var isCustom: Bool {
        self == .custom
    }
    
    /// A static array of the preset window sizes that can be selected by the user, excluding the custom option.
    static let selectableCases: [WindowSize] = [.small, .medium, .large, .xLarge]
    
    /// Returns the dimensions for the window size.
    func windowDimensions(customSize: NSSize? = nil) -> NSSize {
        switch self {
        case .small:
            return NSSize(width: 800, height: 300)
        case .medium:
            return NSSize(width: 1000, height: 375)
        case .large:
            return NSSize(width: 1200, height: 450)
        case .xLarge:
            return NSSize(width: 1440, height: 540)
        case .custom:
            return customSize ?? NSSize(width: 1000, height: 375)
        }
    }
    
    /// Returns the next larger preset window size. If the current size is custom, it will determine the next largest preset size based on the provided custom dimensions.
    /// - Parameter customSize: An optional `NSSize` representing the custom dimensions to use
    /// - Returns: A `WindowSize` representing the next larger preset size.
    func largerPreset(using customSize: NSSize? = nil) -> WindowSize {
        switch self {
        case .small:
            return .medium
        case .medium:
            return .large
        case .large:
            return .xLarge
        case .xLarge:
            return .xLarge
        case .custom:
            let dimensions = customSize ?? windowDimensions(customSize: customSize)
            let currentIndex = Self.presetIndex(for: dimensions)
            return Self.selectableCases[min(currentIndex + 1, Self.selectableCases.count - 1)]
        }
    }
    
    /// Returns the next smaller preset window size. If the current size is custom, it will determine the next smallest preset size based on the provided custom dimensions.
    /// - Parameter customSize: An optional `NSSize` representing the custom dimensions to use
    /// - Returns: A `WindowSize` representing the next smaller preset size.
    func smallerPreset(using customSize: NSSize? = nil) -> WindowSize {
        switch self {
        case .small:
            return .small
        case .medium:
            return .small
        case .large:
            return .medium
        case .xLarge:
            return .large
        case .custom:
            let dimensions = customSize ?? windowDimensions(customSize: customSize)
            let currentIndex = Self.presetIndex(for: dimensions)
            return Self.selectableCases[currentIndex]
        }
    }
    
    /// Returns the appropriate preset window size for the given dimensions.
    /// - Parameter dimensions: An `NSSize` representing the dimensions for which to determine the preset window size.
    /// - Returns: A `WindowSize` representing the preset size that best matches the provided dimensions.
    static func preset(for dimensions: NSSize) -> WindowSize {
        let index = presetIndex(for: dimensions)
        return selectableCases[index]
    }
    
    /// Determines the index of the preset window size that best matches the provided dimensions.
    /// - Parameter dimensions: An `NSSize` representing the dimensions for which to determine the preset index.
    /// - Returns: An `Int` representing the index of the preset window size that best matches the provided dimensions.
    private static func presetIndex(for dimensions: NSSize) -> Int {
        let widths = selectableCases.map { $0.windowDimensions().width }
        var currentIndex = 0
        
        for (index, width) in widths.enumerated() {
            if dimensions.width >= width {
                currentIndex = index
            }
        }
        
        return currentIndex
    }
}

/// Class representing the app settings, which are persisted across app launches and can be observed for changes.
@MainActor
final class AppSettings: ObservableObject {
    /// Test seam that allows the settings file location to be redirected.
    static var settingsURLOverride: URL?
    
    // MARK: - Onboarding
    /// Utilized to determine if the app was restarted from the permission screen during onboarding. Utilized when restarting the app to refresh permission.
    @Published var restartedFromPermissionScreen = false
    
    
    // MARK: - Bindings
    /// The keyboard shortcut used to toggle the keyboard overlay. By default, it is set to Command + K.
    @Published var keyboardHotkey = Shortcut(key: "k", modifiers: [.command])
    
    /// The controller button bindings for toggling the keyboard overlay and mouse mode, which can be customized by the user.
    @Published var controllerToggleBindings: ControllerToggleBindings = .default
    
    /// The controller button bindings for various actions in the app.
    @Published var controllerActionBindings: ControllerActionBindings = .default
    
    
    // MARK: - Preferences
    /// A boolean value indicating whether mouse input is enabled while the keyboard overlay is active.
    @Published var enableMouseInKeyboard: Bool = true
    
    /// A boolean value indicating whether mouse input should be prioritized over keyboard input when both are enabled.
    @Published var prioritizeMouseOverKeyboard: Bool = false
    
    /// The layout of the keyboard to be used in the overlay, which can affect how certain keys are displayed and mapped.
    @Published var keyboardLayout: KeyboardLayout = .QWERTY
    
    /// The axis action assigned to the left stick.
    @Published var leftStickInputType: [AxisActionType] = [.overlayMovement, .scrollWheel]
    
    /// The axis action assigned to the right stick.
    @Published var rightStickInputType: [AxisActionType] = [.mouseMovement]
    
    /// The axis action assigned to the D-pad.
    @Published var padInputType: [AxisActionType] = [.overlayMovement]
    
    /// A boolean value indicating whether the Shift action binding should toggle between Shift, Caps Lock and Regular. If false, the Shift action binding will only toggle the Shift key.
    @Published var shiftShortcutCyclesToCapsLock = true
    
    /// A boolean value indicating whether the keyboard overlay can be dismissed by pressing the guide button alone.
    @Published var dismissWithGuideButton = true

    /// The controller input backend to use for sourcing controller events.
    @Published var controllerInputBackendMode: ControllerInputBackendMode = .hybridIOHID
    
    /// A boolean value indicating whether the app should open automatically on startup.
    @Published var openAppOnStartup = false
    
    /// The movement style for the keyboard overlay when controlled by the controller.
    @Published var keyboardMovementStyle: KeyboardMovementMode = .limited
    
    /// The deadzone for the left stick.
    @Published var leftStickDeadzone: CGFloat = 0.4
    
    /// The deadzone for the right stick.
    @Published var rightStickDeadzone: CGFloat = 0.4
    
    /// The distance the mouse moves in response to controller input.
    @Published var mouseSensitivity: CGFloat = 300.0
    
    /// The smoothing alpha value for mouse movement.
    @Published var mouseSmoothing: CGFloat = 0.4
    
    /// A boolean value indicating whether the X-axis mouse movement is inverted.
    @Published var invertMouseX: Bool = false
    
    /// A boolean value indicating whether the Y-axis mouse movement is inverted.
    @Published var invertMouseY: Bool = false
    
    /// The distance the mouse scrolls in response to controller input.
    @Published var scrollSpeed: CGFloat = 300.0
    
    /// A boolean value indicating whether the X-axis mouse scroll is inverted.
    @Published var invertScrollX: Bool = false
    
    /// A boolean value indicating whether the Y-axis mouse scroll is inverted.
    @Published var invertScrollY: Bool = false
    
    /// A boolean value indicating whether haptic feedback is enabled for controller input.
    @Published var enableHaptics: Bool = true
    
    
    // MARK: - Overlay
    /// A boolean value indicating wether the app is in the mouse overlay.
    @Published var inMouseMode: Bool = false
    
    /// A boolean value indicating whether the guide bar is shown on the keyboard overlay.
    @Published var showGuideBar: Bool = true
    
    /// The preset window size for the keyboard overlay.
    @Published var keyboardWindowSize: WindowSize = .small
    
    /// The custom dimensions for the keyboard overlay, used when the `keyboardWindowSize` is set to `.custom`.
    @Published var keyboardCustomDimensions: NSSize = WindowSize.medium.windowDimensions()
    
    /// The position of the keyboard overlay window on the screen.
    @Published var keyboardWindowPosition: NSPoint = .zero
    
    /// The position of the mouse overlay window on the screen.
    @Published var mouseWindowPosition: NSPoint = .zero
    
    // MARK: - App state (Does not persist)
    /// The visual style for controller glyphs, which can be automatically detected based on the connected controller.
    @Published var controllerGlyphStyle: ControllerGlyphStyle = .generic
    
    /// The current state of controller input capture, including which buttons are currently pressed and whether the guide button is pressed.
    @Published var controllerCaptureState: ControllerCaptureState = .empty
    
    /// The currently detected controller, including its name and the guide buttons it has.
    @Published var detectedController: DetectedController?
    
    
    /// A set of cancellables for managing Combine subscriptions related to saving settings when they change.
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        load()
        
        let saveTriggers: [AnyPublisher<Void, Never>] = [
            $restartedFromPermissionScreen.map { _ in () }.eraseToAnyPublisher(),
            $keyboardHotkey.map { _ in () }.eraseToAnyPublisher(),
            $controllerToggleBindings.map { _ in () }.eraseToAnyPublisher(),
            $controllerActionBindings.map { _ in () }.eraseToAnyPublisher(),
            $enableMouseInKeyboard.map { _ in () }.eraseToAnyPublisher(),
            $prioritizeMouseOverKeyboard.map { _ in () }.eraseToAnyPublisher(),
            $keyboardLayout.map { _ in () }.eraseToAnyPublisher(),
            $leftStickInputType.map { _ in () }.eraseToAnyPublisher(),
            $rightStickInputType.map { _ in () }.eraseToAnyPublisher(),
            $padInputType.map { _ in () }.eraseToAnyPublisher(),
            $shiftShortcutCyclesToCapsLock.map { _ in () }.eraseToAnyPublisher(),
            $dismissWithGuideButton.map { _ in () }.eraseToAnyPublisher(),
            $controllerInputBackendMode.map { _ in () }.eraseToAnyPublisher(),
            $openAppOnStartup.map { _ in () }.eraseToAnyPublisher(),
            $keyboardMovementStyle.map { _ in () }.eraseToAnyPublisher(),
            $leftStickDeadzone.map { _ in () }.eraseToAnyPublisher(),
            $rightStickDeadzone.map { _ in () }.eraseToAnyPublisher(),
            $mouseSensitivity.map { _ in () }.eraseToAnyPublisher(),
            $mouseSmoothing.map { _ in () }.eraseToAnyPublisher(),
            $invertMouseX.map { _ in () }.eraseToAnyPublisher(),
            $invertMouseY.map { _ in () }.eraseToAnyPublisher(),
            $scrollSpeed.map { _ in () }.eraseToAnyPublisher(),
            $invertScrollX.map { _ in () }.eraseToAnyPublisher(),
            $invertScrollY.map { _ in () }.eraseToAnyPublisher(),
            $enableHaptics.map { _ in () }.eraseToAnyPublisher(),
            $inMouseMode.map { _ in () }.eraseToAnyPublisher(),
            $showGuideBar.map { _ in () }.eraseToAnyPublisher(),
            $keyboardWindowSize.map { _ in () }.eraseToAnyPublisher(),
            $keyboardCustomDimensions.map { _ in () }.eraseToAnyPublisher(),
            $keyboardWindowPosition.map { _ in () }.eraseToAnyPublisher(),
            $mouseWindowPosition.map { _ in () }.eraseToAnyPublisher()
        ]
        
        Publishers.MergeMany(saveTriggers)
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(75), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.save()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Save Code
    /// A private static property that returns the URL for the settings file where the app settings are persisted.
    private static var settingsURL: URL {
        if let override = settingsURLOverride {
            return override
        }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ConType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }
    
    /// Saves the current app settings to a JSON file in the Application Support directory. The settings are encoded using `JSONEncoder` and written to the file specified by `settingsURL`.
    func save() {
        let codable = AppSettingsCodable(
            restartedFromPermissionScreen: restartedFromPermissionScreen,
            keyboardHotkey: keyboardHotkey,
            controllerToggleBindings: controllerToggleBindings,
            controllerActionBindings: controllerActionBindings,
            enableMouseInKeyboard: enableMouseInKeyboard,
            prioritizeMouseOverKeyboard: prioritizeMouseOverKeyboard,
            keyboardLayoutName: keyboardLayout.name,
            leftStickInputType: leftStickInputType,
            rightStickInputType: rightStickInputType,
            padInputType: padInputType,
            shiftShortcutCyclesToCapsLock: shiftShortcutCyclesToCapsLock,
            dismissWithGuideButton: dismissWithGuideButton,
            controllerInputBackendMode: controllerInputBackendMode,
            openAppOnStartup: openAppOnStartup,
            keyboardMovementStyle: keyboardMovementStyle,
            leftStickDeadzone: leftStickDeadzone,
            rightStickDeadzone: rightStickDeadzone,
            mouseSensitivity: mouseSensitivity,
            mouseSmoothing: mouseSmoothing,
            invertMouseX: invertMouseX,
            invertMouseY: invertMouseY,
            scrollSpeed: scrollSpeed,
            invertScrollX: invertScrollX,
            invertScrollY: invertScrollY,
            enableHaptics: enableHaptics,
            inMouseMode: inMouseMode,
            showGuideBar: showGuideBar,
            keyboardWindowSize: keyboardWindowSize,
            keyboardCustomDimensions: CodableSize(keyboardCustomDimensions),
            keyboardWindowPosition: CodablePoint(keyboardWindowPosition),
            mouseWindowPosition: CodablePoint(mouseWindowPosition)
        )
        do {
            let data = try JSONEncoder().encode(codable)
            try data.write(to: Self.settingsURL, options: [.atomic])
        } catch {
            debugPrint("[AppSettings] Failed to save settings: \(error)")
        }
    }
    
    /// Loads the app settings from a JSON file in the Application Support directory. The settings are decoded using `JSONDecoder` and applied to the corresponding properties in the `AppSettings` class.
    func load() {
        let url = Self.settingsURL
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let codable = try JSONDecoder().decode(AppSettingsCodable.self, from: data)
            self.restartedFromPermissionScreen = codable.restartedFromPermissionScreen
            self.keyboardHotkey = codable.keyboardHotkey
            self.controllerToggleBindings = codable.controllerToggleBindings
            self.controllerActionBindings = codable.controllerActionBindings
            self.enableMouseInKeyboard = codable.enableMouseInKeyboard
            self.prioritizeMouseOverKeyboard = codable.prioritizeMouseOverKeyboard
            
            /// Restore layout by name
            if let layout = KeyboardLayout.all.first(where: { $0.name == codable.keyboardLayoutName }) {
                self.keyboardLayout = layout
            }
            
            self.leftStickInputType = codable.leftStickInputType
            self.rightStickInputType = codable.rightStickInputType
            self.padInputType = codable.padInputType
            self.shiftShortcutCyclesToCapsLock = codable.shiftShortcutCyclesToCapsLock
            self.dismissWithGuideButton = codable.dismissWithGuideButton
            self.controllerInputBackendMode = codable.controllerInputBackendMode ?? .gameController
            self.openAppOnStartup = codable.openAppOnStartup
            self.keyboardMovementStyle = codable.keyboardMovementStyle
            self.leftStickDeadzone = codable.leftStickDeadzone
            self.rightStickDeadzone = codable.rightStickDeadzone
            self.mouseSensitivity = codable.mouseSensitivity
            self.mouseSmoothing = codable.mouseSmoothing
            self.invertMouseX = codable.invertMouseX
            self.invertMouseY = codable.invertMouseY
            self.scrollSpeed = codable.scrollSpeed
            self.invertScrollX = codable.invertScrollX
            self.invertScrollY = codable.invertScrollY
            self.enableHaptics = codable.enableHaptics
            self.inMouseMode = codable.inMouseMode
            self.showGuideBar = codable.showGuideBar
            self.keyboardWindowSize = codable.keyboardWindowSize
            if let keyboardCustomDimensions = codable.keyboardCustomDimensions?.nsSize {
                self.keyboardCustomDimensions = keyboardCustomDimensions
            }
            self.keyboardWindowPosition = codable.keyboardWindowPosition.nsPoint
            self.mouseWindowPosition = codable.mouseWindowPosition.nsPoint
        } catch {
            debugPrint("[AppSettings] Failed to load settings: \(error)")
        }
    }
    
    /// Restores the default settings for the app.
    /// - Parameter onlyHotkeys: Wether to only restore hotkey and controller bindings defaults, or to restore all defaults including preferences and overlay settings.
    func restoreDefaults(onlyHotkeys: Bool) {
        if onlyHotkeys {
            self.keyboardHotkey = Shortcut(key: "k", modifiers: [.command])
            self.controllerToggleBindings = .default
            self.controllerActionBindings = .default
            return
        } else {
            self.restartedFromPermissionScreen = false
            self.keyboardHotkey = Shortcut(key: "k", modifiers: [.command])
            self.controllerToggleBindings = .default
            self.controllerActionBindings = .default
            self.enableMouseInKeyboard = true
            self.prioritizeMouseOverKeyboard = false
            self.keyboardLayout = .QWERTY
            self.leftStickInputType = [.overlayMovement, .scrollWheel]
            self.rightStickInputType = [.mouseMovement]
            self.padInputType = [.overlayMovement]
            self.shiftShortcutCyclesToCapsLock = true
            self.dismissWithGuideButton = true
            self.controllerInputBackendMode = .gameController
            self.keyboardMovementStyle = .limited
            self.leftStickDeadzone = 0.4
            self.rightStickDeadzone = 0.4
            self.mouseSensitivity = 300.0
            self.mouseSmoothing = 0.4
            self.invertMouseX = false
            self.invertMouseY = false
            self.scrollSpeed = 600.0
            self.invertScrollX = false
            self.invertScrollY = false
            self.enableHaptics = true
            self.inMouseMode = false
            self.showGuideBar = true
            self.keyboardWindowSize = .small
            self.keyboardCustomDimensions = WindowSize.medium.windowDimensions()
            self.keyboardWindowPosition = .zero
            self.mouseWindowPosition = .zero
            return
        }
    }
}

// MARK: - Codable helpers
extension Shortcut: Codable {
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

extension ControllerToggleBindings: Codable {}

extension ControllerActionBindings: Codable {}

extension ControllerAssignableButton: Codable {}

extension ControllerActionBinding: Codable {}

extension AxisActionType: Codable {}

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
        case .custom: try container.encode("custom", forKey: .value)
        }
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch value {
        case "small": self = .small
        case "medium": self = .medium
        case "large": self = .large
        case "xLarge": self = .xLarge
        case "custom": self = .custom
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

/// A struct used for encoding and decoding `NSPoint` values in the `AppSettingsCodable` struct. Since `NSPoint` does not conform to `Codable`, this struct provides a way to represent point values in a codable format, allowing them to be easily saved and loaded as part of the app settings.
struct CodablePoint: Codable {
    var x: CGFloat
    var y: CGFloat
    
    init(_ point: NSPoint) {
        self.x = point.x
        self.y = point.y
    }
    var nsPoint: NSPoint { NSPoint(x: x, y: y) }
}

/// A struct used for encoding and decoding `NSSize` values in the `AppSettingsCodable` struct. Since `NSSize` does not conform to `Codable`, this struct provides a way to represent size values in a codable format, allowing them to be easily saved and loaded as part of the app settings.
struct CodableSize: Codable {
    var width: CGFloat
    var height: CGFloat
    
    init(_ size: NSSize) {
        self.width = size.width
        self.height = size.height
    }
    
    var nsSize: NSSize { NSSize(width: width, height: height) }
}

/// A private struct used for encoding and decoding the `AppSettings` properties to and from JSON. This struct conforms to `Codable` and contains properties that mirror the settings in `AppSettings`, allowing for easy serialization and deserialization of the app settings when saving to or loading from a file.
private struct AppSettingsCodable: Codable {
    var restartedFromPermissionScreen: Bool
    var keyboardHotkey: Shortcut
    var controllerToggleBindings: ControllerToggleBindings
    var controllerActionBindings: ControllerActionBindings
    var enableMouseInKeyboard: Bool
    var prioritizeMouseOverKeyboard: Bool
    var keyboardLayoutName: String
    var leftStickInputType: [AxisActionType]
    var rightStickInputType: [AxisActionType]
    var padInputType: [AxisActionType]
    var shiftShortcutCyclesToCapsLock: Bool
    var dismissWithGuideButton: Bool
    var controllerInputBackendMode: ControllerInputBackendMode?
    var openAppOnStartup: Bool
    var keyboardMovementStyle: KeyboardMovementMode
    var leftStickDeadzone: CGFloat
    var rightStickDeadzone: CGFloat
    var mouseSensitivity: CGFloat
    var mouseSmoothing: CGFloat
    var invertMouseX: Bool
    var invertMouseY: Bool
    var scrollSpeed: CGFloat
    var invertScrollX: Bool
    var invertScrollY: Bool
    var enableHaptics: Bool
    var inMouseMode: Bool
    var showGuideBar: Bool
    var keyboardWindowSize: WindowSize
    var keyboardCustomDimensions: CodableSize?
    var keyboardWindowPosition: CodablePoint
    var mouseWindowPosition: CodablePoint
}
