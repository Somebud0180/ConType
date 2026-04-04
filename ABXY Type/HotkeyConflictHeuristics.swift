import Carbon.HIToolbox

enum HotkeyAvailability {
    case likelyAvailable
    case unavailable
    case possiblyTaken

    var description: String {
        switch self {
        case .likelyAvailable:
            return "Likely Available"
        case .unavailable:
            return "Unavailable"
        case .possiblyTaken:
            return "Possibly Taken"
        }
    }
}

struct HotkeyConflictHeuristics {
    // Best-effort check: attempts temporary registration to spot known conflicts.
    func checkCommandK() -> HotkeyAvailability {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x41425859), id: UInt32(1))

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
            return .likelyAvailable
        }

        if status == eventHotKeyExistsErr {
            return .unavailable
        }

        return .possiblyTaken
    }
}