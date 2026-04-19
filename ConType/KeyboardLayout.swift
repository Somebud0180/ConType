//
//  KeyboardLayout.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/19/26.
//

import AppKit

struct VirtualKey: Identifiable, Hashable {
    let id = UUID()
    let baseLabel: String
    let shiftedLabel: String?
    let keyCode: CGKeyCode
    let widthUnits: CGFloat
    let role: VirtualKeyRole
    let usesRemainingSpace: Bool

    init(
        baseLabel: String,
        shiftedLabel: String? = nil,
        keyCode: CGKeyCode,
        widthUnits: CGFloat = 1,
        role: VirtualKeyRole = .standard,
        usesRemainingSpace: Bool = false
    ) {
        self.baseLabel = baseLabel
        self.shiftedLabel = shiftedLabel
        self.keyCode = keyCode
        self.widthUnits = widthUnits
        self.role = role
        self.usesRemainingSpace = usesRemainingSpace
    }

    var respondsToCapsLock: Bool {
        baseLabel.count == 1
            && baseLabel.unicodeScalars.allSatisfy(
                CharacterSet.letters.contains
            )
    }

    var isAlphanumeric: Bool {
        baseLabel.count == 1
            && baseLabel.unicodeScalars.allSatisfy(
                CharacterSet.alphanumerics.contains
            )
    }
}

enum VirtualKeyRole: Hashable {
    case standard
    case toggleModifier(ModifierToggleKey)
}

enum ModifierToggleKey: Hashable {
    case control
    case option
    case command
    case shift
    case capsLock
}

struct KeyboardLayout: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let rows: [[VirtualKey]]
    
    static let all: [KeyboardLayout] = [
        KeyboardLayout.QWERTY,
        KeyboardLayout.alignedQWERTY,
        // Add more layouts here
    ]
}

