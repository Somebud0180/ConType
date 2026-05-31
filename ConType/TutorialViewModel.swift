//
//  TutorialViewModel.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/27/26.
//

import AppKit
import SwiftUI
import Combine

/// A simple blinking caret view used in the pseudo text field during the keyboard tutorial page.
struct BlinkingCaret: View {
    @State private var isVisible = true
    
    var body: some View {
        Text("|")
            .font(.largeTitle)
            .foregroundStyle(.white)
            .opacity(isVisible ? 1 : 0)
            .padding(.horizontal, -2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isVisible.toggle()
                }
            }
    }
}

/// ViewModel for the Tutorial view, responsible for managing tutorial state and responding to controller input events.
@MainActor
final class TutorialViewModel: ObservableObject {
    let settings: AppSettings
    let keyboardViewModel: KeyboardOverlayViewModel
    private var cancellables = Set<AnyCancellable>()
    
    var onComplete: (() -> Void)?
    var openSettings: (() -> Void)?
    var updateCoordinatorVisibility: (() -> Void)?
    
    @Published private(set) var currentPage: Int = 3
    @Published var viewProxy: GeometryProxy?
    
    // State for keyboard interaction
    @Published var keyboardOverlayVisible: Bool = false {
        didSet {
            updateCoordinatorVisibility?()
        }
    }
    @Published var keyboardMoved: Bool = false
    @Published var completedTyping: Bool = false
    @Published var pseudoTextField: String = ""
    @Published var pseudoTextFieldReference: String = ""
    @Published var animateCaret: Bool = false
    @Published var caretOffset: CGFloat = 0
    
    // State for mouse interaction
    @Published var mouseOverlayVisible = false {
        didSet {
            updateCoordinatorVisibility?()
        }
    }
    @Published var mouseMoved: Bool = false
    @Published var completedMousing: Bool = false
    @Published var mousePosition: CGPoint = CGPoint.zero
    @Published var mouseDown: Bool = false
    @Published var mouseButtonFrame: CGRect = .zero
    @Published var mouseButtonFrameDown: Bool = false
    
    init(
        settings: AppSettings
    ) {
        self.settings = settings
        self.keyboardViewModel = KeyboardOverlayViewModel(settings: settings)
        
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    /// A capsule-shaped text field that displays the string variable `pseudoTextField` and a blinking caret when the string is not empty.
    /// The text field animates its width based on the content and applies a glass effect.
    /// - Returns: A view representing the pseudo text field
    func pseudoTextFieldView() -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Text(pseudoTextField.isEmpty ? "Start Typing!" : pseudoTextField)
                    .lineLimit(1)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .opacity(pseudoTextField.isEmpty ? 0.8 : 1)
                
                if !pseudoTextField.isEmpty {
                    BlinkingCaret()
                        .opacity(0)
                }
            }
            
