import CoreAudio
import Testing
@testable import TypeThisPlease

struct AudioDevicePolicyTests {
    @Test
    func preferredDeviceWinsWhenAvailable() {
        let dockMic = AudioInputDevice(id: 1, uid: "dock", name: "Dock Mic", isDefault: false, transportType: kAudioDeviceTransportTypeUSB, inputChannelCount: 1)
        let builtIn = AudioInputDevice(id: 2, uid: "builtin", name: "MacBook Pro Microphone", isDefault: true, transportType: kAudioDeviceTransportTypeBuiltIn, inputChannelCount: 1)

        let resolved = AudioDevicePolicy.resolve(
            preferences: [.init(uid: "dock", name: "Dock Mic")],
            availableDevices: [builtIn, dockMic]
        )

        #expect(resolved?.uid == "dock")
    }

    @Test
    func defaultDeviceIsFallbackWhenNoPreferenceMatches() {
        let dockMic = AudioInputDevice(id: 1, uid: "dock", name: "Dock Mic", isDefault: false, transportType: kAudioDeviceTransportTypeUSB, inputChannelCount: 1)
        let builtIn = AudioInputDevice(id: 2, uid: "builtin", name: "MacBook Pro Microphone", isDefault: true, transportType: kAudioDeviceTransportTypeBuiltIn, inputChannelCount: 1)

        let resolved = AudioDevicePolicy.resolve(
            preferences: [.init(uid: "missing", name: "Missing Mic")],
            availableDevices: [dockMic, builtIn]
        )

        #expect(resolved?.uid == "builtin")
    }
}
