import Combine
import SwiftUI

enum OverlayPositionGuideKind: String {
    case keyboard
    case mouse
}

struct OverlayPositionGuideTarget: Equatable {
    let kind: OverlayPositionGuideKind
    let frame: CGRect
}

@MainActor
final class OverlayPositionGuideModel: ObservableObject {
    @Published var screenFrame: CGRect = .zero
    @Published var targets: [OverlayPositionGuideTarget] = []
    
    var isVisible: Bool {
        !targets.isEmpty && !screenFrame.isEmpty
    }
    
    func clear() {
        screenFrame = .zero
        targets = []
    }
}

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
    
    @ViewBuilder
    private func guideView(for target: OverlayPositionGuideTarget, in size: CGSize) -> some View {
        let localFrame = localFrame(for: target.frame, in: size)
        let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 6])
        let cornerRadius = max(12, min(localFrame.width, localFrame.height) * 0.15)
        
        switch target.kind {
        case .keyboard:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.28), style: strokeStyle)
                )
                .frame(width: localFrame.width, height: localFrame.height)
                .position(x: localFrame.midX, y: localFrame.midY)
                .allowsHitTesting(false)
                .transition(.opacity)
        case .mouse:
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
    
    private func localFrame(for globalFrame: CGRect, in size: CGSize) -> CGRect {
        guard !model.screenFrame.isEmpty else { return .zero }
        let x = globalFrame.minX - model.screenFrame.minX
        let y = size.height - (globalFrame.maxY - model.screenFrame.minY)
        return CGRect(origin: CGPoint(x: x, y: y), size: globalFrame.size)
    }
}