extension KeyboardLayout {
    static let QWERTY = KeyboardLayout(
        name: "QWERTY",
        rows: [
            [
                VirtualKey(baseLabel: "`", shiftedLabel: "~", keyCode: 50),
                VirtualKey(baseLabel: "1", shiftedLabel: "!", keyCode: 18),
                VirtualKey(baseLabel: "2", shiftedLabel: "@", keyCode: 19),
                VirtualKey(baseLabel: "3", shiftedLabel: "#", keyCode: 20),
                VirtualKey(baseLabel: "4", shiftedLabel: "$", keyCode: 21),
                VirtualKey(baseLabel: "5", shiftedLabel: "%", keyCode: 23),
                VirtualKey(baseLabel: "6", shiftedLabel: "^", keyCode: 22),
                VirtualKey(baseLabel: "7", shiftedLabel: "&", keyCode: 26),
                VirtualKey(baseLabel: "8", shiftedLabel: "*", keyCode: 28),
                VirtualKey(baseLabel: "9", shiftedLabel: "(", keyCode: 25),
                VirtualKey(baseLabel: "0", shiftedLabel: ")", keyCode: 29),
                VirtualKey(baseLabel: "-", shiftedLabel: "_", keyCode: 27),
                VirtualKey(baseLabel: "=", shiftedLabel: "+", keyCode: 24),
                VirtualKey(baseLabel: "Delete", keyCode: 51, widthUnits: 2)
            ],
            [
                VirtualKey(baseLabel: "Tab", keyCode: 48, widthUnits: 1.5),
                VirtualKey(baseLabel: "q", shiftedLabel: "Q", keyCode: 12),
                VirtualKey(baseLabel: "w", shiftedLabel: "W", keyCode: 13),
                VirtualKey(baseLabel: "e", shiftedLabel: "E", keyCode: 14),
                VirtualKey(baseLabel: "r", shiftedLabel: "R", keyCode: 15),
                VirtualKey(baseLabel: "t", shiftedLabel: "T", keyCode: 17),
                VirtualKey(baseLabel: "y", shiftedLabel: "Y", keyCode: 16),
                VirtualKey(baseLabel: "u", shiftedLabel: "U", keyCode: 32),
                VirtualKey(baseLabel: "i", shiftedLabel: "I", keyCode: 34),
                VirtualKey(baseLabel: "o", shiftedLabel: "O", keyCode: 31),
                VirtualKey(baseLabel: "p", shiftedLabel: "P", keyCode: 35),
                VirtualKey(baseLabel: "[", shiftedLabel: "{", keyCode: 33),
                VirtualKey(baseLabel: "]", shiftedLabel: "}", keyCode: 30),
                VirtualKey(
                    baseLabel: "\\",
                    shiftedLabel: "|",
                    keyCode: 42,
                    widthUnits: 1.5
                ),
            ],
            [
                VirtualKey(
                    baseLabel: "Caps Lock",
                    keyCode: 57,
                    role: .toggleModifier(.capsLock),
                    usesRemainingSpace: true
                ),
                VirtualKey(baseLabel: "a", shiftedLabel: "A", keyCode: 0),
                VirtualKey(baseLabel: "s", shiftedLabel: "S", keyCode: 1),
                VirtualKey(baseLabel: "d", shiftedLabel: "D", keyCode: 2),
                VirtualKey(baseLabel: "f", shiftedLabel: "F", keyCode: 3),
                VirtualKey(baseLabel: "g", shiftedLabel: "G", keyCode: 5),
                VirtualKey(baseLabel: "h", shiftedLabel: "H", keyCode: 4),
                VirtualKey(baseLabel: "j", shiftedLabel: "J", keyCode: 38),
                VirtualKey(baseLabel: "k", shiftedLabel: "K", keyCode: 40),
                VirtualKey(baseLabel: "l", shiftedLabel: "L", keyCode: 37),
                VirtualKey(baseLabel: ";", shiftedLabel: ":", keyCode: 41),
                VirtualKey(baseLabel: "'", shiftedLabel: "\"", keyCode: 39),
                VirtualKey(
                    baseLabel: "Return",
                    keyCode: 36,
                    usesRemainingSpace: true
                ),
            ],
            [
                VirtualKey(
                    baseLabel: "Shift",
                    keyCode: 56,
                    role: .toggleModifier(.shift),
                    usesRemainingSpace: true
                ),
                VirtualKey(baseLabel: "z", shiftedLabel: "Z", keyCode: 6),
                VirtualKey(baseLabel: "x", shiftedLabel: "X", keyCode: 7),
                VirtualKey(baseLabel: "c", shiftedLabel: "C", keyCode: 8),
                VirtualKey(baseLabel: "v", shiftedLabel: "V", keyCode: 9),
                VirtualKey(baseLabel: "b", shiftedLabel: "B", keyCode: 11),
                VirtualKey(baseLabel: "n", shiftedLabel: "N", keyCode: 45),
                VirtualKey(baseLabel: "m", shiftedLabel: "M", keyCode: 46),
                VirtualKey(baseLabel: ",", shiftedLabel: "<", keyCode: 43),
                VirtualKey(baseLabel: ".", shiftedLabel: ">", keyCode: 47),
                VirtualKey(baseLabel: "/", shiftedLabel: "?", keyCode: 44),
                VirtualKey(
                    baseLabel: "Shift",
                    keyCode: 60,
                    role: .toggleModifier(.shift),
                    usesRemainingSpace: true
                ),
            ],
            [
                VirtualKey(
                    baseLabel: "Control",
                    keyCode: 59,
                    role: .toggleModifier(.control)
                ),
                VirtualKey(
                    baseLabel: "Option",
                    keyCode: 58,
                    role: .toggleModifier(.option)
                ),
                VirtualKey(
                    baseLabel: "Command",
                    keyCode: 55,
                    widthUnits: 1.2,
                    role: .toggleModifier(.command)
                ),
                VirtualKey(
                    baseLabel: "Space",
                    keyCode: 49,
                    usesRemainingSpace: true
                ),
            ],
        ]
    )

