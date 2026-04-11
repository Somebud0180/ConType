import Combine
import ApplicationServices
import AppKit
import SwiftUI

enum VirtualKeyRole: Hashable {
    case standard
    case toggleModifier(ModifierToggleKey)
}

enum ModifierToggleKey: Hashable {
    case control
    case option
    case command
    case shift
    case capsLock
}

struct VirtualKey: Identifiable, Hashable {
    let id = UUID()
    let baseLabel: String
    let shiftedLabel: String?
    let keyCode: CGKeyCode
    let widthUnits: CGFloat
    let role: VirtualKeyRole
    let usesRemainingSpace: Bool

    init(
        baseLabel: String,
        shiftedLabel: String? = nil,
        keyCode: CGKeyCode,
        widthUnits: CGFloat = 1,
        role: VirtualKeyRole = .standard,
        usesRemainingSpace: Bool = false
    ) {
        self.baseLabel = baseLabel
        self.shiftedLabel = shiftedLabel
        self.keyCode = keyCode
        self.widthUnits = widthUnits
        self.role = role
        self.usesRemainingSpace = usesRemainingSpace
    }

    var respondsToCapsLock: Bool {
        baseLabel.count == 1 && baseLabel.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    var isAlphanumeric: Bool {
        baseLabel.count == 1 && baseLabel.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}

enum OverlayMoveDirection {
    case up
    case down
    case left
    case right
}

enum OverlayMoveTrigger {
    case press
    case holdRepeat
}

@MainActor
final class KeyboardOverlayViewModel: ObservableObject {
    let rows: [[VirtualKey]] = [
        [
            VirtualKey(baseLabel: "`", shiftedLabel: "~", keyCode: 50),
            VirtualKey(baseLabel: "1", shiftedLabel: "!", keyCode: 18),
            VirtualKey(baseLabel: "2", shiftedLabel: "@", keyCode: 19),
            VirtualKey(baseLabel: "3", shiftedLabel: "#", keyCode: 20),
            VirtualKey(baseLabel: "4", shiftedLabel: "$", keyCode: 21),
            VirtualKey(baseLabel: "5", shiftedLabel: "%", keyCode: 23),
            VirtualKey(baseLabel: "6", shiftedLabel: "^", keyCode: 22),
            VirtualKey(baseLabel: "7", shiftedLabel: "&", keyCode: 26),
            VirtualKey(baseLabel: "8", shiftedLabel: "*", keyCode: 28),
            VirtualKey(baseLabel: "9", shiftedLabel: "(", keyCode: 25),
            VirtualKey(baseLabel: "0", shiftedLabel: ")", keyCode: 29),
            VirtualKey(baseLabel: "-", shiftedLabel: "_", keyCode: 27),
            VirtualKey(baseLabel: "=", shiftedLabel: "+", keyCode: 24),
            VirtualKey(baseLabel: "Delete", keyCode: 51, widthUnits: 2)
        ],
        [
            VirtualKey(baseLabel: "Tab", keyCode: 48, widthUnits: 1.5),
            VirtualKey(baseLabel: "q", shiftedLabel: "Q", keyCode: 12),
            VirtualKey(baseLabel: "w", shiftedLabel: "W", keyCode: 13),
            VirtualKey(baseLabel: "e", shiftedLabel: "E", keyCode: 14),
            VirtualKey(baseLabel: "r", shiftedLabel: "R", keyCode: 15),
            VirtualKey(baseLabel: "t", shiftedLabel: "T", keyCode: 17),
            VirtualKey(baseLabel: "y", shiftedLabel: "Y", keyCode: 16),
            VirtualKey(baseLabel: "u", shiftedLabel: "U", keyCode: 32),
            VirtualKey(baseLabel: "i", shiftedLabel: "I", keyCode: 34),
            VirtualKey(baseLabel: "o", shiftedLabel: "O", keyCode: 31),
            VirtualKey(baseLabel: "p", shiftedLabel: "P", keyCode: 35),
            VirtualKey(baseLabel: "[", shiftedLabel: "{", keyCode: 33),
            VirtualKey(baseLabel: "]", shiftedLabel: "}", keyCode: 30),
            VirtualKey(baseLabel: "\\", shiftedLabel: "|", keyCode: 42, widthUnits: 1.5)
        ],
        [
            VirtualKey(baseLabel: "Caps Lock", keyCode: 57, role: .toggleModifier(.capsLock), usesRemainingSpace: true),
            VirtualKey(baseLabel: "a", shiftedLabel: "A", keyCode: 0),
            VirtualKey(baseLabel: "s", shiftedLabel: "S", keyCode: 1),
            VirtualKey(baseLabel: "d", shiftedLabel: "D", keyCode: 2),
            VirtualKey(baseLabel: "f", shiftedLabel: "F", keyCode: 3),
            VirtualKey(baseLabel: "g", shiftedLabel: "G", keyCode: 5),
            VirtualKey(baseLabel: "h", shiftedLabel: "H", keyCode: 4),
            VirtualKey(baseLabel: "j", shiftedLabel: "J", keyCode: 38),
            VirtualKey(baseLabel: "k", shiftedLabel: "K", keyCode: 40),
            VirtualKey(baseLabel: "l", shiftedLabel: "L", keyCode: 37),
            VirtualKey(baseLabel: ";", shiftedLabel: ":", keyCode: 41),
            VirtualKey(baseLabel: "'", shiftedLabel: "\"", keyCode: 39),
            VirtualKey(baseLabel: "Return", keyCode: 36, usesRemainingSpace: true)
        ],
        [
            VirtualKey(baseLabel: "Shift", keyCode: 56, role: .toggleModifier(.shift), usesRemainingSpace: true),
            VirtualKey(baseLabel: "z", shiftedLabel: "Z", keyCode: 6),
            VirtualKey(baseLabel: "x", shiftedLabel: "X", keyCode: 7),
            VirtualKey(baseLabel: "c", shiftedLabel: "C", keyCode: 8),
            VirtualKey(baseLabel: "v", shiftedLabel: "V", keyCode: 9),
            VirtualKey(baseLabel: "b", shiftedLabel: "B", keyCode: 11),
            VirtualKey(baseLabel: "n", shiftedLabel: "N", keyCode: 45),
            VirtualKey(baseLabel: "m", shiftedLabel: "M", keyCode: 46),
            VirtualKey(baseLabel: ",", shiftedLabel: "<", keyCode: 43),
            VirtualKey(baseLabel: ".", shiftedLabel: ">", keyCode: 47),
            VirtualKey(baseLabel: "/", shiftedLabel: "?", keyCode: 44),
            VirtualKey(baseLabel: "Shift", keyCode: 60, role: .toggleModifier(.shift), usesRemainingSpace: true)
        ],
        [
            VirtualKey(baseLabel: "Control", keyCode: 59, role: .toggleModifier(.control)),
            VirtualKey(baseLabel: "Option", keyCode: 58, role: .toggleModifier(.option)),
            VirtualKey(baseLabel: "Command", keyCode: 55, widthUnits: 1.2, role: .toggleModifier(.command)),
            VirtualKey(baseLabel: "Space", keyCode: 49, usesRemainingSpace: true)
        ]
    ]

    @Published private(set) var selectedRow = 0
    @Published private(set) var selectedColumn = 0
    @Published private(set) var activeModifierKeys: Set<ModifierToggleKey> = []

    var selectedKey: VirtualKey? {
        guard rows.indices.contains(selectedRow) else { return nil }
        let row = rows[selectedRow]
        guard row.indices.contains(selectedColumn) else { return nil }
        return row[selectedColumn]
    }

    @discardableResult
    func move(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger = .press) -> Bool {
        let previousRow = selectedRow
        let previousColumn = selectedColumn
        let allowsWrap = trigger == .press

        switch direction {
        case .left:
            if selectedColumn > 0 {
                selectedColumn -= 1
            } else if allowsWrap {
                selectedColumn = max(0, rows[selectedRow].count - 1)
            }
        case .right:
            let maxColumn = max(0, rows[selectedRow].count - 1)
            if selectedColumn < maxColumn {
                selectedColumn += 1
            } else if allowsWrap {
                selectedColumn = 0
            }
        case .up:
            if selectedRow > 0 {
                selectedRow -= 1
            } else if allowsWrap {
                selectedRow = rows.count - 1
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
        case .down:
            if selectedRow < rows.count - 1 {
                selectedRow += 1
            } else if allowsWrap {
                selectedRow = 0
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
        }

        return previousRow != selectedRow || previousColumn != selectedColumn
    }

    func select(row: Int, column: Int) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        selectedRow = row
        selectedColumn = column
    }

    func activateSelected(using emitter: (VirtualKey, CGEventFlags) -> Void) {
        guard let key = selectedKey else { return }
        activate(key, using: emitter)
    }

    func activate(_ key: VirtualKey, using emitter: (VirtualKey, CGEventFlags) -> Void) {
        switch key.role {
        case .toggleModifier(let modifier):
            if activeModifierKeys.contains(modifier) {
                activeModifierKeys.remove(modifier)
            } else {
                activeModifierKeys.insert(modifier)
            }
        case .standard:
            let flags = eventFlags(from: activeModifierKeys)
            emitter(key, flags)

            // Shift behaves as one-shot for typed alphanumeric characters.
            if key.isAlphanumeric {
                activeModifierKeys.remove(.shift)
            }
        }
    }

    func isModifierActive(_ modifier: ModifierToggleKey) -> Bool {
        activeModifierKeys.contains(modifier)
    }

    func cycleShiftShortcut(cyclesToCapsLock: Bool) {
        let nextState: ShiftShortcutState
        switch shiftShortcutState {
        case .lowercase:
            nextState = .shift
        case .shift:
            nextState = cyclesToCapsLock ? .capsLock : .lowercase
        case .capsLock:
            nextState = .lowercase
        }
        applyShiftShortcutState(nextState)
    }

    func toggleCapsLockShortcut() {
        if activeModifierKeys.contains(.capsLock) {
            activeModifierKeys.remove(.capsLock)
        } else {
            activeModifierKeys.insert(.capsLock)
        }
    }

    func prefersShiftLegend(for key: VirtualKey) -> Bool {
        guard key.shiftedLabel != nil else { return false }

        var isShifted = activeModifierKeys.contains(.shift)
        if key.respondsToCapsLock && activeModifierKeys.contains(.capsLock) {
            isShifted.toggle()
        }
        return isShifted
    }

    private func eventFlags(from modifiers: Set<ModifierToggleKey>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }

    private enum ShiftShortcutState {
        case lowercase
        case shift
        case capsLock
    }

    private var shiftShortcutState: ShiftShortcutState {
        if activeModifierKeys.contains(.capsLock) { return .capsLock }
        if activeModifierKeys.contains(.shift) { return .shift }
        return .lowercase
    }

    private func applyShiftShortcutState(_ state: ShiftShortcutState) {
        activeModifierKeys.subtract([.shift, .capsLock])
        switch state {
        case .lowercase:
            break
        case .shift:
            activeModifierKeys.insert(.shift)
        case .capsLock:
            activeModifierKeys.insert(.capsLock)
        }
    }
}

struct KeyboardOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: KeyboardOverlayViewModel
    let onKeyPressed: (VirtualKey, CGEventFlags) -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: metrics.windowCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.windowCornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.26), lineWidth: 1)
                    )

                VStack(spacing: metrics.rowSpacing) {
                    ForEach(Array(viewModel.rows.enumerated()), id: \.offset) { rowIndex, row in
                        let rowWidths = widths(for: row, metrics: metrics)

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
                                        .frame(width: keyWidth, height: metrics.keyHeight)
                                        .scaleEffect(isModifierLatched ? 0.9 : 1)
                                        .background(
                                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                                .fill(fillColor)
                                        )
                                        .overlay(
                                            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                                                .strokeBorder(strokeColor, lineWidth: 1)
                                        )
                                        .animation(keyAnimation, value: isModifierLatched)
                                        .animation(keyAnimation, value: prefersShiftLegend)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(metrics.innerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(metrics.outerPadding)
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

    private func widths(for row: [VirtualKey], metrics: KeyboardLayoutMetrics) -> [UUID: CGFloat] {
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
        guard !remainingKeys.isEmpty else { return resolved }

        let availableRemainingWidth = max(0, availableKeyWidth - fixedWidth)
        let minRemainingWidths = remainingKeys.map { minimumFittingWidth(for: $0, metrics: metrics) }
        let minRemainingSum = minRemainingWidths.reduce(CGFloat(0), +)

        if minRemainingSum > availableRemainingWidth, minRemainingSum > 0 {
            for (index, key) in remainingKeys.enumerated() {
                resolved[key.id] = availableRemainingWidth * (minRemainingWidths[index] / minRemainingSum)
            }
            return resolved
        }

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
        
        if let shortcutButton = controllerShortcutButton(for: key) {
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
        let outerPadding = max(6, min(14, side * 0.02))
        let innerPadding = max(10, min(20, side * 0.03))
        let rowSpacing = max(8, min(18, size.height * 0.03))
        let columnSpacing = max(6, min(14, size.width * 0.008))

        let contentWidth = max(1, size.width - ((outerPadding + innerPadding) * 2))
        let contentHeight = max(1, size.height - ((outerPadding + innerPadding) * 2))

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
            outerPadding: outerPadding,
            contentWidth: contentWidth,
            activeLegendFontSize: max(11, min(22, keyHeight * 0.35)),
            inactiveLegendFontSize: max(8, min(16, keyHeight * 0.23)),
            legendSpacing: max(1, min(6, keyHeight * 0.06)),
            commandSymbolFontSize: max(10, min(15, keyHeight * 0.24)),
            commandLabelFontSize: max(9, min(13, keyHeight * 0.2)),
            commandSymbolInset: max(4, min(9, keyHeight * 0.1)),
            commandLabelBottomInset: max(4, min(10, keyHeight * 0.11)),
            controllerGlyphSize: max(16, min(24, keyHeight * 0.35)),
            controllerGlyphInset: max(3, min(8, keyHeight * 0.1)),
            controllerFallbackFontSize: max(8, min(12, keyHeight * 0.18)),
            keyCornerRadius: max(8, min(14, keyHeight * 0.23)),
            outerKeyCornerRadius: max(12, min(20, keyHeight * 0.35)),
            windowCornerRadius: max(18, min(30, side * 0.06))
        )
    }

    private struct KeyboardLayoutMetrics {
        let baseUnitWidth: CGFloat
        let keyHeight: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let innerPadding: CGFloat
        let outerPadding: CGFloat
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
    KeyboardOverlayView(settings: AppSettings(), viewModel: KeyboardOverlayViewModel()) { key, _ in
        print("Pressed \(key.baseLabel)")
    }
    .frame(width: 840, height: 280)
}
