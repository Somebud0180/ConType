//
//  OnboardingView.swift
//  ConType
//
//  Created by Ethan John Lagera on 4/14/26.
//

import AppKit
import Combine
import Foundation
import SwiftUI

/// A class that manages the onboarding view. Handles permission check, initial presentation, flow progression, and completion.
@MainActor
final class OnboardingViewModel: ObservableObject {
    let settings: AppSettings
    private let isPermissionAuthorized: @MainActor () -> Bool
    private let requestPermissionAuthorization: @MainActor () -> Bool
    private let restartApplication: @MainActor () -> Void
    
    @Published private(set) var step = 0
    @Published private(set) var isAccessibilityTrusted = false
    @Published var isAwaitingPermissionGrant: Bool = false
    
    var onComplete: (() -> Void)?
    var openSettings: (() -> Void)?
    var onAccessibilityTrustChanged: ((Bool) -> Void)?
    
    var isAwaitingActivation: Bool {
        step >= 3
    }
    
    private var permissionPollTimer: Timer?
    
    init(
        settings: AppSettings,
        isPermissionAuthorized: @escaping @MainActor () -> Bool = InputMonitoringPermission.isAuthorized,
        requestPermissionAuthorization: @escaping @MainActor () -> Bool = InputMonitoringPermission.requestAuthorization,
        restartApplication: (@MainActor () -> Void)? = nil
    ) {
        self.settings = settings
        self.isPermissionAuthorized = isPermissionAuthorized
        self.requestPermissionAuthorization = requestPermissionAuthorization
        self.restartApplication = restartApplication ?? Self.defaultRestartApplication
        self.isAccessibilityTrusted = isPermissionAuthorized()
    }
    
    /// Sets the active step based on how the view was invoked. Usually called when the onboarding view is called.
    /// - Parameter startAtWelcome: A `Bool` indicating wether the view should explicitly start at the beginning
    func prepareForPresentation(startAtWelcome: Bool) {
        if startAtWelcome {
            step = 0
        } else if settings.restartedFromPermissionScreen {
            step = 1
            settings.restartedFromPermissionScreen = false
            startPermissionPollingIfNeeded()
        } else {
            step = isPermissionAuthorized() ? 2 : 1
            startPermissionPollingIfNeeded()
        }
        
        refreshAccessibilityStatus(advanceFromPermissionStep: true)
    }
    
    /// Stops the permission polling
    func stop() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
    
    /// Increases the value of `step` by 1
    func advanceStep() {
        step += 1
    }
    
    /// Decreases the value of `step` by 1, ensuring the step doesn't go below 0
    func goBack() {
        guard step > 0 else { return }
        step -= 1
    }
    
    /// Handles the view's permission button functionality.
    /// If trusted, advance a step. If the app already requested the permission, restart the app. Else perform permission request.
    func handlePermissionButton() {
        if isAccessibilityTrusted {
            step = 2
            return
        }
        
        if isAwaitingPermissionGrant {
            // From HoldToTalk Repository, by @jxucoder
            // Restart app
            settings.restartedFromPermissionScreen = true
            restartApplication()
            return
        }
        
        _ = requestPermissionAuthorization()
        startPermissionPollingIfNeeded()
        refreshAccessibilityStatus(advanceFromPermissionStep: true)
        isAwaitingPermissionGrant = true
    }
    
    /// Handles performing completion when awaiting for the overlay to be called.
    func handleShortcutActivation() {
        guard isAwaitingActivation else { return }
        complete()
    }
    
    /// Performs callback for handling completion.
    func complete() {
        onComplete?()
    }
    
    /// Begins the background checking of wether the permission has been granted.
    /// Calls `refreshAccessibilityStatus()` every 0.8 seconds.
    private func startPermissionPollingIfNeeded() {
        guard permissionPollTimer == nil else { return }
        
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.refreshAccessibilityStatus(advanceFromPermissionStep: true)
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }
    
    /// Checks if the user has granted the app the required permission.
    /// - Parameter advanceFromPermissionStep: A `Bool` indicating wether the function should advance the view after the permission                                                                                         is given.
    private func refreshAccessibilityStatus(advanceFromPermissionStep: Bool) {
        let trusted = isPermissionAuthorized()
        let wasTrusted = isAccessibilityTrusted
        
        if wasTrusted != trusted {
            isAccessibilityTrusted = trusted
            onAccessibilityTrustChanged?(trusted)
        }
        
        if advanceFromPermissionStep, !wasTrusted, trusted, step == 1 {
            step = 2
        }
    }
    
