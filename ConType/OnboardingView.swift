import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    let settings: AppSettings
    
    @Published private(set) var step = 0
    @Published private(set) var isAccessibilityTrusted = InputMonitoringPermission.isAuthorized()
    @Published var isAwaitingPermissionGrant: Bool = false

    var onComplete: (() -> Void)?
    var onAccessibilityTrustChanged: ((Bool) -> Void)?
    
    var isAwaitingActivation: Bool {
        step == 2
    }

    private var permissionPollTimer: Timer?
    
    init(settings: AppSettings) {
        self.settings = settings
    }

    func prepareForPresentation(startAtWelcome: Bool) {
        if startAtWelcome {
            step = 0
        } else if settings.restartedFromPermissionScreen {
            step = 1
            settings.restartedFromPermissionScreen = false
            startPermissionPollingIfNeeded()
        } else {
            step = InputMonitoringPermission.isAuthorized() ? 2 : 1
            startPermissionPollingIfNeeded()
        }

        refreshAccessibilityStatus(advanceFromPermissionStep: true)
    }

    func stop() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    func advanceStep() {
        step += 1
    }

    func goBack() {
        guard step > 0 else { return }
        step -= 1
    }

    func handlePermissionButton() {
        if isAccessibilityTrusted {
            step = 2
            return
        }
        
        if isAwaitingPermissionGrant {
            // From HoldToTalk Repository, by @jxucoder
            // Restart app
            settings.restartedFromPermissionScreen = true
            
            let url = Bundle.main.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }

        _ = InputMonitoringPermission.requestAuthorization()
        startPermissionPollingIfNeeded()
        refreshAccessibilityStatus(advanceFromPermissionStep: true)
        isAwaitingPermissionGrant = true
    }

    func handleShortcutActivation() {
        guard isAwaitingActivation else { return }
        complete()
    }

    func complete() {
        onComplete?()
    }

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

    private func refreshAccessibilityStatus(advanceFromPermissionStep: Bool) {
        let trusted = InputMonitoringPermission.isAuthorized()
        let wasTrusted = isAccessibilityTrusted
        
        if wasTrusted != trusted {
            isAccessibilityTrusted = trusted
            onAccessibilityTrustChanged?(trusted)
        }

        if advanceFromPermissionStep, !wasTrusted, trusted, step == 1 {
            step = 2
        }
    }
}

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
            default:
                readyStep
            }

            Spacer(minLength: 20)

            actionRow
        }
        .padding(24)
        .frame(width: 360, height: 400)
    }

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
    
    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)

            Text("Press")
                .font(.largeTitle.weight(.semibold))

            shortcutBadge(settings.keyboardHotkey.displayText)

            Text("or")
                .foregroundStyle(.secondary)

            shortcutBadge(settings.controllerToggleBinding.title(for: settings.controllerGlyphStyle))

            Text("to get started")
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack {
            if viewModel.step > 0 {
                backButton
            }

            Spacer()

            switch viewModel.step {
            case 0, 2:
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
        .tint(.secondary)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
