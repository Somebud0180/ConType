import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var step = 0
    @Published private(set) var isAccessibilityTrusted = AccessibilityPermission.isTrusted()

    var onComplete: (() -> Void)?

    var isAwaitingActivation: Bool {
        step == 2
    }

    private var permissionPollTimer: Timer?

    func prepareForPresentation(startAtWelcome: Bool) {
        if startAtWelcome {
            step = 0
        } else {
            step = AccessibilityPermission.isTrusted() ? 2 : 1
        }

        refreshAccessibilityStatus(advanceFromPermissionStep: true)
        startPermissionPollingIfNeeded()
    }

    func stop() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    func advanceFromWelcome() {
        step = 1
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

        _ = AccessibilityPermission.requestPrompt()
        refreshAccessibilityStatus(advanceFromPermissionStep: true)
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
        let trusted = AccessibilityPermission.isTrusted()
        let wasTrusted = isAccessibilityTrusted
        
        print(trusted)
        
        if wasTrusted != trusted {
            isAccessibilityTrusted = trusted
        }

        if advanceFromPermissionStep, !wasTrusted, trusted, step == 2 {
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
            default:
                readyStep
            }

            Spacer(minLength: 20)

            actionRow
        }
        .padding(24)
        .frame(width: 360, height: 480)
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
                Text("After enabling in System Settings, this screen advances automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            case 0:
                Button("Next") {
                    viewModel.advanceFromWelcome()
                }
                .keyboardShortcut(.defaultAction)
            case 1:
                Button(viewModel.isAccessibilityTrusted ? "Next ->" : "Enable Permission") {
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
    OnboardingView(settings: AppSettings(), viewModel: OnboardingViewModel())
}
