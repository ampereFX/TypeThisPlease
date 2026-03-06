import Foundation

actor WhisperCPPTranscriptionEngine: TranscriptionEngine {
    static let identifier = "whisper.cpp"

    enum EngineError: LocalizedError {
        case runtimeMissing
        case modelMissing
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .runtimeMissing:
                return "The Whisper runtime is missing."
            case .modelMissing:
                return "The Whisper model is missing."
            case .processFailed(let message):
                return message
            }
        }
    }

    let capabilities: Set<TranscriptionCapability> = [.localExecution, .promptConditioning]

    private let modelManager: ModelManager
    private var configuration: WhisperConfiguration
    private var processes: [UUID: Process] = [:]

    init(modelManager: ModelManager, configuration: WhisperConfiguration = WhisperConfiguration()) {
        self.modelManager = modelManager
        self.configuration = configuration
    }

    func updateConfiguration(_ configuration: WhisperConfiguration) {
        self.configuration = configuration
    }

    func prepare() async throws {
        let status = await modelManager.status(configuration: configuration)
        guard status.runtimeExists, status.runtimeURL != nil else { throw EngineError.runtimeMissing }
        guard status.modelExists, status.modelURL != nil else { throw EngineError.modelMissing }
    }

    func transcribe(segment: TranscriptionSegment) async throws -> TranscriptionResult {
        let status = await modelManager.status(configuration: configuration)
        guard let runtimeURL = status.runtimeURL, status.runtimeExists else { throw EngineError.runtimeMissing }
        guard let modelURL = status.modelURL, status.modelExists else { throw EngineError.modelMissing }

        let outputBaseURL = segment.fileURL.deletingPathExtension()
        let outputTextURL = outputBaseURL.appendingPathExtension("txt")
        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = runtimeURL

        var arguments = [
            "-m", modelURL.path,
            "-f", segment.fileURL.path,
            "-of", outputBaseURL.path,
            "-otxt"
        ]
        let language = configuration.language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !language.isEmpty {
            arguments += ["-l", language]
        }
        if !configuration.prompt.isEmpty {
            arguments += ["--prompt", configuration.prompt]
        }
        if !configuration.extraArguments.isEmpty {
            arguments.append(contentsOf: configuration.extraArguments.split(separator: " ").map(String.init))
        }

        process.arguments = arguments
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        processes[segment.id] = process

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] process in
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    Task {
                        await self?.clearProcess(for: segment.id)
                        if process.terminationStatus == 0 {
                            do {
                                let text = try String(contentsOf: outputTextURL, encoding: .utf8)
                                continuation.resume(returning: TranscriptionResult(segmentIndex: segment.index, text: text))
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        } else {
                            continuation.resume(throwing: EngineError.processFailed(stderr.isEmpty ? "Whisper exited with status \(process.terminationStatus)." : stderr))
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task {
                await self.cancel(job: segment.id)
            }
        }
    }

    func cancel(job: UUID) async {
        guard let process = processes[job] else { return }
        process.terminate()
        processes[job] = nil
    }

    private func clearProcess(for job: UUID) {
        processes[job] = nil
    }
}
