import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey) else {
            DebugLog.log("No persisted settings found; using defaults.", category: "settings")
            return AppSettings()
        }
        let decoded = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
        let hydrated = hydrateInstalledPathsIfAvailable(decoded)
        DebugLog.log(
            "Loaded settings. executablePath='\(hydrated.whisperConfiguration.executablePath)' modelPath='\(hydrated.whisperConfiguration.modelPath)' finalize='\(hydrated.finalizeBehavior.rawValue)' onboarding=\(hydrated.hasCompletedOnboarding)",
            category: "settings"
        )
        return hydrated
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
        DebugLog.log(
            "Saved settings. executablePath='\(settings.whisperConfiguration.executablePath)' modelPath='\(settings.whisperConfiguration.modelPath)' finalize='\(settings.finalizeBehavior.rawValue)' onboarding=\(settings.hasCompletedOnboarding)",
            category: "settings"
        )
    }

    private func hydrateInstalledPathsIfAvailable(_ settings: AppSettings) -> AppSettings {
        var settings = settings
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TypeThisPlease", isDirectory: true)
        let runtimeURL = appSupport.appendingPathComponent("runtime").appendingPathComponent("whisper-cli")
        let modelURL = appSupport.appendingPathComponent("models").appendingPathComponent("whisper-model.bin")

        if settings.whisperConfiguration.executablePath.isEmpty, fileManager.isExecutableFile(atPath: runtimeURL.path) {
            settings.whisperConfiguration.executablePath = runtimeURL.path
            DebugLog.log("Hydrated executablePath from app support: \(runtimeURL.path)", category: "settings")
        }
        if settings.whisperConfiguration.modelPath.isEmpty, fileManager.fileExists(atPath: modelURL.path) {
            settings.whisperConfiguration.modelPath = modelURL.path
            DebugLog.log("Hydrated modelPath from app support: \(modelURL.path)", category: "settings")
        }

        return settings
    }
}
