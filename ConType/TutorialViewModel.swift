//
//  TutorialViewModel.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/27/26.
//

import AppKit
import SwiftUI
import Combine

struct BlinkingCaret: View {
    @State private var isVisible = true
    
    var body: some View {
        Text("|")
            .font(.largeTitle)
            .foregroundStyle(.white)
            .opacity(isVisible ? 1 : 0)
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
    var updateCoordinatorVisibilty: (() -> Void)?
    
    @Published private(set) var currentPage: Int = 0
    
    // State for keyboard interaction
    @Published var keyboardOverlayVisible = false {
        didSet {
            updateCoordinatorVisibilty?()
        }
    }
    @Published var keyboardMoved = false
    @Published var completedTyping = false
    @Published var pseudoTextField = ""
    @Published var animateCaret = false
    @Published var caretOffset = 0
    
    // State for mouse interaction
    @Published var mouseOverlayVisible = false {
        didSet {
            updateCoordinatorVisibilty?()
        }
    }
    @Published var mouseMoved = false
    @Published var completedMousing = false
    @Published var mousePosition = CGPoint.zero
    @Published var mouseDown = false
    @Published var viewProxy: GeometryProxy?
    @Published var mouseButtonFrame: CGRect = .zero
    @Published var mouseButtonFrameDown = false
    
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
    
    func pseudoTextFieldView() -> some View {
        HStack(spacing: 1) {
            Text(pseudoTextField.isEmpty ? "Start Typing!" : pseudoTextField)
                .lineLimit(1)
                .font(.largeTitle)
                .foregroundStyle(.white)
                .opacity(pseudoTextField.isEmpty ? 0.8 : 1)
            
            if !pseudoTextField.isEmpty {
                BlinkingCaret()
                    .offset(y: -1)
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
    /// Called when the keyboard overlay activation is triggered.
    func handleKeyboardOverlayActivated() {
        if currentPage == 3 && !keyboardOverlayVisible {
            keyboardOverlayVisible = true
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 4
            }
        } else if currentPage == 4 && completedTyping {
            keyboardOverlayVisible = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 5
            }
        }
    }
    
    /// Called when the mouse overlay activation is triggered.
    func handleMouseOverlayActivated() {
        if currentPage == 5 && !mouseOverlayVisible {
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
    
    func activateSelectedKey() {
        let keys = keyboardViewModel.activateSelected()
        onKeyPressed(keys.0, keys.1)
        debugPrint("Pressing key: \(keys.1), flags: \(keys.1)")
    }
    
    func activateBackspaceKey() {
        if pseudoTextField.isEmpty { return }
        pseudoTextField.removeLast()
    }
    
    func activateSpaceKey() {
        pseudoTextField.append(" ")
    }
    
    func activateEnterKey() {
        // Activate enter key
    }
    
    func activateShiftShortcut(cyclesToCapsLock: Bool) {
        keyboardViewModel.cycleShiftShortcut(cyclesToCapsLock: cyclesToCapsLock)
    }
    
    func activateCapsLockShortcut() {
        keyboardViewModel.toggleCapsLockShortcut()
    }
    
    func onKeyPressed(_ key: VirtualKey, _ flags: CGEventFlags) {
        guard currentPage == 4 else { return }
        guard keyboardMoved else { return }
        guard key.keyCode != 0 else { return }
        
        if key.keyCode == 51 { // Backspace
            if !pseudoTextField.isEmpty {
                pseudoTextField.removeLast()
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
        
        pseudoTextField.append(newChar)
    }
    
    /// Resets the keyboard overlay view model state (selection, modifiers).
    func resetKeyboardOverlay() {
        keyboardViewModel.setKeyboardLayout(settings.keyboardLayout)
    }
    
    func onMouseOverlayPressed() {
        // Do nothing for now
    }
    
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
    
    func reclampMouse() {
        guard let proxy = viewProxy else { return }
        let clampedX = min(max(mousePosition.x, 0), proxy.size.width)
        let clampedY = min(max(mousePosition.y, 0), proxy.size.height)
        mousePosition = CGPoint(x: clampedX, y: clampedY)
    }
    
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
    
    /// Advances to the next tutorial page and resets overlay state if leaving page 3.
    func nextPage() {
        if currentPage == 4 {
            resetKeyboardOverlay()
        }
        currentPage += 1
    }
    
    /// Completes the tutorial and invokes the completion callback.
    func completeTutorial() {
        onComplete?()
    }
    
    // MARK: - Glyph Helpers
    func displayedGuideButtons() -> [ControllerGuideButton] {
        guard let detectedController = settings.detectedController else { return [] }
        if detectedController.guideButtons.isEmpty {
            return [.menu]
        }
        return detectedController.guideButtons
    }
    
    func genericGuideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size,
            colorMultiply: .white
        )
    }
    
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
    
    func assignedButtonGlyph(for action: ControllerActionBinding) -> some View {
        let button = settings.controllerActionBindings.button(for: action)
        return buttonGlyph(button)
    }
    
    func buttonGlyph(_ button: ControllerAssignableButton, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: button.glyphAssetName(for: settings.controllerGlyphStyle),
            fallbackText: button.fallbackGlyphText,
            size: size,
            colorMultiply: .white
        )
    }
    
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
    
    private func axisGlyph(_ axis: AxisInput, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: axis.glyphAssetName,
            fallbackText: axis.fallbackText,
            size: size,
            colorMultiply: .white
        )
    }
    
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
