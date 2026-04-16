//
//  MouseEmitter.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/15/26.
//

import ApplicationServices
import AppKit

final class MouseEmitter {
    /// Moves the mouse cursor by a given delta (dx, dy) relative to its current position.
    /// Returns true if the event was posted, false if accessibility permissions are missing.
    @discardableResult
    func moveCursor(by delta: CGVector) -> Bool {
        guard AccessibilityPermission.isTrusted() else { return false }
        let current = NSEvent.mouseLocation
        // Note: NSEvent.mouseLocation uses a flipped origin (bottom-left is (0,0)),
        // but CGEvent expects screen coordinates (origin at bottom-left)
        let newLocation = CGPoint(x: current.x + delta.dx, y: NSScreen.main!.frame.height - current.y + delta.dy)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newLocation, mouseButton: .left) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        debugPrint("Emitting mouse event: \(event)")
        return true
    }

    /// Moves the mouse cursor to an absolute location on the screen.
    /// Returns true if the event was posted, false if accessibility permissions are missing.
    @discardableResult
    func moveCursor(to location: CGPoint) -> Bool {
        guard AccessibilityPermission.isTrusted() else { return false }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    func emit(button: CGMouseButton, eventType: CGEventType) -> Bool {
        guard AccessibilityPermission.isTrusted() else { return false }
        
        let actualMousePosition = CGPoint(x: NSEvent.mouseLocation.x, y: NSScreen.main!.frame.height - NSEvent.mouseLocation.y)
        
        guard let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: actualMousePosition, mouseButton: button) else {
            return false
        }
        
        event.post(tap: .cghidEventTap)
        return true
    }
}
