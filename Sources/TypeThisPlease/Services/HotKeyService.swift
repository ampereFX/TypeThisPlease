import Carbon
import Foundation

final class HotKeyService {
    enum Action: UInt32 {
        case toggleRecording = 1
        case checkpoint = 2
    }

    enum HotKeyError: LocalizedError {
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let status):
                return "Hotkey registration failed with status \(status)."
            }
        }
    }

    private let signature: OSType = 0x54545048
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var configuredRecordingHotKey: HotKey?
    private var configuredCheckpointHotKey: HotKey?
    private var isSuspended = false

    init() {
        DebugLog.log("HotKeyService init", category: "hotkey")
        installHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func configure(
        recording: HotKey?,
        checkpoint: HotKey?,
        onRecording: @escaping @MainActor () -> Void,
        onCheckpoint: @escaping @MainActor () -> Void
    ) throws {
        DebugLog.log(
            "Configuring hotkeys. recording='\(recording?.displayString ?? "nil")' checkpoint='\(checkpoint?.displayString ?? "nil")' suspended=\(isSuspended)",
            category: "hotkey"
        )
        configuredRecordingHotKey = recording
        configuredCheckpointHotKey = checkpoint
        handlers = [
            Action.toggleRecording.rawValue: onRecording,
            Action.checkpoint.rawValue: onCheckpoint
        ]

        guard !isSuspended else {
            DebugLog.log("HotKeyService is suspended; unregistering instead of registering.", category: "hotkey")
            unregisterAll()
            return
        }

        try registerConfiguredHotKeys()
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        DebugLog.log("setSuspended -> \(suspended)", category: "hotkey")
        if suspended {
            unregisterAll()
            return
        }

        try? registerConfiguredHotKeys()
    }

    private func installHandler() {
        DebugLog.log("Installing Carbon hotkey handler", category: "hotkey")
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            return service.handle(eventRef)
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    private func register(_ hotKey: HotKey, id: UInt32) throws {
        DebugLog.log("Registering hotkey id=\(id) key='\(hotKey.displayString)' code=\(hotKey.keyCode) modifiers=\(hotKey.modifiers.rawValue)", category: "hotkey")
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw HotKeyError.registrationFailed(status)
        }
        registeredHotKeys[id] = hotKeyRef
    }

    private func unregisterAll() {
        if !registeredHotKeys.isEmpty {
            DebugLog.log("Unregistering \(registeredHotKeys.count) hotkeys", category: "hotkey")
        }
        for hotKeyRef in registeredHotKeys.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKeys.removeAll()
    }

    private func registerConfiguredHotKeys() throws {
        unregisterAll()

        if let configuredRecordingHotKey {
            try register(configuredRecordingHotKey, id: Action.toggleRecording.rawValue)
        }
        if let configuredCheckpointHotKey {
            try register(configuredCheckpointHotKey, id: Action.checkpoint.rawValue)
        }
    }

    private func handle(_ eventRef: EventRef?) -> OSStatus {
        if isSuspended {
            DebugLog.log("Ignoring hotkey event because service is suspended.", category: "hotkey")
            return noErr
        }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        DebugLog.log("Received hotkey event id=\(hotKeyID.id)", category: "hotkey")

        if let handler = handlers[hotKeyID.id] {
            Task { @MainActor in
                DebugLog.log("Dispatching handler for hotkey id=\(hotKeyID.id)", category: "hotkey")
                handler()
            }
        }
        return noErr
    }
}