    static let alignedQWERTY = KeyboardLayout(
        name: "QWERTY (Aligned)",
        rows: [
            [
                VirtualKey(baseLabel: "`", shiftedLabel: "~", keyCode: 50),
                VirtualKey(baseLabel: "1", shiftedLabel: "!", keyCode: 18),
                VirtualKey(baseLabel: "2", shiftedLabel: "@", keyCode: 19),
                VirtualKey(baseLabel: "3", shiftedLabel: "#", keyCode: 20),
                VirtualKey(baseLabel: "4", shiftedLabel: "$", keyCode: 21),
                VirtualKey(baseLabel: "5", shiftedLabel: "%", keyCode: 23),
                VirtualKey(baseLabel: "6", shiftedLabel: "^", keyCode: 22),
                VirtualKey(baseLabel: "7", shiftedLabel: "&", keyCode: 26),
                VirtualKey(baseLabel: "8", shiftedLabel: "*", keyCode: 28),
                VirtualKey(baseLabel: "9", shiftedLabel: "(", keyCode: 25),
                VirtualKey(baseLabel: "0", shiftedLabel: ")", keyCode: 29),
                VirtualKey(baseLabel: "-", shiftedLabel: "_", keyCode: 27),
                VirtualKey(baseLabel: "=", shiftedLabel: "+", keyCode: 24),
                VirtualKey(baseLabel: "Delete", keyCode: 51, widthUnits: 2),
            ],
            [
                VirtualKey(baseLabel: "q", shiftedLabel: "Q", keyCode: 12),
                VirtualKey(baseLabel: "w", shiftedLabel: "W", keyCode: 13),
                VirtualKey(baseLabel: "e", shiftedLabel: "E", keyCode: 14),
                VirtualKey(baseLabel: "r", shiftedLabel: "R", keyCode: 15),
                VirtualKey(baseLabel: "t", shiftedLabel: "T", keyCode: 17),
                VirtualKey(baseLabel: "y", shiftedLabel: "Y", keyCode: 16),
                VirtualKey(baseLabel: "u", shiftedLabel: "U", keyCode: 32),
                VirtualKey(baseLabel: "i", shiftedLabel: "I", keyCode: 34),
                VirtualKey(baseLabel: "o", shiftedLabel: "O", keyCode: 31),
                VirtualKey(baseLabel: "p", shiftedLabel: "P", keyCode: 35),
                VirtualKey(baseLabel: "[", shiftedLabel: "{", keyCode: 33),
                VirtualKey(baseLabel: "]", shiftedLabel: "}", keyCode: 30),
                VirtualKey(baseLabel: "\\", shiftedLabel: "|", keyCode: 42),
                VirtualKey(baseLabel: "Tab", keyCode: 48,
                           usesRemainingSpace: true),
            ],
            [
                VirtualKey(baseLabel: "a", shiftedLabel: "A", keyCode: 0),
                VirtualKey(baseLabel: "s", shiftedLabel: "S", keyCode: 1),
                VirtualKey(baseLabel: "d", shiftedLabel: "D", keyCode: 2),
                VirtualKey(baseLabel: "f", shiftedLabel: "F", keyCode: 3),
                VirtualKey(baseLabel: "g", shiftedLabel: "G", keyCode: 5),
                VirtualKey(baseLabel: "h", shiftedLabel: "H", keyCode: 4),
                VirtualKey(baseLabel: "j", shiftedLabel: "J", keyCode: 38),
                VirtualKey(baseLabel: "k", shiftedLabel: "K", keyCode: 40),
                VirtualKey(baseLabel: "l", shiftedLabel: "L", keyCode: 37),
                VirtualKey(baseLabel: ";", shiftedLabel: ":", keyCode: 41),
                VirtualKey(baseLabel: "'", shiftedLabel: "\"", keyCode: 39),
                VirtualKey(
                    baseLabel: "Return",
                    keyCode: 36,
                    usesRemainingSpace: true
                ),
            ],
            [
                VirtualKey(baseLabel: "z", shiftedLabel: "Z", keyCode: 6),
                VirtualKey(baseLabel: "x", shiftedLabel: "X", keyCode: 7),
                VirtualKey(baseLabel: "c", shiftedLabel: "C", keyCode: 8),
                VirtualKey(baseLabel: "v", shiftedLabel: "V", keyCode: 9),
                VirtualKey(baseLabel: "b", shiftedLabel: "B", keyCode: 11),
                VirtualKey(baseLabel: "n", shiftedLabel: "N", keyCode: 45),
                VirtualKey(baseLabel: "m", shiftedLabel: "M", keyCode: 46),
                VirtualKey(baseLabel: ",", shiftedLabel: "<", keyCode: 43),
                VirtualKey(baseLabel: ".", shiftedLabel: ">", keyCode: 47),
                VirtualKey(baseLabel: "/", shiftedLabel: "?", keyCode: 44),
                VirtualKey(
                    baseLabel: "Caps Lock",
                    keyCode: 57,
                    widthUnits: 2.5,
                    role: .toggleModifier(.capsLock),
                ),
                VirtualKey(
                    baseLabel: "Shift",
                    keyCode: 60,
                    role: .toggleModifier(.shift),
                    usesRemainingSpace: true
                ),
            ],
            [
                VirtualKey(
                    baseLabel: "Control",
                    keyCode: 59,
                    role: .toggleModifier(.control)
                ),
                VirtualKey(
                    baseLabel: "Option",
                    keyCode: 58,
                    role: .toggleModifier(.option)
                ),
                VirtualKey(
                    baseLabel: "Command",
                    keyCode: 55,
                    widthUnits: 1.2,
                    role: .toggleModifier(.command)
                ),
                VirtualKey(
                    baseLabel: "Space",
                    keyCode: 49,
                    usesRemainingSpace: true
                ),
            ],
        ]
    )
}
