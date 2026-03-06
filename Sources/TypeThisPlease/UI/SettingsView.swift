import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                hotkeySection
                outputSection
                devicesSection
                modelSection
                permissionsSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Configure hotkeys, local Whisper runtime, output behavior, and input device priorities.")
                .foregroundStyle(.secondary)
        }
    }

    private var hotkeySection: some View {
        SettingsCard(title: "Hotkeys", subtitle: "Global shortcuts for recording and checkpoints.") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start / Stop")
                        .font(.headline)
                    HotKeyRecorder(
                        hotKey: appModel.settings.recordingHotKey,
                        onHotKeyChanged: { appModel.setRecordingHotKey($0) },
                        onCaptureChanged: { isCapturing in
                            if isCapturing {
                                appModel.beginHotKeyCapture()
                            } else {
                                appModel.endHotKeyCapture()
                            }
                        }
                    )
                    .frame(height: 44)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Checkpoint")
                        .font(.headline)
                    HotKeyRecorder(
                        hotKey: appModel.settings.checkpointHotKey,
                        onHotKeyChanged: { appModel.setCheckpointHotKey($0) },
                        onCaptureChanged: { isCapturing in
                            if isCapturing {
                                appModel.beginHotKeyCapture()
                            } else {
                                appModel.endHotKeyCapture()
                            }
                        }
                    )
                    .frame(height: 44)
                }
            }
        }
    }

    private var outputSection: some View {
        SettingsCard(title: "Output", subtitle: "Control how the final transcript leaves the app.") {
            Picker("Delivery", selection: Binding(
                get: { appModel.settings.outputAction },
                set: { appModel.setOutputAction($0) }
            )) {
                ForEach(OutputAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)

            if appModel.settings.outputAction == .copyAndPaste && appModel.permissionsService.accessibilityState != .granted {
                Text("Accessibility permission is required for auto-paste. The app falls back to clipboard-only if it is missing.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private var devicesSection: some View {
        SettingsCard(title: "Input Devices", subtitle: "The app chooses the first currently available device from this priority list.") {
            VStack(alignment: .leading, spacing: 14) {
                if let resolvedDevice = appModel.resolvedDevice {
                    Label("Current selection: \(resolvedDevice.name)", systemImage: "mic.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Label("No microphone currently available", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Priority List")
                        .font(.headline)

                    if appModel.settings.devicePreferences.isEmpty {
                        Text("No explicit priorities yet. The app currently falls back to the default input device.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.settings.devicePreferences) { preference in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preference.name)
                                    Text(preference.uid)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    appModel.movePreferredDeviceUp(preference.uid)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                Button {
                                    appModel.movePreferredDeviceDown(preference.uid)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                Button(role: .destructive) {
                                    appModel.removePreferredDevice(preference.uid)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Devices")
                        .font(.headline)

                    if appModel.availableDevices.isEmpty {
                        Text("No audio inputs detected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.availableDevices) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                    Text(device.uid)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if appModel.settings.devicePreferences.contains(where: { $0.uid == device.uid }) {
                                    Text("Preferred")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Add to Priority") {
                                        appModel.addPreferredDevice(device)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var modelSection: some View {
        SettingsCard(title: "Whisper Runtime", subtitle: "Configure the process-based transcription backend and its model.") {
            VStack(alignment: .leading, spacing: 14) {
                pathRow(
                    title: "Executable",
                    text: Binding(
                        get: { appModel.settings.whisperConfiguration.executablePath },
                        set: { newValue in
                            appModel.updateWhisperConfiguration { $0.executablePath = newValue }
                        }
                    ),
                    chooseAction: appModel.chooseWhisperExecutable
                )

                pathRow(
                    title: "Model",
                    text: Binding(
                        get: { appModel.settings.whisperConfiguration.modelPath },
                        set: { newValue in
                            appModel.updateWhisperConfiguration { $0.modelPath = newValue }
                        }
                    ),
                    chooseAction: appModel.chooseWhisperModel
                )

                TextField("Runtime download URL", text: Binding(
                    get: { appModel.settings.whisperConfiguration.runtimeDownloadURL },
                    set: { newValue in appModel.updateWhisperConfiguration { $0.runtimeDownloadURL = newValue } }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Model download URL", text: Binding(
                    get: { appModel.settings.whisperConfiguration.modelDownloadURL },
                    set: { newValue in appModel.updateWhisperConfiguration { $0.modelDownloadURL = newValue } }
                ))
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Download Runtime") {
                        appModel.downloadRuntime()
                    }
                    .disabled(appModel.installationStatus.runtimeDownloadInProgress)

                    Button("Download Model") {
                        appModel.downloadModel()
                    }
                    .disabled(appModel.installationStatus.modelDownloadInProgress)
                }

                TextField("Language (auto or ISO code)", text: Binding(
                    get: { appModel.settings.whisperConfiguration.language },
                    set: { newValue in appModel.updateWhisperConfiguration { $0.language = newValue } }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Prompt conditioning", text: Binding(
                    get: { appModel.settings.whisperConfiguration.prompt },
                    set: { newValue in appModel.updateWhisperConfiguration { $0.prompt = newValue } }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Extra arguments", text: Binding(
                    get: { appModel.settings.whisperConfiguration.extraArguments },
                    set: { newValue in appModel.updateWhisperConfiguration { $0.extraArguments = newValue } }
                ))
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    statusLine(label: "Runtime", ok: appModel.installationStatus.runtimeExists, path: appModel.installationStatus.runtimeURL?.path)
                    statusLine(label: "Model", ok: appModel.installationStatus.modelExists, path: appModel.installationStatus.modelURL?.path)
                    if let error = appModel.installationStatus.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .font(.callout)
            }
        }
    }

    private var permissionsSection: some View {
        SettingsCard(title: "Permissions", subtitle: "Microphone is required for capture. Accessibility enables optional auto-paste.") {
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Microphone",
                    state: appModel.permissionsService.microphoneState.rawValue,
                    actionTitle: "Request Access",
                    action: appModel.requestMicrophonePermission
                )
                permissionRow(
                    title: "Accessibility",
                    state: appModel.permissionsService.accessibilityState.rawValue,
                    actionTitle: "Open Prompt",
                    action: appModel.requestAccessibilityPermission
                )

                HStack(spacing: 12) {
                    Button("Run Microphone Test") {
                        appModel.runMicrophoneSelfTest()
                    }
                    .disabled(appModel.microphoneTestState == .running)
                    Button("Show Setup Dialog") {
                        appModel.openOnboardingWindow()
                    }
                }

                MicrophoneLevelMeterView(
                    level: appModel.microphoneTestState == .running ? appModel.microphoneTestLevel : appModel.microphoneTestPeakLevel,
                    isActive: appModel.microphoneTestState == .running
                )

                microphoneTestStatus

                Text("When you launch through `swift run`, macOS permission state can reflect the host app that launched the binary. The microphone self-test verifies real device access from inside this app flow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pathRow(title: String, text: Binding<String>, chooseAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                Button("Choose", action: chooseAction)
            }
        }
    }

    private func statusLine(label: String, ok: Bool, path: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .fontWeight(.semibold)
            Text(ok ? "Ready" : "Missing")
                .foregroundStyle(ok ? .green : .orange)
            if let path, !path.isEmpty {
                Text(path)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func permissionRow(title: String, state: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(state.capitalized)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
    }

    @ViewBuilder
    private var microphoneTestStatus: some View {
        switch appModel.microphoneTestState {
        case .idle:
            EmptyView()
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

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
