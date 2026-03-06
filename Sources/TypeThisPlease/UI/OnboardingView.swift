import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to TypeThisPlease")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Grant the required permissions and then configure the local Whisper runtime before your first transcription session.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                permissionCard(
                    title: "Microphone",
                    subtitle: "Required for every recording session.",
                    state: appModel.permissionsService.microphoneState,
                    actionTitle: "Grant Microphone Access",
                    action: appModel.requestMicrophonePermission
                )

                permissionCard(
                    title: "Accessibility",
                    subtitle: "Optional. Only needed for auto-paste into the frontmost app.",
                    state: appModel.permissionsService.accessibilityState,
                    actionTitle: "Open Accessibility Prompt",
                    action: appModel.requestAccessibilityPermission
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button("Run Microphone Test") {
                        appModel.runMicrophoneSelfTest()
                    }
                    .disabled(appModel.microphoneTestState == .running)

                    Button("Open Settings") {
                        appModel.completeOnboarding(openSettings: true)
                    }
                }

                MicrophoneLevelMeterView(
                    level: appModel.microphoneTestState == .running ? appModel.microphoneTestLevel : appModel.microphoneTestPeakLevel,
                    isActive: appModel.microphoneTestState == .running
                )

                microphoneTestStatus
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Label("Runtime installed: \(appModel.installationStatus.runtimeExists ? "Yes" : "No")", systemImage: "terminal")
                Label("Model installed: \(appModel.installationStatus.modelExists ? "Yes" : "No")", systemImage: "cpu")
                Text("Start Recording stays disabled until both the Whisper runtime and a model are available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack {
                Button("Later") {
                    appModel.completeOnboarding(openSettings: false)
                }
                Spacer()
                Button("Open Settings") {
                    appModel.completeOnboarding(openSettings: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func permissionCard(
        title: String,
        subtitle: String,
        state: PermissionsService.PermissionState,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                Text(stateLabel(for: state))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(color(for: state))
            }
            Spacer()
            Button(actionTitle, action: action)
                .disabled(state == .granted)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stateLabel(for state: PermissionsService.PermissionState) -> String {
        switch state {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested yet"
        }
    }

    private func color(for state: PermissionsService.PermissionState) -> Color {
        switch state {
        case .granted:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .secondary
        }
    }

    @ViewBuilder
    private var microphoneTestStatus: some View {
        switch appModel.microphoneTestState {
        case .idle:
            Text("Use the microphone test to verify that the app can really open the selected input device.")
                .foregroundStyle(.secondary)
        case .running:
            Label("Testing microphone access…", systemImage: "waveform")
                .foregroundStyle(.secondary)
        case .succeeded(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}
