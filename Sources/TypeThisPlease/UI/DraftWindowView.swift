import SwiftUI

struct DraftWindowView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let session = appModel.session {
                        if session.blocks.isEmpty {
                            placeholder
                        } else {
                            ForEach(session.blocks) { block in
                                switch block.kind {
                                case .transcript(let segmentIndex):
                                    TranscriptBlockView(segmentIndex: segmentIndex, block: block)
                                case .manual:
                                    ManualBlockView(block: block) { text in
                                        appModel.updateManualBlock(id: block.id, text: text)
                                    }
                                }
                            }
                        }

                        if let finalText = session.finalText, !finalText.isEmpty {
                            Divider().padding(.vertical, 4)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Final Output")
                                    .font(.headline)
                                Text(finalText)
                                    .textSelection(.enabled)
                                    .font(.body)
                            }
                        }
                    } else if !appModel.lastTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Last Transcript")
                                .font(.headline)
                            Text(appModel.lastTranscript)
                                .textSelection(.enabled)
                        }
                    } else {
                        placeholder
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 520, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draft")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(stateSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(appModel.isRecordingActive ? "Stop" : "Start") {
                    appModel.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                Button("Checkpoint") {
                    appModel.createCheckpoint()
                }
                .disabled(!appModel.isRecordingActive)
            }
            Text(appModel.statusMessage.isEmpty ? "Session messages appear here." : appModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checkpoint-driven drafting")
                .font(.headline)
            Text("Start a recording, trigger a checkpoint when you want the spoken part committed, then type the hard-to-transcribe terms into the manual block that appears.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var stateSubtitle: String {
        guard let session = appModel.session else { return "Ready for the next session" }
        switch session.state {
        case .preparing:
            return "Preparing recording on \(session.activeDevice?.name ?? "default microphone")"
        case .recording:
            return "Recording on \(session.activeDevice?.name ?? "default microphone")"
        case .finalizing:
            return "Waiting for pending transcriptions"
        case .completed:
            return session.deliveryMessage ?? "Session completed"
        case .failed(let message):
            return message
        case .idle:
            return "Idle"
        }
    }
}

private struct TranscriptBlockView: View {
    let segmentIndex: Int
    let block: DraftBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Speech Segment \(segmentIndex + 1)", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                statusTag
            }

            Group {
                switch block.status {
                case .ready:
                    Text(block.text.isEmpty ? "Empty transcript." : block.text)
                case .pending, .transcribing:
                    Text("Transcribing…")
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var statusTag: some View {
        switch block.status {
        case .ready:
            Text("Ready")
                .foregroundStyle(.green)
        case .pending, .transcribing:
            Text("Pending")
                .foregroundStyle(.secondary)
        case .failed:
            Text("Failed")
                .foregroundStyle(.red)
        }
    }
}

private struct ManualBlockView: View {
    let block: DraftBlock
    let onTextChange: (String) -> Void

    @State private var text: String

    init(block: DraftBlock, onTextChange: @escaping (String) -> Void) {
        self.block = block
        self.onTextChange = onTextChange
        _text = State(initialValue: block.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Manual Additions", systemImage: "keyboard")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: text) { _, newValue in
                    onTextChange(newValue)
                }
                .onChange(of: block.text) { _, newValue in
                    if newValue != text {
                        text = newValue
                    }
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
