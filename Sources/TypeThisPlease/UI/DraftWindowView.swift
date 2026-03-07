import SwiftUI

struct DraftWindowView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor).opacity(0.9),
                            Color(nsColor: .underPageBackgroundColor).opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 18) {
                editor
                
                VStack(spacing: 12) {
                    waveform
                    hotkeys
                }
            }
            .padding(22)

            if let notice = appModel.transientNotice {
                noticeCapsule(notice)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if appModel.showCancelConfirmation {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        appModel.showCancelConfirmation = false
                    }
                
                cancelConfirmationOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(minWidth: 460, minHeight: 380)
        .background(
            Group {
                if !appModel.showCancelConfirmation {
                    Button("") {
                        appModel.showCancelConfirmation = true
                    }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                }
            }
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: appModel.transientNotice)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: appModel.showCancelConfirmation)
    }

    private var cancelConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    appModel.showCancelConfirmation = false
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Cancel Recording?")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("All unsaved progress will be lost.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("Keep Recording") {
                        appModel.showCancelConfirmation = false
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Discard") {
                        appModel.cancelSession()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var waveform: some View {
        WaveformView(samples: appModel.waveformSamples, isActive: appModel.isRecordingActive)
            .frame(height: 92)
    }

    private var editor: some View {
        SessionEditorView(
            segments: appModel.session?.segments ?? [],
            isInteractive: !appModel.showCancelConfirmation,
            onReplace: { range, replacement, renderedSegments in
                appModel.applyEditorChange(range: range, replacement: replacement, renderedSegments: renderedSegments)
            },
            onFocusChanged: appModel.setEditorFocus
        )
        .frame(maxWidth: .infinity)
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
        .disabled(appModel.showCancelConfirmation)
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
