import SwiftUI

struct MenuBarMenuView: View {
    @EnvironmentObject private var appModel: AppModel
    let onRequestClose: (() -> Void)?

    init(onRequestClose: (() -> Void)? = nil) {
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TypeThisPlease")
                    .font(.headline)
                Text(appModel.menuHeadline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Button(appModel.primaryMenuButtonTitle) {
                    handlePrimaryTap()
                }
                .keyboardShortcut(.defaultAction)

                Button("Checkpoint") {
                    handleCheckpointTap()
                }
                .disabled(!appModel.canTriggerCheckpoint)

                Divider()

                Button("Settings") {
                    handleSettingsTap()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recording: \(appModel.recordingHotKeyDisplayString)")
                Text("Checkpoint: \(appModel.checkpointHotKeyDisplayString)")
                Text(appModel.statusMessage.isEmpty ? "No recent status." : appModel.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .font(.caption)

            Divider()

            Button("Quit TypeThisPlease") {
                handleQuitTap()
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 280)
    }

    private func handleQuitTap() {
        NSApplication.shared.terminate(nil)
    }

    private func handlePrimaryTap() {
        Task { @MainActor in
            let title = appModel.primaryMenuButtonTitle
            let hasBackend = appModel.hasTranscriptionBackendReady
            let sessionIsNil = appModel.session == nil
            DebugLog.log(
                "Menu action tapped. name='primary:\(title)' headline='\(appModel.menuHeadline)' primaryTitle='\(title)' backendReady=\(hasBackend) sessionNil=\(sessionIsNil)",
                category: "menu"
            )
            onRequestClose?()
            DebugLog.log("Executing deferred menu action 'primary:\(title)'", category: "menu")
            if sessionIsNil && !hasBackend {
                appModel.openSettingsWindow()
            } else {
                appModel.toggleRecording()
            }
        }
    }

    private func handleCheckpointTap() {
        Task { @MainActor in
            DebugLog.log("Menu action tapped. name='checkpoint' enabled=\(appModel.canTriggerCheckpoint)", category: "menu")
            onRequestClose?()
            DebugLog.log("Executing deferred menu action 'checkpoint'", category: "menu")
            appModel.createCheckpoint()
        }
    }

    private func handleSettingsTap() {
        Task { @MainActor in
            DebugLog.log("Menu action tapped. name='settings'", category: "menu")
            onRequestClose?()
            DebugLog.log("Executing deferred menu action 'settings'", category: "menu")
            appModel.openSettingsWindow()
        }
    }
}
