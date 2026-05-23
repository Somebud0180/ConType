//
//  AccessibilityPermission.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/8/26.
//
//  Code referenced from Hold To Talk
//  https://github.com/jxucoder/hold-to-talk/tree/main

import CoreGraphics

/// Enum for managing Input Monitoring (TCC) permissions on macOS.
/// Uses CoreGraphics APIs to check and request permission.
public enum InputMonitoringPermission {
    /// Checks if the app is authorized for Input Monitoring.
    /// - Returns: Boolean, true if authorized, false otherwise.
    @MainActor
    public static func isAuthorized() -> Bool {
        CGPreflightPostEventAccess() || CGPreflightListenEventAccess()
    }

    /// Requests Input Monitoring permission from the user.
    /// Doesn't guarantee to return true immediately after permission is granted. May require app restart.
    /// - Returns: `true` if access is granted, `false` otherwise.
    @MainActor
    public static func requestAuthorization() -> Bool {
        CGRequestPostEventAccess()
    }
}
