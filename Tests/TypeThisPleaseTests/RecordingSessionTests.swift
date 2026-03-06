import Testing
@testable import TypeThisPlease

struct RecordingSessionTests {
    @Test
    func checkpointCreatesTranscriptAndManualBlocks() {
        var session = RecordingSession.begin(activeDevice: nil)

        session.insertCheckpointPlaceholder(for: 0)

        #expect(session.blocks.count == 2)
        #expect({
            if case .transcript(0) = session.blocks[0].kind { return true }
            return false
        }())
        #expect({
            if case .manual(0) = session.blocks[1].kind { return true }
            return false
        }())
    }

    @Test
    func transcriptsAndManualTextAssembleInDeclaredOrder() {
        var session = RecordingSession.begin(activeDevice: nil)

        session.insertCheckpointPlaceholder(for: 0)
        session.markTranscriptReady("Hello world.", for: 0)
        let manualBlock = session.blocks[1]
        session.updateManualBlock(manualBlock.id, text: " CustomWord")
        session.insertFinalPlaceholder(for: 1)
        session.markTranscriptReady(" continues here.", for: 1)

        #expect(session.assembledDraft == "Hello world. CustomWord continues here.")
    }

    @Test
    func pendingTranscriptCountIgnoresReadyBlocks() {
        var session = RecordingSession.begin(activeDevice: nil)

        session.insertCheckpointPlaceholder(for: 0)
        session.insertFinalPlaceholder(for: 1)
        session.markTranscriptReady("Hello", for: 0)

        #expect(session.pendingTranscriptCount == 1)
    }
}
