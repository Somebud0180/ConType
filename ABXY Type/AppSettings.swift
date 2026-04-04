import AppKit
import Foundation
import Combine

enum ControllerFaceButton: String, CaseIterable, Identifiable {
    case south
    case east
    case west
    case north

    var id: String { rawValue }

    var title: String {
        switch self {
        case .south: return "A"
        case .east: return "B"
        case .west: return "X"
        case .north: return "Y"
        }
    }
}

struct ControllerToggleBinding: Equatable {
    var faceButton: ControllerFaceButton

    static let `default` = ControllerToggleBinding(faceButton: .west)

    var title: String {
        "Guide + \(faceButton.title)"
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var keyboardHotkey = KeyboardHotkeyManager.Shortcut(key: "k", modifiers: [.command])
    @Published var controllerToggleBinding: ControllerToggleBinding = .default
    @Published var invertControllerFaceButtons = false
}
