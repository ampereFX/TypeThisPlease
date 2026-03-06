import AVFoundation
import AudioToolbox
import Foundation

final class AudioCaptureService {
    enum CaptureError: LocalizedError {
        case alreadyRunning
        case notRunning
        case fileCreationFailed
        case engineStartFailed(String)
        case deviceSelectionFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "A recording session is already active."
            case .notRunning:
                return "No recording session is active."
            case .fileCreationFailed:
                return "The audio segment file could not be created."
            case .engineStartFailed(let message):
                return "The audio engine could not start: \(message)"
            case .deviceSelectionFailed(let message):
                return "The selected input device could not be activated: \(message)"
            }
        }
    }

    private final class WriterBox {
        let segment: TranscriptionSegment
        let file: AVAudioFile

        init(segment: TranscriptionSegment, file: AVAudioFile) {
            self.segment = segment
            self.file = file
        }
    }

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private var engine: AVAudioEngine?
    private var currentWriter: WriterBox?
    private var sessionDirectoryURL: URL?
    private var selectedDevice: AudioInputDevice?
    private(set) var isRunning = false

    func start(device: AudioInputDevice?) throws {
        guard !isRunning else { throw CaptureError.alreadyRunning }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        if let device {
            do {
                try inputNode.auAudioUnit.setDeviceID(device.id)
            } catch {
                throw CaptureError.deviceSelectionFailed(error.localizedDescription)
            }
            selectedDevice = device
        } else {
            selectedDevice = nil
        }

        let format = inputNode.inputFormat(forBus: 0)
        let sessionDirectoryURL = try makeSessionDirectory()
        let initialWriter = try makeWriter(segmentIndex: 0, in: sessionDirectoryURL, format: format)

        currentWriter = initialWriter
        self.sessionDirectoryURL = sessionDirectoryURL
        self.engine = engine

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.write(buffer: buffer)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            reset()
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }
    }

    func checkpoint(segmentIndex: Int) throws -> TranscriptionSegment {
        guard isRunning, let engine, let sessionDirectoryURL else {
            throw CaptureError.notRunning
        }

        let format = engine.inputNode.inputFormat(forBus: 0)
        let nextWriter = try makeWriter(segmentIndex: segmentIndex + 1, in: sessionDirectoryURL, format: format)
        guard let completed = swapWriter(nextWriter) else {
            throw CaptureError.notRunning
        }
        return completed.segment
    }

    func stop(finalSegmentIndex: Int) throws -> TranscriptionSegment? {
        guard isRunning, let engine else { throw CaptureError.notRunning }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        let completed = swapWriter(nil)?.segment
        reset(keepSessionDirectory: true)
        return completed
    }

    func cancel() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        reset()
    }

    private func write(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let writer = currentWriter
        lock.unlock()
        guard let writer else { return }
        try? writer.file.write(from: buffer)
    }

    private func makeSessionDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("TypeThisPlease")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeWriter(segmentIndex: Int, in directoryURL: URL, format: AVAudioFormat) throws -> WriterBox {
        let fileURL = directoryURL.appendingPathComponent("segment-\(segmentIndex).caf")
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        return WriterBox(segment: TranscriptionSegment(id: UUID(), index: segmentIndex, fileURL: fileURL), file: file)
    }

    private func swapWriter(_ writer: WriterBox?) -> WriterBox? {
        lock.lock()
        defer { lock.unlock() }
        let previous = currentWriter
        currentWriter = writer
        return previous
    }

    private func reset(keepSessionDirectory: Bool = false) {
        currentWriter = nil
        engine = nil
        selectedDevice = nil
        isRunning = false

        if !keepSessionDirectory, let sessionDirectoryURL {
            try? fileManager.removeItem(at: sessionDirectoryURL)
        }
        sessionDirectoryURL = nil
    }
}
