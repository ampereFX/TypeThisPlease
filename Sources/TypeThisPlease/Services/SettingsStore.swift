import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }
}