            if !pseudoTextField.isEmpty {
                HStack(spacing: 0) {
                    Text(pseudoTextFieldReference)
                        .lineLimit(1)
                        .font(.largeTitle)
                        .opacity(0)
                    
                    BlinkingCaret()
                        .offset(y: -1)
                }
            }
        }
        .padding(8)
        .padding(.horizontal, 12)
        .frame(minWidth: pseudoTextField.isEmpty ? 0 : 512, alignment: .leading)
        .glassEffect(
            .clear,
            in: Capsule()
        )
        .animation(.spring(.bouncy, blendDuration: 0.3), value: pseudoTextField)
    }
    
    // MARK: - Input Event Handlers
    /// Handles activation of the keyboard overlay, advancing tutorial pages based on current page and interaction completion state.
    func handleKeyboardOverlayActivated() {
        if currentPage == 3 {
            keyboardOverlayVisible = true
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 4
            }
        } else if currentPage == 4 && completedTyping {
            keyboardOverlayVisible = false
            resetKeyboardOverlay()
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 5
            }
        }
    }
    
    /// Hamdles activation of the mouse overlay, advancing tutorial pages based on current page and interaction completion state.
    func handleMouseOverlayActivated() {
        if currentPage == 5 {
            mouseOverlayVisible = true
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 6
            }
        } else if currentPage == 6 && completedMousing {
            keyboardOverlayVisible = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 7
            }
        }
    }
    
    /// Handles dismissal of the overlays via guide button, advancing tutorial pages based on current page and interaction completion state.
    func handleDismissOverlayViaGuideButton() {
        guard settings.dismissWithGuideButton else { return }
        if currentPage == 4 && completedTyping {
            keyboardOverlayVisible = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 5
            }
        } else if currentPage == 6 && completedMousing {
            keyboardOverlayVisible = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 7
            }
        }
    }
    
    /// Called when movement is triggered with a direction and trigger type.
    /// Forwards movement to the keyboard overlay view model and marks first move as detected.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` indicating the movement direction.
    ///   - trigger: The `OverlayMoveTrigger` indicating how the movement was triggered.
    func handleMove(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger) {
        guard currentPage == 4 else { return }
        keyboardViewModel.move(direction, trigger: trigger)
        if !keyboardMoved {
            withAnimation(.easeInOut(duration: 0.3)) {
                keyboardMoved = true
            }
        }
    }
    
    /// Handles activating the currently selected key in the keyboard overlay, sending the corresponding key press event.
    func activateSelectedKey() {
        let keys = keyboardViewModel.activateSelected()
        onKeyPressed(keys.0, keys.1)
    }
    
    /// Activates the backspace key, removing the last character from the pseudo text field if it's not empty.
    func activateBackspaceKey() {
        if pseudoTextField.isEmpty || pseudoTextFieldReference.isEmpty { return }
        debugPrint("Offset: \(caretOffset), pseudoTextField: \(pseudoTextField), pseudoTextFieldReference: \(pseudoTextFieldReference)")
        if caretOffset < 0 {
            pseudoTextField.remove(at: pseudoTextField.index(pseudoTextField.endIndex, offsetBy: Int(caretOffset) - 1))
        } else {
            pseudoTextField.removeLast()
        }
        pseudoTextFieldReference.removeLast()
        clampCaretOffset()
    }
    
    /// Handles activating the space key, appending a space character to the pseudo text field.
    func activateSpaceKey() {
        debugPrint("Offset: \(caretOffset), pseudoTextField: \(pseudoTextField), pseudoTextFieldReference: \(pseudoTextFieldReference)")
        pseudoTextField.insert(contentsOf: " ", at: pseudoTextField.index(pseudoTextField.endIndex, offsetBy: Int(caretOffset)))
        pseudoTextFieldReference.append(" ")
        clampCaretOffset()
    }
    
    /// Handles activating the tab key. Does nothing.
    func activateEnterKey() {
        // Activate enter key
    }
    
    /// Handles activating the shift shortcut, forwarding the action to the keyboard overlay view model and toggling the shifted state.
    /// - Parameter cyclesToCapsLock: A boolean indicating whether the shift shortcut should cycle to caps lock after being activated a certain number of times
    func activateShiftShortcut(cyclesToCapsLock: Bool) {
        keyboardViewModel.cycleShiftShortcut(cyclesToCapsLock: cyclesToCapsLock)
    }
    
    /// Handles activating the caps lock shortcut, forwarding the action to the keyboard overlay view model to toggle caps lock state.
    func activateCapsLockShortcut() {
        keyboardViewModel.toggleCapsLockShortcut()
    }
    
    /// Adjusts the caret position to the left, ensuring it does not go beyond the start of the text in the pseudo text field.
    func moveCaretLeft() {
        guard currentPage == 4 else { return }
        if caretOffset > CGFloat(-pseudoTextField.count) {
            caretOffset -= 1
            pseudoTextFieldReference.removeLast()
            debugPrint("Caret offset after moving left: \(caretOffset)")
        }
    }
    
    /// Adjusts the caret position to the right, ensuring it does not go beyond the end of the text in the pseudo text field.
    func moveCaretRight() {
        guard currentPage == 4 else { return }
        if caretOffset < 0 {
            caretOffset += 1
            
            /// Special handling for offset 0. Causes `index out of bounds` if using the general logic.
            if caretOffset < 0 {
                pseudoTextFieldReference.append(pseudoTextField[pseudoTextField.index(pseudoTextField.endIndex, offsetBy: Int(caretOffset))])
            } else {
                pseudoTextFieldReference = pseudoTextField
            }
            
            debugPrint("Caret offset after moving right: \(caretOffset)")
        }
    }
    
    func clampCaretOffset() {
        caretOffset = min(max(caretOffset, CGFloat(-pseudoTextField.count)), 0)
    }
    
    func getCaretOffset() -> CGFloat {
        let charWidth: CGFloat = 24
        return CGFloat(caretOffset) * charWidth
    }
    
    /// Handles a key press event from the keyboard overlay, updating the pseudo text field based on the key code and modifier flags.
    /// - Parameters:
    ///   - key: The `VirtualKey` that was pressed, containing information about the key code and labels
    ///   - flags: The `CGEventFlags` representing the modifier keys active during the key press
    func onKeyPressed(_ key: VirtualKey, _ flags: CGEventFlags) {
        guard currentPage == 4 else { return }
        guard keyboardMoved else { return }
        guard key.keyCode != 0 else { return }
        
        if key.keyCode == 51 { // Backspace
            if !pseudoTextField.isEmpty {
                pseudoTextField.removeLast()
                clampCaretOffset()
            }
            return
        } else if key.keyCode == 49 { // Space
            pseudoTextField.append(" ")
            return
        } else if key.keyCode == 48 || key.keyCode == 36 { // Tab & Return
            return
        }
        
        let hasShiftedLabel = key.shiftedLabel != nil
        let isShifted = flags.contains(.maskShift)
        
        let newChar = isShifted && hasShiftedLabel ? key.shiftedLabel! : key.baseLabel
        
        /// Insert the new character at the caret position in the pseudo text field.
        pseudoTextField.insert(contentsOf: newChar, at: pseudoTextField.index(pseudoTextField.endIndex, offsetBy: Int(caretOffset)))
        
        pseudoTextFieldReference.append(newChar)
        
        clampCaretOffset()
    }
    
    /// Resets the keyboard overlay view model state (selection, modifiers).
    func resetKeyboardOverlay() {
        keyboardViewModel.setKeyboardLayout(settings.keyboardLayout)
    }
    
    /// Handles pressing on the mouse overlay. Does nothing.
    func onMouseOverlayPressed() {
        // Do nothing for now
    }
    
    /// Handles mouse movement by updating the `mousePosition` based on the provided delta, clamping it within the view bounds, and updating interaction state accordingly.
    /// - Parameter delta: A `CGVector` representing the change in mouse position since the last update
    func handleMouseMove(by delta: CGVector) {
        guard currentPage == 6, let proxy = viewProxy else { return }
        let newX = mousePosition.x + delta.dx
        let newY = mousePosition.y + delta.dy
        let clampedX = min(max(newX, 0), proxy.size.width)
        let clampedY = min(max(newY, 0), proxy.size.height)
        
        if !mouseMoved {
            withAnimation(.easeInOut(duration: 0.3)) {
                mouseMoved = true
            }
        }
        
        mousePosition = CGPoint(x: clampedX, y: clampedY)
        
        if mouseButtonFrameDown && !mouseButtonFrame.contains(mousePosition) {
            mouseButtonFrameDown = false
        }
    }
    
    /// Handles mouse click events by updating the `mouseDown` state and checking if the click occurred within the designated button frame, advancing tutorial progress accordingly.
    /// - Parameter isDown: A boolean indicating whether the mouse button was pressed down or released
    func handleMouseClick(isDown: Bool) {
        guard currentPage == 6 else { return }
        mouseDown = isDown
        
        debugPrint("Mouse click \(isDown ? "down" : "up") at position: \(mousePosition), button frame: \(mouseButtonFrame)")
        
        if isDown && mouseButtonFrame.contains(mousePosition) {
            mouseButtonFrameDown = true
        } else if !isDown && mouseButtonFrameDown && mouseButtonFrame.contains(mousePosition) {
            mouseButtonFrameDown = false
            completedMousing = true
        } else {
            mouseButtonFrameDown = false
        }
    }
    
    /// Reclamps the mouse position within the bounds of the view proxy, ensuring the cursor does not go outside the visible area.
    func reclampMouse() {
        guard let proxy = viewProxy else { return }
        let clampedX = min(max(mousePosition.x, 0), proxy.size.width)
        let clampedY = min(max(mousePosition.y, 0), proxy.size.height)
        mousePosition = CGPoint(x: clampedX, y: clampedY)
    }
    
    /// Generates a view representing the mouse cursor overlay, displaying a pointer icon at the current mouse position with visibility based on the `mouseOverlayVisible` state.
    /// - Parameters:
    ///   - proxy: A `GeometryProxy` representing the dimensions of the view, used for positioning and clamping the mouse cursor within bounds
    ///   - mousePos: A `CGPoint` representing the current position of the mouse cursor, used to position the cursor icon in the overlay
    /// - Returns: A view containing the mouse cursor icon, positioned at `mousePos` and with opacity based on `mouseOverlayVisible`
    func mouseCursorLayer(_ proxy: GeometryProxy, mousePos: CGPoint) -> some View {
        return VStack {
            Image(systemName: "pointer.arrow")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 15, height: 18)
                .position(mousePos)
                .opacity(self.mouseOverlayVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: self.mouseOverlayVisible)
        }
    }
    
    /// Advances to the next tutorial page.
    func nextPage() {
        // Prevent button mashing to skip pages
        if currentPage < 3 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage += 1
            }
        }
    }
    
    /// Returns to the previous tutor
    /// ial page.
    func previousPage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = max(currentPage - 1, 0)
        }
    }
    
    /// Invokes the completion callback and resets all states to their initial values.
    func completeTutorial() {
        onComplete?()
        currentPage = 0
        keyboardOverlayVisible = false
        keyboardMoved = false
        completedTyping = false
        pseudoTextField = ""
        animateCaret = false
        caretOffset = 0
        mouseOverlayVisible = false
        mouseMoved = false
        completedMousing = false
        mousePosition = CGPoint.zero
        mouseDown = false
        viewProxy = nil
        mouseButtonFrame = .zero
        mouseButtonFrameDown = false
    }
    
    // MARK: - Glyph Helpers
    /// Determines which guide buttons to display based on the detected controller and settings, defaulting to showing a menu button if no guide buttons are detected.
    /// - Returns: An array of `ControllerGuideButton` representing the buttons to be displayed in the guide
    func displayedGuideButtons() -> [ControllerGuideButton] {
        guard let detectedController = settings.detectedController else { return [] }
        if detectedController.guideButtons.isEmpty {
            return [.menu]
        }
        return detectedController.guideButtons
    }
    
    /// Generates a generic guide button glyph, using a default controller icon and "Guide" text, with customizable size.
    /// - Parameter size: A `CGFloat` representing the size of the glyph, defaulting to 20
    /// - Returns: A view representing the generic guide button glyph
    func genericGuideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size,
            colorMultiply: .white
        )
    }
    
    /// Generates a view for a given controller guide button, displaying the appropriate glyph based on the current settings and detected controller, with a fallback to text if no glyph is available.
    /// The glyph is styled with a glass effect and accessibility label.
    /// - Parameters:
    ///   - button: A `ControllerGuideButton` representing the specific guide button to generate a glyph for
    ///   - size: A `CGFloat` representing the size of the glyph, defaulting to 32
    /// - Returns: A view representing the controller guide button glyph
    @ViewBuilder
    func controllerGuideGlyphs(_ button: ControllerGuideButton, size: CGFloat = 32) -> some View {
        let title = button.displayTitle(for: settings.controllerGlyphStyle)
        if let assetName = button.glyphAssetName(for: settings.controllerGlyphStyle) {
            ControllerGlyphBadge(
                assetName: assetName,
                fallbackText: title,
                size: size,
                colorMultiply: .white
            )
        } else {
            Text(title)
                .font(.system(size: max(10, size * 0.45), weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, max(4, size * 0.24))
                .frame(height: size)
                .background(
                    RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .accessibilityLabel(Text(title))
        }
    }
    
    /// Generates a horizontal stack of guide button glyphs based on the detected controller and settings, displaying a message if no controller is detected.
    /// - Returns: A view representing the stack of guide button glyphs or a message prompting the user to reconnect their controller
    func guideButtons() -> some View {
        let guideButtons = displayedGuideButtons()
        
        return HStack(spacing: 8) {
            Group {
                if settings.detectedController != nil {
                    ForEach(
                        Array(guideButtons.enumerated()),
                        id: \.offset
                    ) { _, guideButton in
                        self.controllerGuideGlyphs(guideButton)
                    }
                } else {
                    Text("Controller disconnected. Please reconnect them.")
                }
            }
            .foregroundStyle(.white)
            .frame(minHeight: 44)
        }
    }
    
    /// Quickly generates a view representing the glyph assigned to a specific controller action.
    /// - Parameter action: The `ControllerActionBinding` representing the specific controller action to generate a glyph for
    /// - Returns: A view representing the assigned button glyph for the given controller action
    func assignedButtonGlyph(for action: ControllerActionBinding) -> some View {
        let button = settings.controllerActionBindings.button(for: action)
        return buttonGlyph(button)
    }
    
    /// Generates a view representing the glyph for a given controller button, using the appropriate asset based on the current settings and detected controller, with a fallback to text if no glyph is available.
    /// - Parameters:
    ///   - button: A `ControllerAssignableButton` representing the specific controller button to generate a glyph for
    ///   - size: A `CGFloat` representing the size of the glyph, defaulting to 20
    /// - Returns: A view representing the controller button glyph
    func buttonGlyph(_ button: ControllerAssignableButton, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: button.glyphAssetName(for: settings.controllerGlyphStyle),
            fallbackText: button.fallbackGlyphText,
            size: size,
            colorMultiply: .white
        )
    }
    
    /// Creates a view representing the shortcut for a given controller toggle binding, displaying the guide button glyph and the assigned button glyph with a "+" separator, along with the name of the assigned button.
    /// - Parameter mode: The `ControllerToggleBinding` representing the specific toggle action to generate the shortcut view for
    /// - Returns: A view representing the controller shortcut for the given toggle binding
    func controllerShortcut(for mode: ControllerToggleBinding) -> some View {
        let selectedButton = settings.controllerToggleBindings.binding(for: mode)
        
        return HStack(spacing: 8) {
            genericGuideGlyph(size: 32)
            Text("+")
            buttonGlyph(selectedButton, size: 32)
            Text(selectedButton.displayTitle(for: settings.controllerGlyphStyle))
                .font(.system(.body, design: .monospaced))
        }
        .foregroundStyle(.white)
        .frame(width: 220, alignment: .center)
        .frame(minHeight: 44)
    }
    
    /// Generates a view representing the glyph for a given controller axis input, using the appropriate asset based on the current settings and detected controller, with a fallback to text if no glyph is available.
    /// - Parameters:
    ///   - axis: An `AxisInput` representing the specific controller axis to generate a glyph for
    ///   - size: A `CGFloat` representing the size of the glyph, defaulting to 20
    /// - Returns: A view representing the controller axis glyph for the given axis input
    private func axisGlyph(_ axis: AxisInput, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: axis.glyphAssetName,
            fallbackText: axis.fallbackText,
            size: size,
            colorMultiply: .white
        )
    }
    
    /// Generates a view representing the axes assigned to a specific controller action, displaying the corresponding glyphs with "or" separators if multiple axes are assigned, or a message prompting the user to configure bindings if no axes are assigned.
    /// - Parameter action: An `AxisActionType` representing the specific controller action to generate the axis bindings view for
    /// - Returns: A view representing the assigned axis bindings for the given controller action, or a message prompting the user to configure bindings if none are assigned
    func axisBindings(for action: AxisActionType) -> some View {
        // Collect axes assigned to overlay movement
        var bindingAxes: [AxisInput] = []
        
        var actionString: String {
            switch action {
            case .overlayMovement: return "keyboard"
            case .mouseMovement: return "mouse"
            case .arrowKeys: return "arrow key"
            case .scrollWheel: return "scroll"
            default: return "this"
            }
        }
        
        if settings.leftStickInputType.contains(action) {
            bindingAxes.append(.leftStick)
        }
        if settings.rightStickInputType.contains(action) {
            bindingAxes.append(.rightStick)
        }
        if settings.padInputType.contains(action) {
            bindingAxes.append(.pad)
        }
        
        if bindingAxes.isEmpty {
            return AnyView(
                Button("It seems like you have no input assigned to \(actionString) movement, click here to open settings and configure.") {
                    self.openSettings?()
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
            )
        }
        
        if bindingAxes.count == 1 {
            return AnyView(
                HStack(spacing: 8) {
                    axisGlyph(bindingAxes[0], size: 32)
                }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
            )
        }
        
        // Multiple bindings: show with "or" separators
        var content: [AnyView] = []
        for (index, axis) in bindingAxes.enumerated() {
            if index > 0 {
                content.append(AnyView(Text("or")))
            }
            content.append(AnyView(axisGlyph(axis, size: 32)))
        }
        
        return AnyView(
            HStack(spacing: 8) {
                ForEach(Array(content.enumerated()), id: \.offset) { _, view in
                    view
                }
            }
                .foregroundStyle(.white)
                .frame(minHeight: 44)
        )
    }
    
    /// Generates a view representing the mouse click buttons assigned to the left and right click actions, displaying the corresponding glyphs and labels for each button.
    /// - Returns: A view representing the mouse click buttons with their assigned glyphs and labels
    func mouseClickButtons() -> some View {
        return HStack(spacing: 8) {
            VStack {
                assignedButtonGlyph(for: .mouseLeftClick)
                
                Text("Left Click")
                    .font(.footnote)
                    .fontWeight(.semibold)
            }
            VStack {
                assignedButtonGlyph(for: .mouseRightClick)
                
                Text("Right Click")
                    .font(.footnote)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(.white)
        .frame(minHeight: 44)
    }
}

//MARK: - View Modifiers
/// A button style that applies a prominent liquid glass like effect in a capsule shape.
struct RoundGlassProminent: ViewModifier {
    let padding: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .padding(.vertical, padding / 2)
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassEffect(
                .regular
                    .interactive()
                    .tint(.accentColor),
                in: Capsule()
            )
    }
}

extension View {
    /// Applies RoundGlassProminent to a given view.
    /// - Parameter padding: `CGFloat` amount of padding, default 16
    /// - Returns: A modifier view with the RoundGlassProminent style applied
    func roundGlassProminent(padding: CGFloat = 16) -> some View {
        self.modifier(RoundGlassProminent(padding: padding))
    }
}

#Preview {
    let vm = TutorialViewModel(
        settings: AppSettings()
    )
    
    TutorialView(viewModel: vm, settings: AppSettings())
}
