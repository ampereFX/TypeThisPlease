import Foundation

enum OutputAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case copy
    case copyAndPaste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy:
            return "Copy to Clipboard"
        case .copyAndPaste:
            return "Copy and Paste"
        }
    }
}

struct WhisperConfiguration: Codable, Equatable, Sendable {
    var executablePath: String = ""
    var modelPath: String = ""
    var runtimeDownloadURL: String = ""
    var modelDownloadURL: String = ""
    var language: String = "auto"
    var prompt: String = ""
    var extraArguments: String = "--no-prints"
}

struct AppSettings: Codable, Equatable, Sendable {
    var recordingHotKey: HotKey? = .defaultRecording
    var checkpointHotKey: HotKey? = .defaultCheckpoint
    var outputAction: OutputAction = .copy
    var devicePreferences: [AudioDevicePreference] = []
    var preferredEngineID: String = WhisperCPPTranscriptionEngine.identifier
    var whisperConfiguration = WhisperConfiguration()
    var hasCompletedOnboarding = false
}
