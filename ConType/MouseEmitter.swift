//
//  MouseEmitter.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/15/26.
//

import ApplicationServices
import AppKit

/// Handles posting CGEvents for mouse emulation
final class MouseEmitter {
    private var isMouseDown = false
    
    /// Moves the mouse cursor by a given delta relative to its current position.
    /// - Parameter delta: The `CGVector` of the mouse movement
    /// - Returns: `true` if the event was posted, `false` if mising permissions or event failed
    @discardableResult func moveCursor(by delta: CGVector) -> Bool {
        guard InputMonitoringPermission.isAuthorized() else { return false }
        let current = NSEvent.mouseLocation
        let eventType: CGEventType = isMouseDown ? .leftMouseDragged : .mouseMoved
        let newLocation = CGPoint(x: current.x + delta.dx, y: NSScreen.main!.frame.height - current.y + delta.dy)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: newLocation, mouseButton: .left) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    /// Moves the mouse cursor to an absolute location on the screen.
    /// - Parameter location: The `CGPoint` where the mouse should be moved to
    /// - Returns: `true` if the event was posted, `false` if mising permissions or event failed
    @discardableResult func moveCursor(to location: CGPoint) -> Bool {
        guard InputMonitoringPermission.isAuthorized() else { return false }
        let eventType: CGEventType = isMouseDown ? .leftMouseDragged : .mouseMoved
        guard let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: location, mouseButton: .left) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }
    
    /// Emits a mouse scroll by a given delta.
    /// - Parameter delta: The `CGVector` of the mouse scroll
    /// - Returns: `true` if the event was posted, `false` if mising permissions or event failed
    @discardableResult func scroll(_ delta: CGVector) -> Bool {
        guard InputMonitoringPermission.isAuthorized() else { return false }
        let px = Int(delta.dx)
        let py = Int(delta.dy)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(py), wheel2: Int32(px), wheel3: 0) else {
            return false
        }
        debugPrint(event)
        event.post(tap: .cghidEventTap)
        return true
    }
    
    /// Emits a mouse button based on the given button and mouse event type.
    /// - Parameters:
    ///   - button: The `CGMouseButton` to be emitted
    ///   - eventType: The `CGEventType` of the event. Such as `.leftMouseDown` or `.leftMouseUp`
    /// - Returns: `true` if the event was posted, `false` if mising permissions or event failed
    @discardableResult func emit(button: CGMouseButton, eventType: CGEventType) -> Bool {
        guard InputMonitoringPermission.isAuthorized() else { return false }
        
        let actualMousePosition = CGPoint(x: NSEvent.mouseLocation.x, y: NSScreen.main!.frame.height - NSEvent.mouseLocation.y)
        
        guard let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: actualMousePosition, mouseButton: button) else {
            return false
        }
        
        if eventType == .leftMouseDown || eventType == .rightMouseDown {
            isMouseDown = true
        } else if eventType == .leftMouseUp || eventType == .rightMouseUp {
            isMouseDown = false
        }
        
        event.post(tap: .cghidEventTap)
        return true
    }
}
