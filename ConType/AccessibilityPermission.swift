//
//  AccessibilityPermission.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/8/26.
//
//  Code referenced from AXorcist
//  https://github.com/steipete/AXorcist/

import ApplicationServices

public enum AccessibilityPermission {
    @MainActor
    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    static func requestPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary?)
    }
}
