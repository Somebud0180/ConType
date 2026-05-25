//
//  OverlayPositionGuideView.swift
//  ConType
//
//  Created by Ethan John Lagera on 5/21/26.
//

import Combine
import SwiftUI

/// Types of overlay position guides used by the UI.
/// Contains:
/// - `keyboard` — guide used when positioning the keyboard overlay.
/// - `mouse` — guide used when positioning the mouse overlay.
enum OverlayPositionGuideKind: String {
    case keyboard
    case mouse
}

/// Represents a single overlay guide target on screen.
/// - Properties:
///   - `kind`: The kind of guide (`OverlayPositionGuideKind`).
///   - `frame`: The target frame in global (screen) coordinates.
struct OverlayPositionGuideTarget: Equatable {
    let kind: OverlayPositionGuideKind
    let frame: CGRect
}

@MainActor
/// Observable model that tracks the overlay guide state for rendering.
/// Properties:
/// - `screenFrame` (global screen bounds used for coordinate conversion)
/// - `targets` (an array of `OverlayPositionGuideTarget` representing current guide targets)
/// - `isVisible` (returns the visibility state based on `screenFrame` and `targets`)
/// - `clear()` (resets the model state)
final class OverlayPositionGuideModel: ObservableObject {
    @Published var screenFrame: CGRect = .zero
    @Published var targets: [OverlayPositionGuideTarget] = []
    
    /// Whether the guide should be shown (has targets and a valid screen frame).
    var isVisible: Bool {
        !targets.isEmpty && !screenFrame.isEmpty
    }
    
    /// Reset the model state.
    func clear() {
        screenFrame = .zero
        targets = []
    }
}

/// SwiftUI view that renders visual position guides for overlay targets.
/// Renders ghost outlines and guide lines based on the `OverlayPositionGuideModel` state.
struct OverlayPositionGuideView: View {
    @ObservedObject var model: OverlayPositionGuideModel
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(model.targets.enumerated()), id: \.offset) { _, target in
                    guideView(for: target, in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .allowsHitTesting(false)
    }
    
    /// Build the visual guide for a single `OverlayPositionGuideTarget`.
    /// - Parameters:
    ///   - target: The target descriptor (kind + global frame).
    ///   - size: The local drawing size provided by the parent `GeometryReader`.
    ///- Returns: A SwiftUI view representing the guide for the target, positioned according to the converted local frame.
    @ViewBuilder
    private func guideView(for target: OverlayPositionGuideTarget, in size: CGSize) -> some View {
        let localFrame = localFrame(for: target.frame, in: size)
        let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 6])
        let cornerRadius = max(18, min(30, min(size.width, size.height) * 0.06))
        
        switch target.kind {
        case .keyboard:
            ZStack {
                // MARK: Ghost Overlay Outline
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.28), style: strokeStyle)
                    )
                
                // MARK: Vertical Guide Lines
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: -size.height))
                        path.addLine(to: CGPoint(x: 0, y: size.height * 2))
                    }
                    .stroke(Color.primary.opacity(0.20), style: strokeStyle)
                    
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width, y: -size.height))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: size.height * 2))
                    }
                    .stroke(Color.primary.opacity(0.20), style: strokeStyle)
                }
            }
            .frame(width: localFrame.width, height: localFrame.height)
            .position(x: localFrame.midX, y: localFrame.midY)
            .allowsHitTesting(false)
            .transition(.opacity)
        case .mouse:
            // MARK: Ghost Overlay Outline
            Circle()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.28), style: strokeStyle)
                )
                .frame(width: localFrame.width, height: localFrame.height)
                .position(x: localFrame.midX, y: localFrame.midY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
    
    /// Convert a global (screen) `CGRect` into local view coordinates.
    /// - Parameters:
    ///   - globalFrame: The target frame expressed in screen (global) coordinates.
    ///   - size: The local view size (height is used to flip the y-axis).
    /// - Returns: A `CGRect` positioned in the local coordinate space. Returns `.zero` if
    ///   `model.screenFrame` is empty.
    /// - Notes: The implementation subtracts `model.screenFrame.origin` and flips the y-axis
    ///   to match SwiftUI coordinate space.
    private func localFrame(for globalFrame: CGRect, in size: CGSize) -> CGRect {
        guard !model.screenFrame.isEmpty else { return .zero }
        let x = globalFrame.minX - model.screenFrame.minX
        let y = size.height - (globalFrame.maxY - model.screenFrame.minY)
        return CGRect(origin: CGPoint(x: x, y: y), size: globalFrame.size)
    }
}
