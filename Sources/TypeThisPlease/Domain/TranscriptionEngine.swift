import Foundation

struct TranscriptionSegment: Identifiable, Hashable, Sendable {
    let id: UUID
    let index: Int
    let fileURL: URL
}

struct TranscriptionResult: Equatable, Sendable {
    let segmentIndex: Int
    let text: String
}

enum TranscriptionCapability: String, Hashable, Sendable {
    case localExecution
    case promptConditioning
}

protocol TranscriptionEngine: Sendable {
    var capabilities: Set<TranscriptionCapability> { get }
    func prepare() async throws
    func transcribe(segment: TranscriptionSegment) async throws -> TranscriptionResult
    func cancel(job: UUID) async
}

struct ProcessedText: Equatable, Sendable {
    let rawText: String
    let processedText: String
}

struct PostProcessingContext: Equatable, Sendable {
    let sessionID: UUID
    let startedAt: Date
}

protocol PostProcessor: Sendable {
    func process(text: String, context: PostProcessingContext) async throws -> ProcessedText
}
