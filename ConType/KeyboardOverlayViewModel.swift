//
//  KeyboardOverlayViewModel.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/26/26.
//

import Combine
import ApplicationServices
import AppKit

enum OverlayMoveDirection {
    case up
    case down
    case left
    case right
    case upLeft
    case upRight
    case downLeft
    case downRight
}

enum OverlayMoveTrigger {
    case press
    case holdRepeat
}

struct KeyReference: Equatable {
    let id: UUID
    let size: CGSize
    let rowIndex: Int
    let columnIndex: Int
    let xOrigin: CGFloat
}

enum SelectionBias {
    case overlapPreferringClosest // Prioritize overlap, then closest center
    case twoOverlaps              // Return up to two overlapping keys (caller needs to handle)
}

@MainActor
final class KeyboardOverlayViewModel: ObservableObject {
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    
    @Published var keyboardLayout: KeyboardLayout
    @Published var keyRefs: [KeyReference] = []
    @Published private(set) var selectedRow = 0
    @Published private(set) var selectedColumn = 0
    @Published private(set) var activeModifierKeys: Set<ModifierToggleKey> = []

    var rows: [[VirtualKey]] { keyboardLayout.rows }
    var lastKeys: [KeyReference] = []

    init(settings: AppSettings) {
        self.settings = settings
        self.keyboardLayout = settings.keyboardLayout
        
        settings.$keyboardLayout
            .sink { [weak self] value in
                self?.setKeyboardLayout(value)
            }
            .store(in: &cancellables)
    }

    func setKeyboardLayout(_ layout: KeyboardLayout) {
        self.keyboardLayout = layout
        selectedRow = 0
        selectedColumn = 0
        activeModifierKeys.removeAll()
        keyRefs.removeAll()
    }

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
            if selectedRow > 0 || allowsWrap {
                let targetRow = selectedRow > 0 ? selectedRow - 1 : rows.count - 1
                let candidates = keyRefs.filter{ $0.rowIndex == targetRow }
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .overlapPreferringClosest).first {
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    selectedRow = targetRow
                }
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
            
        case .down:
            if selectedRow < rows.count - 1 || allowsWrap {
                let targetRow = selectedRow < rows.count - 1 ? selectedRow + 1 : 0
                let candidates = keyRefs.filter { $0.rowIndex == targetRow }
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .overlapPreferringClosest).first {
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    selectedRow = targetRow
                }
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
            
        case .upLeft:
            if selectedRow > 0 || allowsWrap {
                let targetRow = selectedRow > 0 ? selectedRow - 1 : rows.count - 1
                let candidates = keyRefs.filter { $0.rowIndex == targetRow }
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .twoOverlaps).first {
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    selectedRow = targetRow
                    selectedColumn = max(0, selectedColumn - 1)
                }
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
            
        case .upRight:
            if selectedRow > 0 || allowsWrap {
                let targetRow = selectedRow > 0 ? selectedRow - 1 : rows.count - 1
                let candidates = keyRefs.filter { $0.rowIndex == targetRow }
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .twoOverlaps).last {
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    selectedRow = targetRow
                    selectedColumn += 1
                }
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
            
        case .downLeft:
            if selectedRow < rows.count - 1 || allowsWrap {
                let targetRow = selectedRow < rows.count - 1 ? selectedRow + 1 : 0
                let candidates = keyRefs.filter { $0.rowIndex == targetRow }
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .twoOverlaps).first {
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    selectedRow = targetRow
                    selectedColumn = max(0, selectedColumn - 1)
                }
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
            
        case .downRight:
            if selectedRow < rows.count - 1 || allowsWrap {
                let targetRow = selectedRow < rows.count - 1 ? selectedRow + 1 : 0
                let candidates = keyRefs.filter { $0.rowIndex == targetRow }
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .twoOverlaps).last {
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    selectedRow = targetRow
                    selectedColumn += 1
                }
            }
            selectedColumn = min(selectedColumn, rows[selectedRow].count - 1)
        }
        
        lastKeys.append(KeyReference(
            id: UUID(),
            size: .zero,
            rowIndex: selectedRow,
            columnIndex: selectedColumn,
            xOrigin: 0
        ))
        lastKeys = Array(lastKeys.suffix(5))
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
    
    func bestKeyFromCandidates(
        candidates: [KeyReference],
        currentKeyReference: KeyReference,
        selectionBias: SelectionBias = .overlapPreferringClosest
    ) -> [KeyReference] {
        guard !candidates.isEmpty else { return [] }
        
        let currentKeyLeft = currentKeyReference.xOrigin
        let currentKeyRight = currentKeyReference.xOrigin + currentKeyReference.size.width
        let currentKeyCenterX = currentKeyLeft + (currentKeyReference.size.width / 2.0)
        
        struct CandidateMatch {
            let ref: KeyReference
            let overlap: CGFloat
            let distance: CGFloat
        }
        
        var matches: [CandidateMatch] = []
        var closestFallback: KeyReference? = nil
        var minDistance = CGFloat.greatestFiniteMagnitude
        
        for candidate in candidates {
            let candidateLeft = candidate.xOrigin
            let candidateRight = candidate.xOrigin + candidate.size.width
            let candidateCenterX = candidateLeft + (candidate.size.width / 2.0)
            
            let overlap = min(currentKeyRight, candidateRight) - max(currentKeyLeft, candidateLeft)
            let distance = abs(candidateCenterX - currentKeyCenterX)
            
            if overlap > 0 {
                matches.append(CandidateMatch(ref: candidate, overlap: overlap, distance: distance))
            }
            
            if distance < minDistance {
                minDistance = distance
                closestFallback = candidate
            }
        }
        
        for lastKey in lastKeys.reversed() {
            let matching = matches.filter { $0.ref.rowIndex == lastKey.rowIndex && $0.ref.columnIndex == lastKey.columnIndex }
            if !matching.isEmpty {
                return matching.map { $0.ref }
            }
        }
        
        // Sort by overlap width descending, then by center distance ascending
        matches.sort { lhs, rhs in
            if abs(lhs.overlap - rhs.overlap) > 0.001 {
                return lhs.overlap > rhs.overlap
            }
            return lhs.distance < rhs.distance
        }
        
        let sortedRefs = matches.map { $0.ref }
        
        switch selectionBias {
        case .overlapPreferringClosest:
            if let best = sortedRefs.first {
                return [best]
            }
            return closestFallback.map { [$0] } ?? []
            
        case .twoOverlaps:
            if !sortedRefs.isEmpty {
                // Return top two overlaps, but sorted by X origin so .first is left and .last is right
                return Array(sortedRefs.prefix(2)).sorted { $0.xOrigin < $1.xOrigin }
            }
            return closestFallback.map { [$0] } ?? []
        }
    }
}

