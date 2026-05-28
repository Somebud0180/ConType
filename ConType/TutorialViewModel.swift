//
//  TutorialViewModel.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/27/26.
//

import AppKit
import SwiftUI
import Combine

/// ViewModel for the Tutorial view, responsible for managing tutorial state and responding to controller input events.
@MainActor
final class TutorialViewModel: ObservableObject {
    // Dependencies
    let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    
    // Callbacks (injected from controller)
    private let onTutorialCompleted: (() -> Void)?
    
    // Keyboard overlay state
    let keyboardOverlayViewModel: KeyboardOverlayViewModel
    
    // Published UI state
    @Published var currentPage: Int = 0
    @Published var keyboardShortcutTriggered = false
    @Published var mouseShortcutTriggered = false
    @Published var firstMoveDetected = false
    @Published var completedTyping = false
    
    init(
        settings: AppSettings,
        onTutorialCompleted: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.onTutorialCompleted = onTutorialCompleted
        self.keyboardOverlayViewModel = KeyboardOverlayViewModel(settings: settings)
        
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Input Event Handlers
    /// Called when the keyboard overlay activation is triggered.
    func handleKeyboardOverlayActivated() {
        guard !keyboardShortcutTriggered else { return }
        if currentPage == 2 {
            keyboardShortcutTriggered = true
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 3
            }
        } else if currentPage == 3 && completedTyping {
            keyboardShortcutTriggered = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 4
            }
        }
    }
    
    /// Called when the mouse overlay activation is triggered.
    func handleMouseOverlayActivated() {
        guard !mouseShortcutTriggered else { return }
        if currentPage == 4 {
            mouseShortcutTriggered = true
        }
    }
    
    func handleDismissOverlayViaGuideButton() {
        guard settings.dismissWithGuideButton else { return }
        if currentPage == 3 && completedTyping {
            keyboardShortcutTriggered = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage = 4
            }
        }
    }
    
    /// Called when movement is triggered with a direction and trigger type.
    /// Forwards movement to the keyboard overlay view model and marks first move as detected.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection` indicating the movement direction.
    ///   - trigger: The `OverlayMoveTrigger` indicating how the movement was triggered.
    func handleMove(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger) {
        guard currentPage == 3 else { return }
        keyboardOverlayViewModel.move(direction, trigger: trigger)
        if !firstMoveDetected {
            firstMoveDetected = true
        }
    }
    
    func onKeyPressed(_ key: VirtualKey, _ flags: CGEventFlags) {
        guard currentPage == 3 else { return }
        guard !firstMoveDetected else { return }
        // Swallow input
        
    }
    
    /// Resets the keyboard overlay view model state (selection, modifiers).
    func resetKeyboardOverlay() {
        keyboardOverlayViewModel.setKeyboardLayout(settings.keyboardLayout)
    }
    
    /// Advances to the next tutorial page and resets overlay state if leaving page 3.
    func nextPage() {
        if currentPage == 3 {
            resetKeyboardOverlay()
        }
        currentPage += 1
    }
    
    /// Completes the tutorial and invokes the completion callback.
    func completeTutorial() {
        onTutorialCompleted?()
    }
    
    // MARK: - Glyph Helpers
    func genericGuideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size,
            colorMultiply: .white
        )
    }
    
    private func buttonGlyph(_ button: ControllerAssignableButton, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: button.glyphAssetName(for: settings.controllerGlyphStyle),
            fallbackText: button.fallbackGlyphText,
            size: size,
            colorMultiply: .white
        )
    }
    
    func keyboardShortcut() -> some View {
        let selectedButton = settings.controllerToggleBindings.binding(for: .keyboardToggle)
        
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
    
    func keyboardAxisBindings() -> some View {
        // Collect axes assigned to overlay movement
        var bindingAxes: [AxisInput] = []
        
        if settings.leftStickInputType.contains(.overlayMovement) {
            bindingAxes.append(.leftStick)
        }
        if settings.rightStickInputType.contains(.overlayMovement) {
            bindingAxes.append(.rightStick)
        }
        if settings.padInputType.contains(.overlayMovement) {
            bindingAxes.append(.pad)
        }
        
        if bindingAxes.isEmpty {
            return AnyView(
                Text("It seems like you have no input assigned to keyboard movement, open settings to configure.")
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