    @MainActor
    private static func defaultRestartApplication() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

/// A view struct containing the onboarding flow. Handled by a switch-case for each step with a static action row containing the buttons.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.step {
            case 0:
                welcomeStep
            case 1:
                permissionStep
            case 2:
                configStep
            case 3:
                infoStep
            default:
                readyStep
            }
            
            Spacer(minLength: 20)
            
            actionRow
        }
        .padding(24)
        .frame(width: 360, height: 400)
        .animation(.easeInOut(duration: 0.5), value: viewModel.step)
    }
    
    /// Contains the app icon and name and introduction.
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            
            Image("AppIcon")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 172, height: 172)
            
            Text("Welcome to ConType")
                .font(.largeTitle.weight(.semibold))
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
    
    /// Contains permission request text and descriptions.
    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            
            Text("Enable Accessibility Permissions")
                .font(.largeTitle.weight(.semibold))
            
            Text("This permission is needed to simulate key presses")
                .foregroundStyle(.secondary)
            
            if viewModel.isAccessibilityTrusted {
                Label("Accessibility permission detected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 6)
            } else {
                Text("If you already enabled the permission and can't advance to the next step, try restarting the app below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// Contains a toggle for wether the app should open on system startup.
    private var configStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            
            Text("Almost there!")
                .font(.largeTitle.weight(.semibold))
            
            Toggle(isOn: $settings.openAppOnStartup) {
                Text("Open app at startup")
                Text("Should ConType open automatically when you log in? You can change this later in settings.")
            }
            .toggleStyle(.switch)
            
            Spacer(minLength: 0)
        }
    }
    
    /// Contains an image showing the app in the menu bar and a description.
    private var infoStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            
            Text("You should know...")
                .font(.largeTitle.weight(.semibold))
            
            Image("MenubarHint")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text("You can find the app living in your menu bar at the top of your screen. Just click on the icon you see above to open the menu.")
            
            Spacer(minLength: 0)
        }
    }
    
    /// Contains the instructions/shortcut for toggling the keyboard and mouse overlay.
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            
            Text("Press any of the following")
                .font(.largeTitle.weight(.semibold))
            
            shortcutBadge(settings.keyboardHotkey.displayText,
                          to: "Toggle Overlay")
            
            shortcutBadge(
                settings.controllerToggleBindings.shortcutText(
                    for: .keyboardToggle,
                    style: settings.controllerGlyphStyle
                ),
                to: "Toggle Keyboard Overlay"
            )
            
            shortcutBadge(
                settings.controllerToggleBindings.shortcutText(
                    for: .mouseToggle,
                    style: settings.controllerGlyphStyle
                ),
                to: "Toggle Mouse Overlay"
            )
            
            Text("to get started")
                .foregroundStyle(.secondary)
            
            Text("You can also check out the settings to see more of what you can do with the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// A view containing the buttons suitable for the active step.
    private var actionRow: some View {
        HStack {
            if viewModel.step > 0 {
                backButton
            }
            
#if DEBUG
            if viewModel.step < 4 {
                Button("Skip") {
                    viewModel.advanceStep()
                }
            }
#endif
            
            Spacer()
            
            switch viewModel.step {
            case 0, 2, 3:
                Button("Next") {
                    viewModel.advanceStep()
                }
                .keyboardShortcut(.defaultAction)
            case 1:
                let text = viewModel.isAwaitingPermissionGrant ? "Quit & Reopen" : (viewModel.isAccessibilityTrusted ? "Next" : "Enable Permission")
                Button(text) {
                    viewModel.handlePermissionButton()
                }
                .keyboardShortcut(.defaultAction)
            default:
                Button("Open Settings") {
                    viewModel.openSettings?()
                }
                
                Button("Finish") {
                    viewModel.complete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var backButton: some View {
        Button("Back") {
            viewModel.goBack()
        }
        .buttonStyle(.bordered)
    }
    
    /// Creates a view that contains a shortcut guide.
    /// - Parameters:
    ///   - text: The `String` containg the shortcut to display
    ///   - action: The `String` that contains the name of the shortcut
    /// - Returns: A `View` containing a VStack with styling
    private func shortcutBadge(_ text: String, to action: String) -> some View {
        VStack (alignment: .leading, spacing: 4) {
            Text(action)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(text)
                .font(.system(.body, design: .monospaced).weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingView(settings: AppSettings(), viewModel: OnboardingViewModel(settings: AppSettings()))
}
