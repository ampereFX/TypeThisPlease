import Foundation

enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case finalizing
    case completed
    case failed(String)
}

enum DraftBlockStatus: Equatable, Sendable {
    case pending
    case transcribing
    case ready
    case failed(String)
}

enum DraftBlockKind: Equatable, Sendable {
    case transcript(segmentIndex: Int)
    case manual(boundaryIndex: Int)
}

struct DraftBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: DraftBlockKind
    var text: String
    var status: DraftBlockStatus

    init(id: UUID = UUID(), kind: DraftBlockKind, text: String = "", status: DraftBlockStatus = .ready) {
        self.id = id
        self.kind = kind
        self.text = text
        self.status = status
    }
}

struct RecordingSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var state: RecordingState
    var activeDevice: AudioInputDevice?
    var blocks: [DraftBlock]
    var activeSegmentIndex: Int
    var finalText: String?
    var deliveryMessage: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        state: RecordingState = .preparing,
        activeDevice: AudioInputDevice? = nil,
        blocks: [DraftBlock] = [],
        activeSegmentIndex: Int = 0,
        finalText: String? = nil,
        deliveryMessage: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.state = state
        self.activeDevice = activeDevice
        self.blocks = blocks
        self.activeSegmentIndex = activeSegmentIndex
        self.finalText = finalText
        self.deliveryMessage = deliveryMessage
    }

    static func begin(activeDevice: AudioInputDevice?) -> RecordingSession {
        RecordingSession(state: .preparing, activeDevice: activeDevice)
    }

    var pendingTranscriptCount: Int {
        blocks.reduce(into: 0) { count, block in
            if case .transcript = block.kind {
                switch block.status {
                case .pending, .transcribing:
                    count += 1
                case .ready, .failed:
                    break
                }
            }
        }
    }

    var assembledDraft: String {
        blocks.reduce(into: "") { partial, block in
            partial.append(block.text)
        }
    }

    var isTerminal: Bool {
        switch state {
        case .completed, .failed:
            return true
        case .idle, .preparing, .recording, .finalizing:
            return false
        }
    }

    mutating func insertCheckpointPlaceholder(for segmentIndex: Int) {
        guard !containsTranscriptBlock(for: segmentIndex) else { return }

        blocks.append(DraftBlock(kind: .transcript(segmentIndex: segmentIndex), status: .transcribing))
        blocks.append(DraftBlock(kind: .manual(boundaryIndex: segmentIndex), status: .ready))
        activeSegmentIndex = segmentIndex + 1
    }

    mutating func insertFinalPlaceholder(for segmentIndex: Int) {
        guard !containsTranscriptBlock(for: segmentIndex) else { return }

        blocks.append(DraftBlock(kind: .transcript(segmentIndex: segmentIndex), status: .transcribing))
    }

    mutating func updateManualBlock(_ blockID: UUID, text: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        guard case .manual = blocks[index].kind else { return }
        blocks[index].text = text
    }

    mutating func markTranscriptReady(_ text: String, for segmentIndex: Int) {
        guard let index = transcriptBlockIndex(for: segmentIndex) else { return }
        blocks[index].text = Self.normalizedTranscript(text, previousText: precedingText(before: index))
        blocks[index].status = .ready
    }

    mutating func markTranscriptFailed(_ message: String, for segmentIndex: Int) {
        guard let index = transcriptBlockIndex(for: segmentIndex) else { return }
        blocks[index].status = .failed(message)
        blocks[index].text = ""
    }

    private func containsTranscriptBlock(for segmentIndex: Int) -> Bool {
        transcriptBlockIndex(for: segmentIndex) != nil
    }

    private func transcriptBlockIndex(for segmentIndex: Int) -> Int? {
        blocks.firstIndex { block in
            if case .transcript(let index) = block.kind {
                return index == segmentIndex
            }
            return false
        }
    }

    private func precedingText(before index: Int) -> String {
        guard index > 0 else { return "" }
        return blocks[0..<index].map(\.text).joined()
    }

    private static func normalizedTranscript(_ raw: String, previousText: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let last = previousText.unicodeScalars.last else { return trimmed }
        let firstScalar = trimmed.unicodeScalars.first ?? " ".unicodeScalars.first!
        guard !CharacterSet.whitespacesAndNewlines.contains(last),
              !Self.leadingPunctuation.contains(firstScalar) else {
            return trimmed
        }
        return " \(trimmed)"
    }

    private static let leadingPunctuation = CharacterSet(charactersIn: ".,:;!?)]}")
}
