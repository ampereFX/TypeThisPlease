import SwiftUI

struct RecordingHUDView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(appModel.isRecordingActive ? Color.red : Color.secondary)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appModel.elapsedText)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            }

            HStack(spacing: 10) {
                Label(appModel.settings.recordingHotKey.displayString, systemImage: "record.circle")
                Label(appModel.settings.checkpointHotKey.displayString, systemImage: "bookmark")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .padding(14)
    }

    private var title: String {
        guard let session = appModel.session else { return "Ready" }
        switch session.state {
        case .preparing:
            return "Preparing"
        case .recording:
            return "Recording"
        case .finalizing:
            return "Finalizing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .idle:
            return "Idle"
        }
    }

    private var detailText: String {
        appModel.session?.activeDevice?.name ?? "Default microphone"
    }
}
