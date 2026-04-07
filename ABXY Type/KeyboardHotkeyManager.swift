import AppKit
import ApplicationServices

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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        stop()

        // Prefer a CGEvent tap so we can swallow the shortcut before it reaches the front app.
        if installEventTap() {
            return
        }

        // Fallback: NSEvent monitors (can't swallow events; front app will also receive the keys).
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

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
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

    private func installEventTap() -> Bool {
        // Requires Accessibility to modify/swallow events; otherwise tap creation fails.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: KeyboardHotkeyManager.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, cgEvent, refcon in
        // Pass through non-key events
        guard type == .keyDown else {
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let refcon = refcon else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let manager = Unmanaged<KeyboardHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

        // Convert to NSEvent to reuse existing shortcut matching logic
        guard let nsEvent = NSEvent(cgEvent: cgEvent) else {
            return Unmanaged.passUnretained(cgEvent)
        }

        if manager.matchesToggleShortcut(nsEvent) {
            // Toggle on the main thread and swallow the event so the front app doesn't also handle it
            DispatchQueue.main.async {
                manager.onToggle?()
            }
            return nil
        }

        return Unmanaged.passUnretained(cgEvent)
    }
}
