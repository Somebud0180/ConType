//
//  AppDelegate.swift
//  ConType
//
//  Created by GitHub Copilot on 5/25/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        checkForDuplicateInstanceIfNeeded()
    }
    
    private func checkForDuplicateInstanceIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != NSRunningApplication.current.processIdentifier }
        
        guard !otherInstances.isEmpty else { return }
        
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Another instance of ConType is already running."
        alert.informativeText = "If you want to relaunch ConType, quit the other instance first."
        alert.addButton(withTitle: "Quit")
        
        // If the user confirms, terminate the newly launched instance so they can relaunch after quitting the old one.
        if alert.runModal() == .alertFirstButtonReturn {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
