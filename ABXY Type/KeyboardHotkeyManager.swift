import AppKit

final class KeyboardHotkeyManager {
    struct Shortcut: Equatable {
        let key: String
        let modifiers: NSEvent.ModifierFlags

        var displayText: String {
            var parts: [String] = []
            if modifiers.contains(.control) { parts.append("Ctrl") }
            if modifiers.contains(.option) { parts.append("Option") }
            if modifiers.contains(.shift) { parts.append("Shift") }
            if modifiers.contains(.command) { parts.append("Command") }

            switch key {
            case " ": parts.append("Space")
            case "\r": parts.append("Return")
            default: parts.append(key.uppercased())
            }
            return parts.joined(separator: " + ")
        }
    }

    var onToggle: (() -> Void)?
    var shortcut: Shortcut?

    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.matchesToggleShortcut(event) else { return event }
            self.onToggle?()
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matchesToggleShortcut(event) else { return }
            self.onToggle?()
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        stop()
    }

    private func matchesToggleShortcut(_ event: NSEvent) -> Bool {
        guard let shortcut else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == shortcut.modifiers else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == shortcut.key
    }

    static func shortcut(from event: NSEvent) -> Shortcut? {
        guard let rawKey = event.charactersIgnoringModifiers?.lowercased(), !rawKey.isEmpty else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let mappedKey: String

        switch event.keyCode {
        case 49:
            mappedKey = " "
        case 36, 76:
            mappedKey = "\r"
        default:
            mappedKey = String(rawKey.prefix(1))
        }

        return Shortcut(key: mappedKey, modifiers: flags)
    }

    static func isValidShortcut(_ shortcut: Shortcut) -> Bool {
        // Require at least one modifier to avoid accidental triggers.
        !shortcut.modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }
}
