//
//  KeyEmitter.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import ApplicationServices

/// Handles posting CGEvents for keyboard emulation
final class KeyEmitter {
    /// Wraps `emit()` that accepts a `CGKeyCode` and parses `VirtualKey`'s  key code.
    /// - Parameters:
    ///   - key: The `VirtualKey` to be emitted
    ///   - modifiers: the `CGEventFlags` to apply
    /// - Returns: `true` if emitted successfuly, else `false`
    @discardableResult
    func emit(_ key: VirtualKey, modifiers: CGEventFlags = []) -> Bool {
        emit(keyCode: key.keyCode, modifiers: modifiers)
    }
    
    /// Posts a CGEvent of the key down and key up of the given key code and modifier.
    /// - Parameters:
    ///   - keyCode: The `CGKeyCode` to be emitted
    ///   - modifiers: The `CGEventFlags` to be passed
    /// - Returns: `true` if emitted successfuly, else `false`
    @discardableResult
    func emit(keyCode: CGKeyCode, modifiers: CGEventFlags = []) -> Bool {
        guard InputMonitoringPermission.isAuthorized() else { return false }

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        // Post once via the session event tap to avoid duplicate key delivery.
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
