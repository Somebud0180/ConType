//
//  KeyboardOverlayView.swift
//  ConType
//
//  Created by Ethan John Lagera.
//

import Combine
import ApplicationServices
import AppKit
import SwiftUI

struct KeyboardOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: KeyboardOverlayViewModel
    let onKeyPressed: (VirtualKey, CGEventFlags) -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(in: proxy.size)
            
            VStack(spacing: metrics.rowSpacing) {
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
                        for key in rowWidths.keys {
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
            }
            .padding(metrics.innerPadding)
            .glassEffect(in: .rect(cornerRadius: metrics.windowCornerRadius, style: .continuous))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

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

    @ViewBuilder
    private func keyLegend(for key: VirtualKey, metrics: KeyboardLayoutMetrics, prefersShiftLegend: Bool, controllerShortcutButton: Bool) -> some View {
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
                    .font(.system(size: metrics.activeLegendFontSize, weight: .medium, design: .rounded))
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

    @ViewBuilder
    private func controllerShortcutGlyph(for button: ControllerAssignableButton, metrics: KeyboardLayoutMetrics) -> some View {
        let assetName = button.glyphAssetName(for: settings.controllerGlyphStyle)

        if NSImage(named: NSImage.Name(assetName)) != nil {
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .colorMultiply(Color.primary)
                .frame(width: metrics.controllerGlyphSize, height: metrics.controllerGlyphSize)
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

    private func widths(for row: [VirtualKey], rowIndex: Int, metrics: KeyboardLayoutMetrics) -> [UUID: CGFloat] {
        guard !row.isEmpty else { return [:] }
        debugPrint("Calculating widths for row \(rowIndex)")
        
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
        //        guard !remainingKeys.isEmpty else { return resolved }
        
        let availableRemainingWidth = max(0, availableKeyWidth - fixedWidth)
        let minRemainingWidths = remainingKeys.map { minimumFittingWidth(for: $0, metrics: metrics) }
        let minRemainingSum = minRemainingWidths.reduce(CGFloat(0), +)
        
        //        if minRemainingSum > availableRemainingWidth, minRemainingSum > 0 {
        //            for (index, key) in remainingKeys.enumerated() {
        //                resolved[key.id] = availableRemainingWidth * (minRemainingWidths[index] / minRemainingSum)
        //            }
        //            print("Stage 1, resolved key widths:", resolved)
        //            return resolved
        //        }
        
        let remainingUnits = max(0.0001, remainingKeys.reduce(CGFloat(0)) { $0 + $1.widthUnits })
        let extraWidth = max(0, availableRemainingWidth - minRemainingSum)
        for (index, key) in remainingKeys.enumerated() {
            let unitRatio = key.widthUnits / remainingUnits
            resolved[key.id] = minRemainingWidths[index] + (extraWidth * unitRatio)
        }
        
        return resolved
    }

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

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }

    private var keyAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.24, dampingFraction: 0.82)
    }

    private func isCommandClusterKey(_ key: VirtualKey) -> Bool {
        guard case .toggleModifier(let modifier) = key.role else { return false }
        switch modifier {
        case .control, .option, .command:
            return true
        case .shift, .capsLock:
            return false
        }
    }

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

    private func layoutMetrics(in size: CGSize) -> KeyboardLayoutMetrics {
        let side = min(size.width, size.height)
        let innerPadding = max(10, min(20, side * 0.03))
        let rowSpacing = max(8, min(18, size.height * 0.03))
        let columnSpacing = max(6, min(14, size.width * 0.008))

        let contentWidth = max(1, size.width - (innerPadding * 2))
        let contentHeight = max(1, size.height - (innerPadding * 2))

        let referenceRow = viewModel.rows.first ?? []
        let referenceUnits = max(1, referenceRow.reduce(CGFloat(0)) { $0 + $1.widthUnits })
        let referenceSpacing = CGFloat(max(0, referenceRow.count - 1)) * columnSpacing
        let widthDrivenUnit = max(10, (contentWidth - referenceSpacing) / referenceUnits)
        let heightDrivenKey = (contentHeight - (CGFloat(viewModel.rows.count - 1) * rowSpacing)) / CGFloat(max(viewModel.rows.count, 1))

        let keyHeight = max(26, min(90, heightDrivenKey))

        return KeyboardLayoutMetrics(
            baseUnitWidth: widthDrivenUnit,
            keyHeight: keyHeight,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            innerPadding: innerPadding,
            contentWidth: contentWidth,
            activeLegendFontSize: max(9, min(22, keyHeight * 0.32)),
            inactiveLegendFontSize: max(6, min(16, keyHeight * 0.23)),
            legendSpacing: max(1, min(6, keyHeight * 0.06)),
            commandSymbolFontSize: max(8, min(15, keyHeight * 0.24)),
            commandLabelFontSize: max(7, min(13, keyHeight * 0.18)),
            commandSymbolInset: max(3, min(9, keyHeight * 0.1)),
            commandLabelBottomInset: max(3, min(10, keyHeight * 0.11)),
            controllerGlyphSize: max(14, min(24, keyHeight * 0.32)),
            controllerGlyphInset: max(3, min(8, keyHeight * 0.1)),
            controllerFallbackFontSize: max(8, min(12, keyHeight * 0.18)),
            keyCornerRadius: max(8, min(14, keyHeight * 0.23)),
            outerKeyCornerRadius: max(12, min(20, keyHeight * 0.332)),
            windowCornerRadius: max(18, min(30, side * 0.06))
        )
    }

    private struct KeyboardLayoutMetrics {
        let baseUnitWidth: CGFloat
        let keyHeight: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let innerPadding: CGFloat
        let contentWidth: CGFloat
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
    KeyboardOverlayView(settings: AppSettings(), viewModel: KeyboardOverlayViewModel(settings: AppSettings())) { key, _ in
        print("Pressed \(key.baseLabel)")
    }
    .frame(width: 840, height: 280)
}
