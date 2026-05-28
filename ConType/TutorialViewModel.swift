
//
//  Settingsswift
//  ConType
//
//  Created by Ethan John Lagera on 4/18/26.
//

import AppKit
import SwiftUI
import Combine

/// ViewModel for the Settings view, responsible for managing all state and logic related to the settings UI, including handling user interactions for recording hotkeys, selecting controller bindings, managing axis input types, and providing feedback on potential input conflicts. It interacts with the `AppSettings` model to persist changes and uses callbacks to communicate with the view for actions that require user input or confirmation.
@MainActor
final class TutorialViewModel: ObservableObject {
    // Dependencies
    let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    
    init(
        settings: AppSettings
    ) {
        self.settings = settings
        
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    func genericGuideGlyph(size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: "gamecontroller.circle.fill",
            fallbackText: "Guide",
            size: size
        )
    }
    
    private func buttonGlyph(_ button: ControllerAssignableButton, size: CGFloat = 20) -> some View {
        ControllerGlyphBadge(
            assetName: button.glyphAssetName(for: settings.controllerGlyphStyle),
            fallbackText: button.fallbackGlyphText,
            size: size
        )
    }
    
    func keyboardShortcut() -> some View {
        let selectedButton = settings.controllerToggleBindings.binding(for: .keyboardToggle)
        
        return HStack(spacing: 8) {
            genericGuideGlyph(size: 32)
            Text("+")
            buttonGlyph(selectedButton, size: 32)
                .colorInvert()
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
            size: size
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
                        .colorInvert()
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
            content.append(AnyView(axisGlyph(axis, size: 32).colorInvert()))
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
    
    TutorialView(viewModel: vm)
}
