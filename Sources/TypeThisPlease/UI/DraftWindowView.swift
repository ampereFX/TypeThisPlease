import SwiftUI

struct DraftWindowView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 18) {
                header
                waveform
                editor
                hotkeys
            }
            .padding(22)

            if let notice = appModel.transientNotice {
                noticeCapsule(notice)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(minWidth: 460, minHeight: 280)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: appModel.transientNotice)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(appModel.isRecordingActive ? Color.red : Color.white.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(appModel.isRecordingActive ? "Recording" : appModel.isReviewing ? "Review" : "Ready")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                }

                Text(appModel.panelSubtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(appModel.elapsedText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(appModel.isRecordingActive ? .primary : .secondary)
        }
    }

    private var waveform: some View {
        WaveformView(samples: appModel.waveformSamples, isActive: appModel.isRecordingActive)
            .frame(height: 92)
    }

    private var editor: some View {
        SessionEditorView(
            segments: appModel.session?.segments ?? [],
            onReplace: { range, replacement, renderedSegments in
                appModel.applyEditorChange(range: range, replacement: replacement, renderedSegments: renderedSegments)
            },
            onFocusChanged: appModel.setEditorFocus
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var hotkeys: some View {
        HStack(spacing: 10) {
            HotKeyChip(
                title: "Start / Stop",
                shortcut: appModel.recordingHotKeyDisplayString,
                isEnabled: true,
                action: appModel.toggleRecording
            )
            HotKeyChip(
                title: "Checkpoint",
                shortcut: appModel.checkpointHotKeyDisplayString,
                isEnabled: appModel.canTriggerCheckpoint,
                action: appModel.createCheckpoint
            )
        }
    }

    private func noticeCapsule(_ notice: AppModel.Notice) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(notice.isError ? Color.orange : Color.accentColor)
                .frame(width: 8, height: 8)
            Text(notice.message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct HotKeyChip: View {
    let title: String
    let shortcut: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(shortcut)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(isEnabled ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.09 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
