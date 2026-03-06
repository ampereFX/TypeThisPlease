import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isDefault: Bool
    let transportType: UInt32
    let inputChannelCount: Int

    var stableID: String { uid }
}

struct AudioDevicePreference: Identifiable, Codable, Hashable, Sendable {
    var id: String { uid }
    var uid: String
    var name: String
}

enum AudioDevicePolicy {
    static func resolve(
        preferences: [AudioDevicePreference],
        availableDevices: [AudioInputDevice]
    ) -> AudioInputDevice? {
        guard !availableDevices.isEmpty else { return nil }

        for preference in preferences {
            if let match = availableDevices.first(where: { $0.uid == preference.uid }) {
                return match
            }
        }

        return availableDevices.first(where: \.isDefault) ?? availableDevices.sorted(by: { lhs, rhs in
            if lhs.transportType == kAudioDeviceTransportTypeBuiltIn && rhs.transportType != kAudioDeviceTransportTypeBuiltIn {
                return false
            }
            if rhs.transportType == kAudioDeviceTransportTypeBuiltIn && lhs.transportType != kAudioDeviceTransportTypeBuiltIn {
                return true
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }).first
    }
}
