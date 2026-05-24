//
//  KeyboardOverlayViewModel.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/26/26.
//

import Combine
import ApplicationServices
import AppKit

/// An enum containing the different movement directions of the keyboard overlay.
/// - Contains:
///     - Up
///     - Down
///     - Left
///     - Right
///     - Up-Left
///     - Up-Right
///     - Down-Left
///     - Down-Right
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

/// An enum containing the source of the movement in the keyboard overlay.
/// - Contains:
///     - Press
///     - Hold Repeat
enum OverlayMoveTrigger {
    case press
    case holdRepeat
}

/// A struct containing the properties of a key, such as its identifier, size, placement and origin.
struct KeyReference: Equatable {
    let id: UUID
    let size: CGSize
    let rowIndex: Int
    let columnIndex: Int
    let xOrigin: CGFloat
}

/// An enum containing the two different modes for the movement bias.
/// - Contains:
///     - Preferring Closes
///     - Two Overlaps
enum SelectionBias {
    case overlapPreferringClosest // Prioritize overlap, then closest center
    case twoOverlaps              // Return up to two overlapping keys (caller needs to handle)
}

/// The view model for the keyboard overlay. Handles movement, key press, key activation, modifier handling and shift cycling.
@MainActor
final class KeyboardOverlayViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var keyboardLayout: KeyboardLayout
    @Published var keyRefs: [KeyReference] = []
    @Published private(set) var selectedRow = 0
    @Published private(set) var selectedColumn = 0
    @Published private(set) var activeModifierKeys: Set<ModifierToggleKey> = []

    var rows: [[VirtualKey]] { keyboardLayout.rows }
    var lastKeys: [KeyReference] = []
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        self.keyboardLayout = settings.keyboardLayout

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        settings.$keyboardLayout
            .sink { [weak self] value in
                self?.setKeyboardLayout(value)
            }
            .store(in: &cancellables)
    }
    
    /// Sets the active keyboard layout of the overlay.
    /// - Parameter layout: The `keyboardLayout` to load into the view
    func setKeyboardLayout(_ layout: KeyboardLayout) {
        self.keyboardLayout = layout
        selectedRow = 0
        selectedColumn = 0
        activeModifierKeys.removeAll()
        keyRefs.removeAll()
    }
    
    /// A property that stores the selected key as `VirtualKey`
    var selectedKey: VirtualKey? {
        guard rows.indices.contains(selectedRow) else { return nil }
        let row = rows[selectedRow]
        guard row.indices.contains(selectedColumn) else { return nil }
        return row[selectedColumn]
    }
    
    /// Moves the highlighted key into the chosen direction. Handles diagonals, edge wrapping and key prioritization.
    /// - Parameters:
    ///   - direction: The `OverlayMoveDirection`, where the move is towards
    ///   - trigger: The source of the movement, `OverlayMoveTrigger`
    /// - Returns: `true` if movement is successful, else `false`
    @discardableResult
    func move(_ direction: OverlayMoveDirection, trigger: OverlayMoveTrigger = .press) -> Bool {
        let previousRow = selectedRow
        let previousColumn = selectedColumn
        let allowsWrap = trigger == .press

        switch direction {
        case .left:
            if selectedColumn > 0 {
                /// If column is not the very left, move left.
                selectedColumn -= 1
            } else if allowsWrap {
                /// Else if `allowsWrap`, wrap around to the rightmost column.
                selectedColumn = max(0, rows[selectedRow].count - 1)
            }
            
        case .right:
            let maxColumn = max(0, rows[selectedRow].count - 1)
            if selectedColumn < maxColumn {
                /// If column is not the very right, move right.
                selectedColumn += 1
            } else if allowsWrap {
                /// Else if `allowsWrap`, wrap around to the leftmost column.
                selectedColumn = 0
            }
            
        case .up:
            if selectedRow > 0 || allowsWrap {
                /// If row is not the very top, target the row above. Else, wrap around and target the bottom row.
                let targetRow = selectedRow > 0 ? selectedRow - 1 : rows.count - 1
                
                
                /// Get the keys from the target row.
                let candidates = keyRefs.filter{ $0.rowIndex == targetRow }
                
                if let currentRef = keyRefs.first(where: { $0.rowIndex == selectedRow && $0.columnIndex == selectedColumn }),
                   let best = bestKeyFromCandidates(candidates: candidates, currentKeyReference: currentRef, selectionBias: .overlapPreferringClosest).first {
                    /// Get current key, find the best candidate with `bestKeyFromCandidates` and select best key preferring closes to key origin.
                    selectedRow = best.rowIndex
                    selectedColumn = best.columnIndex
                } else {
                    /// Else, move to target row without changing column.
                    selectedRow = targetRow
                }
            }
            
            /// Ensure selected column is within bounds
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
                    /// Get current key, find the best candidate with `bestKeyFromCandidates` and select the key towards the left of the current.
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
                    /// Get current key, find the best candidate with `bestKeyFromCandidates` and select the key towards the right of the current.
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
        
        /// Append current key into `lastKeys`.
        lastKeys.append(KeyReference(
            id: UUID(),
            size: .zero,
            rowIndex: selectedRow,
            columnIndex: selectedColumn,
            xOrigin: 0
        ))
        
        /// Limit to 5 saved keys at a time.
        lastKeys = Array(lastKeys.suffix(5))
        
        /// Return true if the key has changed
        return previousRow != selectedRow || previousColumn != selectedColumn
    }
    
    /// Updates the selected key variables based on the parameter.
    /// - Parameters:
    ///   - row: The row `Int` of the key to be selected
    ///   - column: The column `Int` of the key to be selected
    func select(row: Int, column: Int) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        selectedRow = row
        selectedColumn = column
    }
    
    /// Activates the selected key
    /// - Parameter emitter: The key and accompanying flag to be activated
    func activateSelected(using emitter: (VirtualKey, CGEventFlags) -> Void) {
        guard let key = selectedKey else { return }
        activate(key, using: emitter)
    }
    
    /// Activates a key and handles modifier keys and emit.
    /// - Parameters:
    ///   - key: The `VirtualKey` to be activated
    ///   - emitter: The key and accompanying flag to be activated
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
    
    /// Checks if a modifier is active.
    /// - Parameter modifier: The `ModifierToggleKey` to check status for
    /// - Returns: `true` if modifier is active, else `false`
    func isModifierActive(_ modifier: ModifierToggleKey) -> Bool {
        activeModifierKeys.contains(modifier)
    }
    
    /// Handles shifting between lowercase, shift and caps lock if applicable
    /// - Parameter cyclesToCapsLock: A `bool` deciding if the function should move from shift to caps lock, moves from shift to lowercase if false.
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
    
    /// Toggles the caps lock modifier
    func toggleCapsLockShortcut() {
        if activeModifierKeys.contains(.capsLock) {
            activeModifierKeys.remove(.capsLock)
        } else {
            activeModifierKeys.insert(.capsLock)
        }
    }
    
    /// Checks if the keyboard is in a shifted mode and if the key should be shifted.
    /// - Parameter key: The `VirtualKey` to check
    /// - Returns: `true` if modifier is active, else `false` if key has no shifted label or no modifier is active.
    func prefersShiftLegend(for key: VirtualKey) -> Bool {
        guard key.shiftedLabel != nil else { return false }

        var isShifted = activeModifierKeys.contains(.shift)
        if key.respondsToCapsLock && activeModifierKeys.contains(.capsLock) {
            isShifted.toggle()
        }
        return isShifted
    }
    
    /// Grabs the active modifiers from a set of `ModifierToggleKey` and turns them into `CGEventFlags`.
    /// - Parameter modifiers: The set of modifiers to check for
    /// - Returns: The set of `CGEventFlags` based on the active modifiers
    private func eventFlags(from modifiers: Set<ModifierToggleKey>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }
    
    /// The different states of key shifts
    private enum ShiftShortcutState {
        case lowercase
        case shift
        case capsLock
    }
    
    /// A property that returns the active key shift state
    private var shiftShortcutState: ShiftShortcutState {
        if activeModifierKeys.contains(.capsLock) { return .capsLock }
        if activeModifierKeys.contains(.shift) { return .shift }
        return .lowercase
    }
    
    /// Resets active modifier keys and applies the passed key shift state.
    /// - Parameter state: The `ShiftShortcutState` to activate.
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
    
    /// Determines the best key candidate based on multiple conditions;
    /// The overlap of the candidate keys' width over the current key,
    /// The bias over which key is selected,
    /// Wether either of the overlapping keys was in the previous keys list.
    /// - Parameters:
    ///   - candidates: The set of keys to check
    ///   - currentKeyReference: The current key to reference from
    ///   - selectionBias: The `SelectionBias` to decide wether to return one key or two
    /// - Returns: A `[KeyReference]` containing the overlapping key(s)
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

