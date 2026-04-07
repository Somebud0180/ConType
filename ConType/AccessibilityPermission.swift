import ApplicationServices

public enum AccessibilityPermission {
    private static let promptOptionKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    @MainActor
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPrompt() -> Bool {
        let options = [promptOptionKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
