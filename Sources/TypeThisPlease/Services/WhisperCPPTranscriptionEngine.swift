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
        DebugLog.log("Whisper engine init executablePath='\(configuration.executablePath)' modelPath='\(configuration.modelPath)'", category: "whisper")
    }

    func updateConfiguration(_ configuration: WhisperConfiguration) {
        DebugLog.log("Whisper updateConfiguration executablePath='\(configuration.executablePath)' modelPath='\(configuration.modelPath)' language='\(configuration.language)'", category: "whisper")
        self.configuration = configuration
    }

    func prepare() async throws {
        DebugLog.log("Whisper prepare begin", category: "whisper")
        let status = await modelManager.status(configuration: configuration)
        DebugLog.log("Whisper prepare status runtimeExists=\(status.runtimeExists) modelExists=\(status.modelExists) runtimeURL='\(status.runtimeURL?.path ?? "nil")' modelURL='\(status.modelURL?.path ?? "nil")'", category: "whisper")
        guard status.runtimeExists, status.runtimeURL != nil else { throw EngineError.runtimeMissing }
        guard status.modelExists, status.modelURL != nil else { throw EngineError.modelMissing }
        DebugLog.log("Whisper prepare succeeded", category: "whisper")
    }

    func transcribe(segment: TranscriptionSegment) async throws -> TranscriptionResult {
        DebugLog.log("Whisper transcribe begin segmentIndex=\(segment.index) file='\(segment.fileURL.path)'", category: "whisper")
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

        DebugLog.log("Whisper process executable='\(runtimeURL.path)' arguments=\(arguments.joined(separator: " "))", category: "whisper")
        process.arguments = arguments
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        processes[segment.id] = process

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] process in
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    DebugLog.log("Whisper process terminated status=\(process.terminationStatus) segmentIndex=\(segment.index) stderr='\(stderr)'", category: "whisper")
                    Task {
                        await self?.clearProcess(for: segment.id)
                        if process.terminationStatus == 0 {
                            do {
                                let text = try String(contentsOf: outputTextURL, encoding: .utf8)
                                DebugLog.log("Whisper output loaded segmentIndex=\(segment.index) length=\(text.count)", category: "whisper")
                                continuation.resume(returning: TranscriptionResult(segmentIndex: segment.index, text: text))
                            } catch {
                                DebugLog.log("Whisper output read failed segmentIndex=\(segment.index) error='\(error.localizedDescription)'", category: "whisper")
                                continuation.resume(throwing: error)
                            }
                        } else {
                            continuation.resume(throwing: EngineError.processFailed(stderr.isEmpty ? "Whisper exited with status \(process.terminationStatus)." : stderr))
                        }
                    }
                }

                do {
                    DebugLog.log("Running Whisper process for segmentIndex=\(segment.index)", category: "whisper")
                    try process.run()
                } catch {
                    DebugLog.log("Failed to run Whisper process segmentIndex=\(segment.index) error='\(error.localizedDescription)'", category: "whisper")
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
        DebugLog.log("Cancelling Whisper process job=\(job.uuidString)", category: "whisper")
        process.terminate()
        processes[job] = nil
    }

    private func clearProcess(for job: UUID) {
        processes[job] = nil
    }
}
