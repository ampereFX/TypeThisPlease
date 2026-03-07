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

enum FinalizeBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case immediate
    case reviewBeforeDelivery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediate:
            return "Deliver Immediately"
        case .reviewBeforeDelivery:
            return "Review Before Delivery"
        }
    }
}

struct FloatingPanelFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
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
    var finalizeBehavior: FinalizeBehavior = .reviewBeforeDelivery
    var devicePreferences: [AudioDevicePreference] = []
    var preferredEngineID: String = WhisperCPPTranscriptionEngine.identifier
    var whisperConfiguration = WhisperConfiguration()
    var floatingPanelFrame: FloatingPanelFrame?
    var hasCompletedOnboarding = false

    private enum CodingKeys: String, CodingKey {
        case recordingHotKey
        case checkpointHotKey
        case outputAction
        case finalizeBehavior
        case devicePreferences
        case preferredEngineID
        case whisperConfiguration
        case floatingPanelFrame
        case hasCompletedOnboarding
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingHotKey = try container.decodeIfPresent(HotKey.self, forKey: .recordingHotKey) ?? .defaultRecording
        checkpointHotKey = try container.decodeIfPresent(HotKey.self, forKey: .checkpointHotKey) ?? .defaultCheckpoint
        outputAction = try container.decodeIfPresent(OutputAction.self, forKey: .outputAction) ?? .copy
        finalizeBehavior = try container.decodeIfPresent(FinalizeBehavior.self, forKey: .finalizeBehavior) ?? .reviewBeforeDelivery
        devicePreferences = try container.decodeIfPresent([AudioDevicePreference].self, forKey: .devicePreferences) ?? []
        preferredEngineID = try container.decodeIfPresent(String.self, forKey: .preferredEngineID) ?? WhisperCPPTranscriptionEngine.identifier
        whisperConfiguration = try container.decodeIfPresent(WhisperConfiguration.self, forKey: .whisperConfiguration) ?? WhisperConfiguration()
        floatingPanelFrame = try container.decodeIfPresent(FloatingPanelFrame.self, forKey: .floatingPanelFrame)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
}
