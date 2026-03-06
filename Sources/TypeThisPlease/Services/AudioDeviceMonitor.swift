import CoreAudio
import Foundation

final class AudioDeviceMonitor {
    private let queue = DispatchQueue(label: "TypeThisPlease.AudioDeviceMonitor")
    private let onChange: @MainActor ([AudioInputDevice]) -> Void

    init(onChange: @escaping @MainActor ([AudioInputDevice]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        refresh()
        addListener(selector: kAudioHardwarePropertyDevices)
        addListener(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func refresh() {
        let devices = Self.loadDevices()
        let handler = onChange
        Task { @MainActor in
            handler(devices)
        }
    }

    private func addListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue
        ) { [weak self] _, _ in
            self?.refresh()
        }
    }

    static func loadDevices() -> [AudioInputDevice] {
        let defaultDeviceID = defaultInputDeviceID()
        let deviceIDs = loadDeviceIDs()

        return deviceIDs.compactMap { deviceID in
            guard inputChannelCount(for: deviceID) > 0 else { return nil }
            guard let name = stringProperty(
                selector: kAudioObjectPropertyName,
                deviceID: deviceID
            ) else { return nil }
            guard let uid = stringProperty(
                selector: kAudioDevicePropertyDeviceUID,
                deviceID: deviceID
            ) else { return nil }

            return AudioInputDevice(
                id: deviceID,
                uid: uid,
                name: name,
                isDefault: deviceID == defaultDeviceID,
                transportType: transportType(for: deviceID),
                inputChannelCount: inputChannelCount(for: deviceID)
            )
        }.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func loadDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs
    }

    private static func defaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID) == noErr else {
            return nil
        }
        return deviceID
    }

    private static func transportType(for deviceID: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value) == noErr else {
            return 0
        }
        return value
    }

    private static func inputChannelCount(for deviceID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }

        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer) == noErr else {
            return 0
        }

        let bufferList = pointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { total, buffer in
            total + Int(buffer.mNumberChannels)
        }
    }

    private static func stringProperty(selector: AudioObjectPropertySelector, deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfString) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let cfString else { return nil }
        return cfString as String
    }
}
