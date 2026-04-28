//
//  AccessibilityPermission.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/8/26.
//
//  Code referenced from AXorcist
//  https://github.com/steipete/AXorcist/

import ApplicationServices
import CoreGraphics

//public enum AccessibilityPermission {
//    @MainActor
//    public static func isTrusted() -> Bool {
//        AXIsProcessTrusted()
//    }
//
//    @MainActor
//    static func requestPrompt() -> Bool {
//        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
//        return AXIsProcessTrustedWithOptions(options as CFDictionary?)
//    }
//}

/// Enum for managing Input Monitoring (TCC) permissions on macOS.
/// Uses CoreGraphics APIs to check and request permission.
public enum InputMonitoringPermission {
    /// Checks if the app is authorized for Input Monitoring.
    @MainActor
    public static func isAuthorized() -> Bool {
        CGPreflightPostEventAccess() || CGPreflightListenEventAccess()
    }

    /// Requests Input Monitoring permission from the user.
    /// Returns true if access is granted, false otherwise.
    @MainActor
    public static func requestAuthorization() -> Bool {
        CGRequestPostEventAccess()
    }
}
