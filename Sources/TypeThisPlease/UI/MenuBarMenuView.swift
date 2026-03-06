import SwiftUI

struct MenuBarMenuView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TypeThisPlease")
                    .font(.headline)
                Text(appModel.isRecordingActive ? "Recording pipeline active" : "Ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Button(appModel.isRecordingActive ? "Stop Recording" : "Start Recording") {
                    appModel.toggleRecording()
                }
                .keyboardShortcut(.defaultAction)

                Button("Checkpoint") {
                    appModel.createCheckpoint()
                }
                .disabled(!appModel.isRecordingActive)

                Divider()

                Button("Show Draft") {
                    appModel.openDraftWindow()
                }

                Button("Settings") {
                    appModel.openSettingsWindow()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recording: \(appModel.settings.recordingHotKey.displayString)")
                Text("Checkpoint: \(appModel.settings.checkpointHotKey.displayString)")
                Text(appModel.statusMessage.isEmpty ? "No recent status." : appModel.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 280)
    }
}
