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
    private var levelObserver: (@Sendable (Float) -> Void)?
    private(set) var isRunning = false

    func setLevelObserver(_ observer: (@Sendable (Float) -> Void)?) {
        DebugLog.log("setLevelObserver nil=\(observer == nil)", category: "audio")
        lock.lock()
        levelObserver = observer
        lock.unlock()
    }

    func start(device: AudioInputDevice?) throws {
        DebugLog.log("start device='\(device?.name ?? "default")' uid='\(device?.uid ?? "-")' isRunning=\(isRunning)", category: "audio")
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
        DebugLog.log("Input format sampleRate=\(format.sampleRate) channels=\(format.channelCount) commonFormat=\(format.commonFormat.rawValue)", category: "audio")
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
            DebugLog.log("Audio engine started. sessionDirectory='\(sessionDirectoryURL.path)'", category: "audio")
        } catch {
            inputNode.removeTap(onBus: 0)
            reset()
            DebugLog.log("Audio engine failed to start: \(error.localizedDescription)", category: "audio")
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }
    }

    func checkpoint(segmentIndex: Int) throws -> TranscriptionSegment {
        DebugLog.log("checkpoint segmentIndex=\(segmentIndex) isRunning=\(isRunning)", category: "audio")
        guard isRunning, let engine, let sessionDirectoryURL else {
            throw CaptureError.notRunning
        }

        let format = engine.inputNode.inputFormat(forBus: 0)
        let nextWriter = try makeWriter(segmentIndex: segmentIndex + 1, in: sessionDirectoryURL, format: format)
        guard let completed = swapWriter(nextWriter) else {
            throw CaptureError.notRunning
        }
        DebugLog.log("checkpoint completed segment file='\(completed.segment.fileURL.path)' nextWriter='\(nextWriter.segment.fileURL.path)'", category: "audio")
        return completed.segment
    }

    func stop(finalSegmentIndex: Int) throws -> TranscriptionSegment? {
        DebugLog.log("stop finalSegmentIndex=\(finalSegmentIndex) isRunning=\(isRunning)", category: "audio")
        guard isRunning, let engine else { throw CaptureError.notRunning }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        let completed = swapWriter(nil)?.segment
        reset(keepSessionDirectory: true)
        DebugLog.log("stop completedSegment='\(completed?.fileURL.path ?? "nil")'", category: "audio")
        return completed
    }

    func cancel() {
        DebugLog.log("cancel", category: "audio")
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        reset()
    }

    private func write(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let writer = currentWriter
        let levelObserver = levelObserver
        lock.unlock()
        if let levelObserver {
            levelObserver(Self.calculateLevel(from: buffer))
        }
        guard let writer else { return }
        try? writer.file.write(from: buffer)
    }

    private func makeSessionDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("TypeThisPlease")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        DebugLog.log("Created session directory '\(url.path)'", category: "audio")
        return url
    }

    private func makeWriter(segmentIndex: Int, in directoryURL: URL, format: AVAudioFormat) throws -> WriterBox {
        let fileURL = directoryURL.appendingPathComponent("segment-\(segmentIndex).wav")
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        DebugLog.log("Created writer segmentIndex=\(segmentIndex) path='\(fileURL.path)'", category: "audio")
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
        DebugLog.log("reset keepSessionDirectory=\(keepSessionDirectory) sessionDirectory='\(sessionDirectoryURL?.path ?? "nil")'", category: "audio")
        currentWriter = nil
        engine = nil
        selectedDevice = nil
        levelObserver = nil
        isRunning = false

        if !keepSessionDirectory, let sessionDirectoryURL {
            try? fileManager.removeItem(at: sessionDirectoryURL)
        }
        sessionDirectoryURL = nil
    }

    private static func calculateLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else { return 0 }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else { return 0 }
            return normalizedLevel(
                channels: channels,
                frameLength: Int(buffer.frameLength),
                channelCount: Int(buffer.format.channelCount)
            )
        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else { return 0 }
            return normalizedIntLevel(
                channels: channels,
                frameLength: Int(buffer.frameLength),
                channelCount: Int(buffer.format.channelCount),
                scale: Float(Int16.max)
            )
        case .pcmFormatInt32:
            guard let channels = buffer.int32ChannelData else { return 0 }
            return normalizedIntLevel(
                channels: channels,
                frameLength: Int(buffer.frameLength),
                channelCount: Int(buffer.format.channelCount),
                scale: Float(Int32.max)
            )
        default:
            return 0
        }
    }

    private static func normalizedLevel(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> Float {
        var peak: Float = 0
        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frame in 0..<frameLength {
                peak = max(peak, abs(channel[frame]))
            }
        }
        return max(0, min(1, peak))
    }

    private static func normalizedIntLevel<T: BinaryInteger>(
        channels: UnsafePointer<UnsafeMutablePointer<T>>,
        frameLength: Int,
        channelCount: Int,
        scale: Float
    ) -> Float {
        var peak: Float = 0
        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frame in 0..<frameLength {
                peak = max(peak, abs(Float(channel[frame])) / scale)
            }
        }
        return max(0, min(1, peak))
    }
}
