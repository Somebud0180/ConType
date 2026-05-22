//
//  WindowSnappingManager.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/22/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlaySnappingManager: ObservableObject {
    var keyboardSnapDistance: CGFloat = 72
    var mouseSnapDistance: CGFloat = 44
    
    private let settings: AppSettings
    weak var keyboardWindow: NSWindow?
    weak var mouseWindow: NSWindow?
    
    private let positionGuideModel = OverlayPositionGuideModel()
    private var positionGuideWindow: NSWindow?
    private var guideHideWorkItem: DispatchWorkItem?
    
    @Published var keyboardSnapLockOrigin: NSPoint?
    @Published var mouseSnapLockOrigin: NSPoint?
    @Published var keyboardSnapSuppressionOrigin: NSPoint?
    @Published var mouseSnapSuppressionOrigin: NSPoint?
    @Published var isApplyingProgrammaticSnap = false
    @Published var keyboardSessionHasSnap = false
    @Published var mouseSessionHasSnap = false
    @Published var dragStartMouseLocation: NSPoint = .zero
    @Published var dragStartWindowOrigin: NSPoint = .zero
    @Published var virtualWindowOrigin: NSPoint = .zero
    
    init(settings: AppSettings, keyboardWindow: NSWindow? = nil, mouseWindow: NSWindow? = nil) {
        self.settings = settings
        self.keyboardWindow = keyboardWindow
        self.mouseWindow = mouseWindow
    }
    
    func makePositionGuideWindowIfNeeded(for screenFrame: NSRect) -> NSWindow {
        if let positionGuideWindow {
            if positionGuideWindow.frame != screenFrame {
                positionGuideWindow.setFrame(screenFrame, display: false)
            }
            return positionGuideWindow
        }
        
        let hostingController = NSHostingController(
            rootView: OverlayPositionGuideView(model: positionGuideModel)
        )
        let baseMask: NSWindow.StyleMask = [
            .borderless, .fullSizeContentView,
        ]
        let window = NonActivatingOverlayPanel(
            contentRect: screenFrame,
            styleMask: baseMask.union(.nonactivatingPanel),
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        
        self.positionGuideWindow = window
        return window
    }
    
    func refreshPositionGuide(for window: NSWindow) {
        guard let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else {
            clearPositionGuide()
            return
        }
        
        let screenRect = NSRect(origin: screenFrame.origin, size: screenFrame.size)
        positionGuideModel.screenFrame = screenRect
        
        if window == keyboardWindow {
            let targetFrame = keyboardGuideTargetFrame(for: window.frame, screenFrame: screenRect)
            let distance = centerDistance(between: window.frame, and: targetFrame)
            let revealDistance: CGFloat = 88
            let snapDistance: CGFloat = 24
            let releaseDistance: CGFloat = keyboardSessionHasSnap ? 156 : 96
            let suppressionDistance: CGFloat = keyboardSessionHasSnap ? 100 : 68
            
            if let snapOrigin = keyboardSnapLockOrigin {
                let movedAwayDistance = originDistance(between: window.frame.origin, and: snapOrigin)
                if movedAwayDistance < releaseDistance {
                    clearPositionGuide()
                    return
                }
                keyboardSnapSuppressionOrigin = snapOrigin
                keyboardSnapLockOrigin = nil
            }
            
            if let suppressionOrigin = keyboardSnapSuppressionOrigin {
                let suppressionOffset = originDistance(between: window.frame.origin, and: suppressionOrigin)
                if suppressionOffset < suppressionDistance {
                    clearPositionGuide()
                    return
                }
                keyboardSnapSuppressionOrigin = nil
            }
            
            if distance <= snapDistance {
                snapKeyboardWindow(to: targetFrame.origin)
                clearPositionGuide()
                return
            }
            
            if distance <= revealDistance && distance > 1 {
                positionGuideModel.targets = [OverlayPositionGuideTarget(kind: .keyboard, frame: targetFrame)]
                makePositionGuideWindowIfNeeded(for: screenRect).orderFrontRegardless()
            } else {
                clearPositionGuide()
            }
        } else if window == mouseWindow {
            let targets = mouseGuideTargets(for: window.frame.size, screenFrame: screenRect)
            guard let nearestTarget = targets.min(by: {
                originDistance(between: window.frame.origin, and: $0.frame.origin) < originDistance(between: window.frame.origin, and: $1.frame.origin)
            }) else {
                clearPositionGuide()
                return
            }
            
            let distance = originDistance(between: window.frame.origin, and: nearestTarget.frame.origin)
            let revealDistance: CGFloat = 52
            let snapDistance: CGFloat = 18
            let releaseDistance: CGFloat = mouseSessionHasSnap ? 108 : 64
            let suppressionDistance: CGFloat = mouseSessionHasSnap ? 72 : 44
            
            if let snapOrigin = mouseSnapLockOrigin {
                let movedAwayDistance = originDistance(between: window.frame.origin, and: snapOrigin)
                if movedAwayDistance < releaseDistance {
                    clearPositionGuide()
                    return
                }
                mouseSnapSuppressionOrigin = snapOrigin
                mouseSnapLockOrigin = nil
            }
            
            if let suppressionOrigin = mouseSnapSuppressionOrigin {
                let suppressionOffset = originDistance(between: window.frame.origin, and: suppressionOrigin)
                if suppressionOffset < suppressionDistance {
                    clearPositionGuide()
                    return
                }
                mouseSnapSuppressionOrigin = nil
            }
            
            if distance <= snapDistance {
                snapMouseWindow(to: nearestTarget.frame.origin)
                clearPositionGuide()
                return
            }
            
            if distance <= revealDistance && distance > 1 {
                positionGuideModel.targets = [nearestTarget]
                makePositionGuideWindowIfNeeded(for: screenRect).orderFrontRegardless()
            } else {
                clearPositionGuide()
            }
        } else {
            clearPositionGuide()
        }
    }
    
    func clearPositionGuide() {
        guideHideWorkItem?.cancel()
        guideHideWorkItem = nil
        positionGuideWindow?.orderOut(nil)
        positionGuideModel.clear()
    }
    
    func scheduleGuideAutoHide() {
        guideHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.guideHideWorkItem = nil
            self?.positionGuideWindow?.orderOut(nil)
            self?.positionGuideModel.clear()
            self?.keyboardSessionHasSnap = false
            self?.mouseSessionHasSnap = false
        }
        guideHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }
    
    func snapKeyboardWindow(to origin: NSPoint) {
        guard let keyboardWindow, keyboardWindow.frame.origin != origin else { return }
        isApplyingProgrammaticSnap = true
        keyboardWindow.setFrameOrigin(origin)
        isApplyingProgrammaticSnap = false
        keyboardSnapLockOrigin = origin
        keyboardSnapSuppressionOrigin = nil
        keyboardSessionHasSnap = true
        settings.keyboardWindowPosition = origin
    }
    
    func snapMouseWindow(to origin: NSPoint) {
        guard let mouseWindow, mouseWindow.frame.origin != origin else { return }
        isApplyingProgrammaticSnap = true
        mouseWindow.setFrameOrigin(origin)
        isApplyingProgrammaticSnap = false
        mouseSnapLockOrigin = origin
        mouseSnapSuppressionOrigin = nil
        mouseSessionHasSnap = true
        settings.mouseWindowPosition = origin
    }
    
    func keyboardGuideTargetFrame(for currentFrame: NSRect, screenFrame: NSRect) -> NSRect {
        NSRect(
            x: screenFrame.midX - (currentFrame.width / 2),
            y: screenFrame.midY - (currentFrame.height / 2),
            width: currentFrame.width,
            height: currentFrame.height
        )
    }
    
    func mouseGuideTargets(for windowSize: NSSize, screenFrame: NSRect) -> [OverlayPositionGuideTarget] {
        let inset: CGFloat = 16
        let width = windowSize.width
        let height = windowSize.height
        
        let bottomLeft = NSRect(
            x: screenFrame.minX + inset,
            y: screenFrame.minY + inset,
            width: width,
            height: height
        )
        let bottomRight = NSRect(
            x: max(screenFrame.minX + inset, screenFrame.maxX - inset - width),
            y: screenFrame.minY + inset,
            width: width,
            height: height
        )
        let topLeft = NSRect(
            x: screenFrame.minX + inset,
            y: max(screenFrame.minY + inset, screenFrame.maxY - inset - height),
            width: width,
            height: height
        )
        let topRight = NSRect(
            x: max(screenFrame.minX + inset, screenFrame.maxX - inset - width),
            y: max(screenFrame.minY + inset, screenFrame.maxY - inset - height),
            width: width,
            height: height
        )
        
        return [
            OverlayPositionGuideTarget(kind: .mouse, frame: bottomLeft),
            OverlayPositionGuideTarget(kind: .mouse, frame: bottomRight),
            OverlayPositionGuideTarget(kind: .mouse, frame: topLeft),
            OverlayPositionGuideTarget(kind: .mouse, frame: topRight)
        ]
    }
    
    func centerDistance(between first: NSRect, and second: NSRect) -> CGFloat {
        hypot(first.midX - second.midX, first.midY - second.midY)
    }
    
    func originDistance(between first: NSPoint, and second: NSPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
    
    func handleWindowDrag(phase: DragPhase, window: NSWindow) {
        let currentGlobalMouse = NSEvent.mouseLocation
        
        switch phase {
        case .began:
            dragStartMouseLocation = currentGlobalMouse
            dragStartWindowOrigin = window.frame.origin
            virtualWindowOrigin = window.frame.origin
            
        case .changed:
            let deltaX = currentGlobalMouse.x - dragStartMouseLocation.x
            let deltaY = currentGlobalMouse.y - dragStartMouseLocation.y
            virtualWindowOrigin = NSPoint(
                x: dragStartWindowOrigin.x + deltaX,
                y: dragStartWindowOrigin.y + deltaY
            )
            
            let isKeyboard = (window === keyboardWindow)
            let isSnapped = isKeyboard ? keyboardSessionHasSnap : mouseSessionHasSnap
            let snapOrigin = isKeyboard ? keyboardSnapLockOrigin : mouseSnapLockOrigin
            
            if isSnapped, let snapPoint = snapOrigin {
                let pullDistance = originDistance(between: virtualWindowOrigin, and: snapPoint)
                let breakoutThreshold: CGFloat = isKeyboard ? keyboardSnapDistance : mouseSnapDistance
                
                if pullDistance > breakoutThreshold {
                    // Break out of the snap
                    if isKeyboard {
                        keyboardSessionHasSnap = false
                        keyboardSnapLockOrigin = nil
                    } else {
                        mouseSessionHasSnap = false
                        mouseSnapLockOrigin = nil
                    }
                    window.setFrameOrigin(virtualWindowOrigin)
                    refreshPositionGuide(for: window)
                }
            } else {
                window.setFrameOrigin(virtualWindowOrigin)
                refreshPositionGuide(for: window)
            }
            
        case .ended:
            break
        }
    }
}
