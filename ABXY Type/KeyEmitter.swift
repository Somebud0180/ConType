import ApplicationServices

final class KeyEmitter {
    @discardableResult
    func emit(_ key: VirtualKey, modifiers: CGEventFlags = []) -> Bool {
        emit(keyCode: key.keyCode, modifiers: modifiers)
    }

    @discardableResult
    func emit(keyCode: CGKeyCode, modifiers: CGEventFlags = []) -> Bool {
        guard AXIsProcessTrusted() else { return false }

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
