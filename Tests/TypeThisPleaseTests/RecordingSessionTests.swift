import Foundation
import Testing
@testable import TypeThisPlease

struct RecordingSessionTests {
    @Test
    func checkpointCreatesTranscribingAndRecordingMarkers() {
        var session = RecordingSession.begin(activeDevice: nil)

        session.insertCheckpointPlaceholder(for: 0)

        #expect(session.segments.count == 2)
        #expect({
            if case .transcribing(0) = session.segments[0].kind { return true }
            return false
        }())
        #expect({
            if case .recording = session.segments[1].kind { return true }
            return false
        }())
    }

    @Test
    func transcriptsAndInsertedManualTextAssembleInDeclaredOrder() {
        var session = RecordingSession.begin(activeDevice: nil)

        session.insertCheckpointPlaceholder(for: 0)
        session.markTranscriptReady("Hello world.", for: 0)
        session.applyEditorChange(
            range: NSRange(location: "Hello world.".count, length: 0),
            replacement: " CustomWord",
            renderedSegments: [
                RenderedEditorSegment(
                    id: session.segments[0].id,
                    kind: session.segments[0].kind,
                    range: NSRange(location: 0, length: "Hello world.".count),
                    text: "Hello world."
                ),
                RenderedEditorSegment(
                    id: session.segments[1].id,
                    kind: session.segments[1].kind,
                    range: NSRange(location: "Hello world.".count, length: "Listening".count),
                    text: "Listening"
                )
            ]
        )
        session.insertFinalPlaceholder(for: 1)
        session.markTranscriptReady("continues here.", for: 1)

        #expect(session.assembledDraft == "Hello world. CustomWord continues here.")
    }

    @Test
    func pendingTranscriptCountIgnoresResolvedSegments() {
        var session = RecordingSession.begin(activeDevice: nil)

        session.insertCheckpointPlaceholder(for: 0)
        session.insertFinalPlaceholder(for: 1)
        session.markTranscriptReady("Hello", for: 0)

        #expect(session.pendingTranscriptCount == 1)
    }
}
