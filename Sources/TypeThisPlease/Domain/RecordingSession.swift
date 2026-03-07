import Foundation

enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case review
    case finalizing
    case completed
    case failed(String)
}

enum EditorSegmentKind: Equatable, Sendable {
    case transcript(segmentIndex: Int)
    case manual
    case transcribing(segmentIndex: Int)
    case recording
}

struct EditorSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: EditorSegmentKind
    var text: String

    init(id: UUID = UUID(), kind: EditorSegmentKind, text: String = "") {
        self.id = id
        self.kind = kind
        self.text = text
    }

    var isEditable: Bool {
        switch kind {
        case .transcript, .manual:
            return true
        case .transcribing, .recording:
            return false
        }
    }

    var isResolvedText: Bool {
        switch kind {
        case .transcript, .manual:
            return true
        case .transcribing, .recording:
            return false
        }
    }
}

struct RenderedEditorSegment: Equatable, Sendable {
    let id: UUID
    let kind: EditorSegmentKind
    let range: NSRange
    let text: String

    var isEditable: Bool {
        switch kind {
        case .transcript, .manual:
            return true
        case .transcribing, .recording:
            return false
        }
    }
}

struct RecordingSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var state: RecordingState
    var activeDevice: AudioInputDevice?
    var segments: [EditorSegment]
    var activeSegmentIndex: Int
    var finalText: String?
    var deliveryMessage: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        state: RecordingState = .preparing,
        activeDevice: AudioInputDevice? = nil,
        segments: [EditorSegment] = [],
        activeSegmentIndex: Int = 0,
        finalText: String? = nil,
        deliveryMessage: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.state = state
        self.activeDevice = activeDevice
        self.segments = segments
        self.activeSegmentIndex = activeSegmentIndex
        self.finalText = finalText
        self.deliveryMessage = deliveryMessage
    }

    static func begin(activeDevice: AudioInputDevice?) -> RecordingSession {
        RecordingSession(
            state: .preparing,
            activeDevice: activeDevice,
            segments: [EditorSegment(kind: .recording, text: Self.recordingMarkerText)]
        )
    }

    var pendingTranscriptCount: Int {
        segments.reduce(into: 0) { count, segment in
            if case .transcribing = segment.kind {
                count += 1
            }
        }
    }

    var assembledDraft: String {
        segments.reduce(into: "") { partial, segment in
            guard segment.isResolvedText else { return }
            partial.append(segment.text)
        }
    }

    var isTerminal: Bool {
        switch state {
        case .completed, .failed:
            return true
        case .idle, .preparing, .recording, .review, .finalizing:
            return false
        }
    }

    var isAwaitingReviewConfirmation: Bool {
        state == .review
    }

    var canCheckpoint: Bool {
        state == .recording
    }

    var hasPendingTranscription: Bool {
        pendingTranscriptCount > 0
    }

    mutating func insertCheckpointPlaceholder(for segmentIndex: Int) {
        replaceTrailingRecordingMarker(
            with: EditorSegment(kind: .transcribing(segmentIndex: segmentIndex), text: Self.transcribingMarkerText)
        )
        segments.append(EditorSegment(kind: .recording, text: Self.recordingMarkerText))
        activeSegmentIndex = segmentIndex + 1
    }

    mutating func insertFinalPlaceholder(for segmentIndex: Int) {
        replaceTrailingRecordingMarker(
            with: EditorSegment(kind: .transcribing(segmentIndex: segmentIndex), text: Self.transcribingMarkerText)
        )
    }

    mutating func enterReviewMode() {
        state = .review
        replaceRecordingMarkerWithSilentState()
    }

    mutating func markTranscriptReady(_ text: String, for segmentIndex: Int) {
        guard let index = segmentIndexIndex(for: segmentIndex) else { return }
        segments[index].text = Self.normalizedTranscript(text, previousText: precedingResolvedText(before: index))
        segments[index].kind = .transcript(segmentIndex: segmentIndex)
    }

    mutating func markTranscriptFailed(for segmentIndex: Int) {
        guard let index = segmentIndexIndex(for: segmentIndex) else { return }
        segments.remove(at: index)
    }

    mutating func applyEditorChange(range: NSRange, replacement: String, renderedSegments: [RenderedEditorSegment]) {
        let editablePrefixLength = renderedSegments
            .first(where: { !$0.isEditable })?
            .range.location ?? renderedSegments.last.map { NSMaxRange($0.range) } ?? 0

        let clampedLocation = min(range.location, editablePrefixLength)
        let clampedEnd = min(NSMaxRange(range), editablePrefixLength)
        let clampedRange = NSRange(location: clampedLocation, length: max(0, clampedEnd - clampedLocation))

        if clampedRange.length == 0 {
            insertText(replacement, at: clampedRange.location, renderedSegments: renderedSegments)
        } else {
            replaceText(in: clampedRange, with: replacement, renderedSegments: renderedSegments)
        }

        coalesceManualSegments()
    }

    private mutating func insertText(_ text: String, at location: Int, renderedSegments: [RenderedEditorSegment]) {
        guard !text.isEmpty else { return }
        let editableSegments = renderedSegments.filter(\.isEditable)
        guard !editableSegments.isEmpty else {
            segments.insert(EditorSegment(kind: .manual, text: text), at: 0)
            return
        }

        for rendered in editableSegments {
            let lower = rendered.range.location
            let upper = NSMaxRange(rendered.range)
            if location > lower && location < upper {
                updateSegment(rendered.id) { segment in
                    let offset = location - lower
                    let index = segment.text.index(segment.text.startIndex, offsetBy: offset)
                    segment.text.insert(contentsOf: text, at: index)
                }
                return
            }
        }

        if let previous = editableSegments.last(where: { NSMaxRange($0.range) == location }),
           case .manual = previous.kind {
            updateSegment(previous.id) { $0.text.append(text) }
            return
        }

        if let next = editableSegments.first(where: { $0.range.location == location }),
           case .manual = next.kind {
            updateSegment(next.id) { $0.text = text + $0.text }
            return
        }

        let insertionIndex = insertionIndexForEditableBoundary(at: location, renderedSegments: editableSegments)
        segments.insert(EditorSegment(kind: .manual, text: text), at: insertionIndex)
    }

    private mutating func replaceText(in range: NSRange, with replacement: String, renderedSegments: [RenderedEditorSegment]) {
        let affected = renderedSegments.filter { $0.isEditable && NSIntersectionRange($0.range, range).length > 0 }
        guard let first = affected.first, let last = affected.last else { return }

        let firstPrefixLength = max(0, range.location - first.range.location)
        let lastSuffixLength = max(0, NSMaxRange(last.range) - NSMaxRange(range))

        let firstPrefix = Self.prefix(of: first.text, length: firstPrefixLength)
        let lastSuffix = Self.suffix(of: last.text, length: lastSuffixLength)
        let mergedText = firstPrefix + replacement + lastSuffix

        guard let firstSegmentIndex = segments.firstIndex(where: { $0.id == first.id }),
              let lastSegmentIndex = segments.firstIndex(where: { $0.id == last.id }) else {
            return
        }

        if affected.count == 1 {
            if mergedText.isEmpty {
                segments.remove(at: firstSegmentIndex)
            } else {
                segments[firstSegmentIndex].text = mergedText
            }
            return
        }

        segments.removeSubrange(firstSegmentIndex...lastSegmentIndex)
        if !mergedText.isEmpty {
            segments.insert(EditorSegment(kind: .manual, text: mergedText), at: firstSegmentIndex)
        }
    }

    private mutating func coalesceManualSegments() {
        var normalized: [EditorSegment] = []
        for segment in segments {
            guard !segment.text.isEmpty || !segment.isEditable else { continue }
            if case .manual = segment.kind,
               let last = normalized.last,
               case .manual = last.kind {
                normalized[normalized.count - 1].text += segment.text
            } else {
                normalized.append(segment)
            }
        }
        segments = normalized
    }

    private func insertionIndexForEditableBoundary(at location: Int, renderedSegments: [RenderedEditorSegment]) -> Int {
        for rendered in renderedSegments {
            if location <= rendered.range.location,
               let index = segments.firstIndex(where: { $0.id == rendered.id }) {
                return index
            }
        }

        if let firstMarkerIndex = segments.firstIndex(where: { !$0.isEditable }) {
            return firstMarkerIndex
        }
        return segments.count
    }

    private mutating func updateSegment(_ id: UUID, mutation: (inout EditorSegment) -> Void) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        mutation(&segments[index])
    }

    private mutating func replaceTrailingRecordingMarker(with replacement: EditorSegment) {
        if let index = segments.lastIndex(where: {
            if case .recording = $0.kind {
                return true
            }
            return false
        }) {
            segments[index] = replacement
        } else {
            segments.append(replacement)
        }
    }

    private mutating func replaceRecordingMarkerWithSilentState() {
        if let index = segments.lastIndex(where: {
            if case .recording = $0.kind {
                return true
            }
            return false
        }) {
            segments[index].text = Self.recordingMarkerText
        }
    }

    private func segmentIndexIndex(for segmentIndex: Int) -> Int? {
        segments.firstIndex { segment in
            switch segment.kind {
            case .transcript(let index), .transcribing(let index):
                return index == segmentIndex
            case .manual, .recording:
                return false
            }
        }
    }

    private func precedingResolvedText(before index: Int) -> String {
        segments[0..<index].reduce(into: "") { partial, segment in
            guard segment.isResolvedText else { return }
            partial.append(segment.text)
        }
    }

    private static func normalizedTranscript(_ raw: String, previousText: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let last = previousText.unicodeScalars.last else { return trimmed }
        let firstScalar = trimmed.unicodeScalars.first ?? " ".unicodeScalars.first!
        guard !CharacterSet.whitespacesAndNewlines.contains(last),
              !leadingPunctuation.contains(firstScalar) else {
            return trimmed
        }
        return " \(trimmed)"
    }

    private static func prefix(of text: String, length: Int) -> String {
        guard length > 0 else { return "" }
        let index = text.index(text.startIndex, offsetBy: min(length, text.count))
        return String(text[..<index])
    }

    private static func suffix(of text: String, length: Int) -> String {
        guard length > 0 else { return "" }
        let index = text.index(text.endIndex, offsetBy: -min(length, text.count))
        return String(text[index...])
    }

    private static let recordingMarkerText = " Listening… "
    private static let transcribingMarkerText = " Transcribing… "
    private static let leadingPunctuation = CharacterSet(charactersIn: ".,:;!?)]}")
}
