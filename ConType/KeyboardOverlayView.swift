//
//  KeyboardOverlayView.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import Combine
import ApplicationServices
import AppKit
import SwiftUI

/// A SwiftUI view that renders an on-screen keyboard overlay. It displays keys according to the current keyboard layout and highlights active modifiers.
/// The view also includes an optional guide bar that shows controller action bindings based on settings.
/// User interactions with the keys trigger the corresponding virtual key events via the `onKeyPressed` closure.
struct KeyboardOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: KeyboardOverlayViewModel
    private var settings: AppSettings { viewModel.settings }
    let onKeyPressed: (VirtualKey, CGEventFlags) -> Void
    
    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(in: proxy.size)
            
            VStack(spacing: metrics.rowSpacing) {
                //MARK: - Keyboard
                ForEach(Array(viewModel.rows.enumerated()), id: \.offset) { rowIndex, row in
                    let rowWidths = widths(for: row, rowIndex: rowIndex, metrics: metrics)
                    
                    HStack(spacing: metrics.columnSpacing) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { columnIndex, key in
                            let isSelected = rowIndex == viewModel.selectedRow && columnIndex == viewModel.selectedColumn
                            let cornerRadii = cornerRadii(forRow: rowIndex, column: columnIndex, rowCount: viewModel.rows.count, columnCount: row.count, metrics: metrics)
                            let isModifierLatched = {
                                if case .toggleModifier(let modifier) = key.role {
                                    return viewModel.isModifierActive(modifier)
                                }
                                return false
                            }()
                            let isCommandCluster = isCommandClusterKey(key)
                            let prefersShiftLegend = viewModel.prefersShiftLegend(for: key)
                            let controllerShortcutButton = controllerShortcutButton(for: key)
                            let keyWidth = rowWidths[key.id] ?? max(1, metrics.baseUnitWidth)
                            let keyHeight = metrics.keyHeight
                            let keyColor: Color = colorScheme == .dark ? Color.white : Color.black
                            let fillColor: Color = isSelected || isModifierLatched
                            ? keyColor.opacity(0.36)
                            : (isCommandCluster ? keyColor.opacity(0.23) : keyColor.opacity(0.16))
                            let strokeColor: Color = isSelected || isModifierLatched
                            ? Color.white.opacity(0.75)
                            : (isCommandCluster ? Color.white.opacity(0.34) : Color.white.opacity(0.22))
                            
                            Button {
                                viewModel.select(row: rowIndex, column: columnIndex)
                                viewModel.activate(key, using: onKeyPressed)
                            } label: {
                                keyLabel(
                                    for: key,
                                    metrics: metrics,
                                    prefersShiftLegend: prefersShiftLegend,
                                    controllerShortcutButton: controllerShortcutButton
                                )
                                .frame(width: keyWidth, height: keyHeight)
                                .scaleEffect(isModifierLatched ? 0.9 : 1)
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .fill(fillColor)
                                )
                                .overlay(
                                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                        .strokeBorder(strokeColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onChange(of: rowWidths) {
                        var xOrginForRow: CGFloat = metrics.innerPadding
                        for key in row {
                            if let width = rowWidths[key.id] {
                                if viewModel.keyRefs.firstIndex(where: { $0.id == key.id }) != nil {
                                    viewModel.keyRefs.removeAll(where: { $0.id == key.id })
                                }
                                
                                viewModel.keyRefs.append(KeyReference(
                                    id: key.id,
                                    size: CGSize(width: width, height: metrics.keyHeight),
                                    rowIndex: rowIndex,
                                    columnIndex: row.firstIndex(where: { $0.id == key.id }) ?? 0,
                                    xOrigin: xOrginForRow,
                                ))
                                
                                xOrginForRow += width + metrics.columnSpacing
                            }
                        }
                    }
                }
                
                //MARK: - Guide Bar
                guideBar(metrics: metrics)
                    .padding(.vertical, -metrics.rowSpacing)
            }
            .animation(.easeInOut(duration: 0.1), value: settings.showGuideBar)
            .animation(.easeInOut(duration: 0.2), value: settings.keyboardLayout)
            .padding(metrics.innerPadding)
            .glassEffect(in: .rect(cornerRadius: metrics.windowCornerRadius, style: .continuous))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    
    /// Renders the guide bar that displays controller action bindings if enabled in settings.
    /// It iterates through all possible controller actions and shows their corresponding hotkeys using glyphs or text.
    /// - Parameter metrics: The layout metrics used to size and space the guide bar items appropriately.
    /// - Returns: A view representing the guide bar with controller action bindings.
    @ViewBuilder private func guideBar(metrics: KeyboardLayoutMetrics) -> some View {
        if settings.showGuideBar {
            let actionBindings = settings.controllerActionBindings
            HStack(spacing: 12) {
                ForEach(ControllerActionBinding.allCases, id: \.self) { action in
                    guideBarItem(for: action, actionBindings: actionBindings, metrics: metrics)
                }
            }
            .animation(.easeInOut(duration: 0.1), value: actionBindings)
            .frame(maxHeight: metrics.guideBarHeight)
        }
    }
    
    /// Renders an individual item in the guide bar for a specific controller action.
    /// It checks if the action has a keyboard binding and displays the action title along with the corresponding hotkey glyph.
    /// - Parameters:
    ///   - action: The controller action for which to render the guide bar item.
    ///   - actionBindings: The current controller action bindings from settings, used to determine which hotkey (if any) is associated with the action.
    ///   - metrics: The layout metrics used to size and space the guide bar item appropriately.
    /// - Returns: A view representing the guide bar item for the specified controller action, or an empty view if the action does not have a keyboard binding.
    @ViewBuilder private func guideBarItem(
        for action: ControllerActionBinding,
        actionBindings: ControllerActionBindings,
        metrics: KeyboardLayoutMetrics
    ) -> some View {
        let hotkey = actionBindings.button(for: action)
        if ControllerActionBinding.keyboardActions.contains(action) && hotkey != .none {
            HStack(spacing: 2) {
                Text(action.title)
                    .font(.system(size: metrics.guideBarFontSize, weight: .regular, design: .rounded))
                    .lineSpacing(0.1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
                controllerShortcutGlyph(for: hotkey, metrics: metrics)
            }
        }
    }
    
    /// Renders the label for a given key, including its base label, shifted label (if applicable), command cluster symbol (if it's a modifier), and controller shortcut glyph (if it has an associated controller action).
    /// - Parameters:
    ///   - key: The virtual key for which to render the label.
    ///   - metrics: The layout metrics used to size and space the key label appropriately.
    ///   - prefersShiftLegend: A boolean indicating whether the shifted legend should be visually emphasized over the base label.
    ///   - controllerShortcutButton: An optional controller button that is bound to this key's action.
    /// - Returns: A view representing the key label with all relevant legends and glyphs based on the key's properties and current settings.
    private func keyLabel(
        for key: VirtualKey,
        metrics: KeyboardLayoutMetrics,
        prefersShiftLegend: Bool,
        controllerShortcutButton: ControllerAssignableButton?
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            keyLegend(for: key, metrics: metrics, prefersShiftLegend: prefersShiftLegend, controllerShortcutButton: controllerShortcutButton != nil)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if let controllerShortcutButton {
                controllerShortcutGlyph(for: controllerShortcutButton, metrics: metrics)
                    .padding(.trailing, metrics.controllerGlyphInset)
                    .padding(.top, metrics.controllerGlyphInset)
            }
        }
        .padding(.horizontal, max(4, metrics.baseUnitWidth * 0.08))
    }
    
    /// Renders the legends for a key, including the base label, shifted label (if applicable), command cluster symbol (for modifiers), and adjusts styling based on whether the shift legend should be emphasized or if the key has an associated controller shortcut.
    /// - Parameters:
    ///   - key: The virtual key for which to render the legends.
    ///   - metrics: The layout metrics used to size and space the legends appropriately.
    ///   - prefersShiftLegend: A boolean indicating whether the shifted legend should be visually emphasized over the base label.
    ///   - controllerShortcutButton: A boolean indicating whether this key has an associated controller shortcut button, which affects the legend layout and styling.
    /// - Returns: A view representing the key legends, including the base label, shifted label, command cluster symbol.
    @ViewBuilder private func keyLegend(for key: VirtualKey, metrics: KeyboardLayoutMetrics, prefersShiftLegend: Bool, controllerShortcutButton: Bool) -> some View {
        if let symbol = commandClusterSymbol(for: key) {
            ZStack(alignment: .topTrailing) {
                Text(symbol)
                    .font(.system(size: metrics.commandSymbolFontSize, weight: .semibold, design: .rounded))
                    .padding(.trailing, metrics.commandSymbolInset)
                    .padding(.top, metrics.commandSymbolInset)
                
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(key.baseLabel)
                        .font(.system(size: metrics.commandLabelFontSize, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, metrics.commandSymbolInset)
                        .padding(.bottom, metrics.commandLabelBottomInset)
                }
            }
        } else if controllerShortcutButton && key.baseLabel != "Space"  {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(key.baseLabel)
                    .font(.system(size: metrics.shortcutFontSize, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, metrics.commandSymbolInset)
                    .padding(.bottom, metrics.commandLabelBottomInset)
            }
        } else if let shiftedLabel = key.shiftedLabel {
            VStack(spacing: metrics.legendSpacing) {
                Text(shiftedLabel)
                    .font(.system(size: prefersShiftLegend ? metrics.activeLegendFontSize : metrics.inactiveLegendFontSize, weight: .semibold, design: .rounded))
                    .scaleEffect(prefersShiftLegend ? 1 : 0.9)
                Text(key.baseLabel)
                    .font(.system(size: prefersShiftLegend ? metrics.inactiveLegendFontSize : metrics.activeLegendFontSize, weight: .medium, design: .rounded))
                    .scaleEffect(prefersShiftLegend ? 0.9 : 1)
            }
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .animation(keyAnimation, value: prefersShiftLegend)
        } else {
            Text(key.baseLabel)
                .font(.system(size: metrics.activeLegendFontSize, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
        }
    }
    
    /// Renders the glyph for a controller shortcut associated with a key. It checks if there is a valid image asset for the controller button based on the current glyph style settings, and if so, it displays the image. If not, it falls back to displaying text representing the button.
    /// - Parameters:
    ///   - button: The controller button for which to render the shortcut glyph.
    ///   - metrics: The layout metrics used to size the glyph appropriately based on whether it's being shown in the guide bar or on the key itself.
    ///   - forGuide: A boolean indicating whether the glyph is being rendered for the guide bar (true) or for a key label (false).
    /// - Returns: A view representing the controller shortcut glyph, either as an image or as styled text, with appropriate accessibility labels for screen readers.
    @ViewBuilder private func controllerShortcutGlyph(for button: ControllerAssignableButton, metrics: KeyboardLayoutMetrics, forGuide: Bool = false) -> some View {
        let assetName = button.glyphAssetName(for: settings.controllerGlyphStyle)
        let size = forGuide ? metrics.guideBarHeight : metrics.controllerGlyphSize
        
        if NSImage(named: NSImage.Name(assetName)) != nil {
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .colorMultiply(Color.primary)
                .frame(width: size, height: size)
                .accessibilityLabel(Text(button.displayTitle(for: settings.controllerGlyphStyle)))
        } else {
            Text(button.fallbackGlyphText)
                .font(.system(size: metrics.controllerFallbackFontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, max(2, metrics.controllerGlyphSize * 0.18))
                .padding(.vertical, max(1, metrics.controllerGlyphSize * 0.1))
                .background(
                    RoundedRectangle(cornerRadius: max(3, metrics.controllerGlyphSize * 0.28), style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                )
                .accessibilityLabel(Text(button.displayTitle(for: settings.controllerGlyphStyle)))
        }
    }
    
    /// Determines if a given virtual key has an associated controller shortcut button based on its role and key code. It checks for specific toggle modifiers (shift and caps lock) and standard keys (backspace, space, enter) to see if they are bound to controller actions in the settings, and returns the corresponding controller button if found.
    /// - Parameter key: The virtual key for which to check for an associated controller shortcut button.
    /// - Returns: An optional `ControllerAssignableButton` that represents the controller action bound to this key, or nil if there is no associated controller shortcut.
    private func controllerShortcutButton(for key: VirtualKey) -> ControllerAssignableButton? {
        switch key.role {
        case .toggleModifier(let modifier):
            switch modifier {
            case .shift:
                return settings.controllerActionBindings.shift
            case .capsLock:
                return settings.controllerActionBindings.capsLock
            case .control, .option, .command:
                return nil
            }
        case .standard:
            break
        }
        
        switch key.keyCode {
        case 51:
            return settings.controllerActionBindings.backspace
        case 49:
            return settings.controllerActionBindings.space
        case 36:
            return settings.controllerActionBindings.enter
        default:
            return nil
        }
    }
    
    /// Calculates the widths for each key in a given row based on the keyboard layout metrics and the properties of the keys.
    /// - Parameters:
    ///   - row: An array of `VirtualKey` objects representing the keys in the row for which to calculate widths.
    ///   - rowIndex: The index of the row within the overall keyboard layout, used for determining corner radii and other layout decisions.
    ///   - metrics: The `KeyboardLayoutMetrics` struct containing various measurements and spacing values.
    /// - Returns: A dictionary mapping each key's unique identifier (UUID) to its calculated width in points.
    private func widths(for row: [VirtualKey], rowIndex: Int, metrics: KeyboardLayoutMetrics) -> [UUID: CGFloat] {
        guard !row.isEmpty else { return [:] }
        
        let spacingWidth = CGFloat(max(0, row.count - 1)) * metrics.columnSpacing
        let availableKeyWidth = max(0, metrics.contentWidth - spacingWidth)
        
        var resolved: [UUID: CGFloat] = [:]
        
        let fixedKeys = row.filter { !$0.usesRemainingSpace }
        for key in fixedKeys {
            let baseWidth = key.widthUnits * metrics.baseUnitWidth
            resolved[key.id] = max(baseWidth, minimumFittingWidth(for: key, metrics: metrics))
        }
        
        let fixedWidth = fixedKeys.reduce(CGFloat(0)) { partialResult, key in
            partialResult + (resolved[key.id] ?? 0)
        }
        
        let remainingKeys = row.filter(\.usesRemainingSpace)
        
        let availableRemainingWidth = max(0, availableKeyWidth - fixedWidth)
        let minRemainingWidths = remainingKeys.map { minimumFittingWidth(for: $0, metrics: metrics) }
        let minRemainingSum = minRemainingWidths.reduce(CGFloat(0), +)
        
        let remainingUnits = max(0.0001, remainingKeys.reduce(CGFloat(0)) { $0 + $1.widthUnits })
        let extraWidth = max(0, availableRemainingWidth - minRemainingSum)
        for (index, key) in remainingKeys.enumerated() {
            let unitRatio = key.widthUnits / remainingUnits
            resolved[key.id] = minRemainingWidths[index] + (extraWidth * unitRatio)
        }
        
        return resolved
    }
    
    /// Calculates the minimum width required for a given key to fit its labels and symbols without truncation, based on the keyboard layout metrics and the properties of the key.
    /// It considers the base label, shifted label (if applicable), command cluster symbol (for modifiers), and controller shortcut glyph to determine the necessary width.
    /// - Parameters:
    ///   - key: The `VirtualKey` for which to calculate the minimum fitting width.
    ///   - metrics: The `KeyboardLayoutMetrics` struct containing various measurements and spacing values.
    /// - Returns: The minimum width in points required for the key to fit its content without truncation.
    private func minimumFittingWidth(for key: VirtualKey, metrics: KeyboardLayoutMetrics) -> CGFloat {
        let horizontalPadding = max(4, metrics.baseUnitWidth * 0.08)
        let baseFont = NSFont.systemFont(ofSize: metrics.activeLegendFontSize, weight: .medium)
        let baseTextWidth = textWidth(key.baseLabel, font: baseFont)
        
        var needed = baseTextWidth + horizontalPadding
        
        if let shiftedLabel = key.shiftedLabel {
            let shiftedFont = NSFont.systemFont(ofSize: metrics.activeLegendFontSize, weight: .semibold)
            needed = max(needed, textWidth(shiftedLabel, font: shiftedFont) + horizontalPadding)
        }
        
        if let commandSymbol = commandClusterSymbol(for: key) {
            let symbolFont = NSFont.systemFont(ofSize: metrics.commandSymbolFontSize, weight: .semibold)
            let labelFont = NSFont.systemFont(ofSize: metrics.commandLabelFontSize, weight: .medium)
            needed = textWidth(key.baseLabel, font: labelFont) + textWidth(commandSymbol, font: symbolFont) + metrics.commandSymbolInset + horizontalPadding
        }
        
        if controllerShortcutButton(for: key) != nil {
            let labelFont = NSFont.systemFont(ofSize: metrics.activeLegendFontSize, weight: .medium)
            needed = textWidth(key.baseLabel, font: labelFont) + metrics.commandSymbolInset + horizontalPadding
        }
        
        return ceil(needed)
    }
    
    /// Calculates the width of a given text string when rendered with a specific font, used for determining the minimum fitting width for key labels and symbols.
    /// - Parameters:
    ///   - text: The string for which to calculate the rendered width.
    ///   - font: The `NSFont` to use for calculating the text width, which should match the font used in the key labels for accurate measurements.
    /// - Returns: The width in points that the text would occupy when rendered with the specified font.
    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
    
    /// A computed property that determines the appropriate animation to use for key label changes based on the user's accessibility settings for reduced motion.
    private var keyAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.24, dampingFraction: 0.82)
    }
    
    /// Determines if a given virtual key is part of the "command cluster" (control, option, command modifiers) based on its role.
    private func isCommandClusterKey(_ key: VirtualKey) -> Bool {
        guard case .toggleModifier(let modifier) = key.role else { return false }
        switch modifier {
        case .control, .option, .command:
            return true
        case .shift, .capsLock:
            return false
        }
    }
    
    /// Returns the appropriate symbol for a key if it is a toggle modifier that belongs to the command cluster (control, option, command).
    /// This is used to render the symbols on modifier keys in the command cluster.
    /// - Parameter key: The `VirtualKey` for which to determine the command cluster symbol.
    /// - Returns: A string representing the symbol for the command cluster modifier, or nil if the key is not a toggle modifier in the command cluster.
    private func commandClusterSymbol(for key: VirtualKey) -> String? {
        guard case .toggleModifier(let modifier) = key.role else { return nil }
        switch modifier {
        case .control:
            return "⌃"
        case .option:
            return "⌥"
        case .command:
            return "⌘"
        case .shift, .capsLock:
            return nil
        }
    }
    
    /// Calculates the corner radii for a key based on its position in the keyboard layout.
    /// Keys that are located at the corners of the keyboard will have larger corner radii to create a more rounded appearance, while inner keys will have a standard corner radii.
    /// - Parameters:
    ///   - rowIndex: The index of the row in which the key is located, used to determine if it's in the top or bottom row for corner radius adjustments.
    ///   - column: The index of the column in which the key is located, used to determine if it's in the leftmost or rightmost column for corner radius adjustments.
    ///   - rowCount: The total number of rows in the keyboard layout, used to determine if the key is in the bottom row for corner radius adjustments.
    ///   - columnCount: The total number of columns in the keyboard layout, used to determine if the key is in the rightmost column for corner radius adjustments.
    ///   - metrics: The `KeyboardLayoutMetrics` struct containing the base and outer corner radius values to apply based on the key's position.
    /// - Returns: A `RectangleCornerRadii` struct containing the calculated corner radii for the keys.
    private func cornerRadii(forRow rowIndex: Int, column: Int, rowCount: Int, columnCount: Int, metrics: KeyboardLayoutMetrics) -> RectangleCornerRadii {
        let base = metrics.keyCornerRadius
        let outer = metrics.outerKeyCornerRadius
        var radii = RectangleCornerRadii(
            topLeading: base,
            bottomLeading: base,
            bottomTrailing: base,
            topTrailing: base
        )
        
        if rowIndex == 0 && column == 0 {
            radii.topLeading = outer
        }
        if rowIndex == 0 && column == columnCount - 1 {
            radii.topTrailing = outer
        }
        if rowIndex == rowCount - 1 && column == 0 {
            radii.bottomLeading = outer
        }
        if rowIndex == rowCount - 1 && column == columnCount - 1 {
            radii.bottomTrailing = outer
        }
        
        return radii
    }
    
    /// Calculates various layout metrics for the keyboard overlay based on the available size and current settings.
    /// This includes dimensions for keys, spacing, padding, font sizes, and corner radii that adapt to different screen sizes and user preferences.
    /// - Parameter size: The available size for the keyboard overlay, used to calculate responsive layout metrics.
    /// - Returns: A `KeyboardLayoutMetrics` struct containing all the calculated layout values to be used throughout the view for consistent sizing and spacing.
    private func layoutMetrics(in size: CGSize) -> KeyboardLayoutMetrics {
        let side = min(size.width, size.height)
        let innerPadding = max(10, min(20, side * 0.03))
        let rowSpacing = max(8, min(18, size.height * 0.03))
        let columnSpacing = max(6, min(14, size.width * 0.008))
        
        let guideBar = settings.showGuideBar ? max(12, min(44, size.height * 0.1)) : 0
        let guideBarSpacing = settings.showGuideBar ? rowSpacing : 0
        let guideBarFontMult = size.height < 300 ? 0.26 : 0.4
        let guideBarFontSize = max(4, min(16, guideBar * guideBarFontMult))
        
        let contentWidth = max(1, size.width - (innerPadding * 2))
        let contentHeight = max(1, size.height - (innerPadding * 2) - guideBar + guideBarSpacing)
        
        let referenceRow = viewModel.rows.first ?? []
        let referenceUnits = max(1, referenceRow.reduce(CGFloat(0)) { $0 + $1.widthUnits })
        let referenceSpacing = CGFloat(max(0, referenceRow.count - 1)) * columnSpacing
        let widthDrivenUnit = max(10, (contentWidth - referenceSpacing) / referenceUnits)
        let heightDrivenKey = (contentHeight - (CGFloat(viewModel.rows.count - 1) * rowSpacing)) / CGFloat(max(viewModel.rows.count, 1))
        
        let keyHeight = max(26, min(90, heightDrivenKey))
        
        return KeyboardLayoutMetrics(
            baseUnitWidth: widthDrivenUnit,
            guideBarHeight: guideBar,
            keyHeight: keyHeight,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            innerPadding: innerPadding,
            contentWidth: contentWidth,
            guideBarFontSize: guideBarFontSize,
            shortcutFontSize: max(6, min(22, keyHeight * 0.28)),
            activeLegendFontSize: max(9, min(22, keyHeight * 0.32)),
            inactiveLegendFontSize: max(6, min(16, keyHeight * 0.23)),
            legendSpacing: max(1, min(6, keyHeight * 0.06)),
            commandSymbolFontSize: max(8, min(15, keyHeight * 0.24)),
            commandLabelFontSize: max(7, min(13, keyHeight * 0.2)),
            commandSymbolInset: max(3, min(9, keyHeight * 0.1)),
            commandLabelBottomInset: max(3, min(10, keyHeight * 0.11)),
            controllerGlyphSize: max(14, min(32, keyHeight * 0.38)),
            controllerGlyphInset: max(3, min(8, keyHeight * 0.1)),
            controllerFallbackFontSize: max(8, min(12, keyHeight * 0.18)),
            keyCornerRadius: max(8, min(14, keyHeight * 0.23)),
            outerKeyCornerRadius: max(12, min(20, keyHeight * 0.332)),
            windowCornerRadius: max(18, min(30, side * 0.06))
        )
    }
    
    /// A struct that encapsulates all the layout metrics for the keyboard overlay, calculated based on the available size and current settings.
    /// This struct provides consistent values for key dimensions, spacing, font sizes, and corner radii used throughout the view to ensure a cohesive and responsive design.
    private struct KeyboardLayoutMetrics {
        let baseUnitWidth: CGFloat
        let guideBarHeight: CGFloat
        let keyHeight: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let innerPadding: CGFloat
        let contentWidth: CGFloat
        let guideBarFontSize: CGFloat
        let shortcutFontSize: CGFloat
        let activeLegendFontSize: CGFloat
        let inactiveLegendFontSize: CGFloat
        let legendSpacing: CGFloat
        let commandSymbolFontSize: CGFloat
        let commandLabelFontSize: CGFloat
        let commandSymbolInset: CGFloat
        let commandLabelBottomInset: CGFloat
        let controllerGlyphSize: CGFloat
        let controllerGlyphInset: CGFloat
        let controllerFallbackFontSize: CGFloat
        let keyCornerRadius: CGFloat
        let outerKeyCornerRadius: CGFloat
        let windowCornerRadius: CGFloat
    }
}
    
#Preview {
    KeyboardOverlayView(viewModel: KeyboardOverlayViewModel(settings: AppSettings())) { key, _ in
    }
    .frame(width: 800, height: 320)
}
