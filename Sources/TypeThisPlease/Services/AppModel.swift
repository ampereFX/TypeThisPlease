import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum MicrophoneTestState: Equatable {
        case idle
        case running
        case succeeded(String)
        case failed(String)
    }

    @Published var settings: AppSettings
    @Published private(set) var availableDevices: [AudioInputDevice] = []
    @Published private(set) var resolvedDevice: AudioInputDevice?
    @Published private(set) var installationStatus = WhisperInstallationStatus(
        runtimeURL: nil,
        modelURL: nil,
        runtimeExists: false,
        modelExists: false,
        runtimeDownloadInProgress: false,
        modelDownloadInProgress: false,
        lastError: nil
    )
    @Published private(set) var session: RecordingSession?
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var elapsedText: String = "00:00"
    @Published private(set) var microphoneTestState: MicrophoneTestState = .idle
    @Published private(set) var microphoneTestLevel: Double = 0
    @Published private(set) var microphoneTestPeakLevel: Double = 0

    let permissionsService: PermissionsService

    private let settingsStore: SettingsStore
    private let hotKeyService: HotKeyService
    private let outputService: OutputService
    private let modelManager: ModelManager
    private let whisperEngine: WhisperCPPTranscriptionEngine
    private let audioCaptureService: AudioCaptureService
    private lazy var audioDeviceMonitor = AudioDeviceMonitor { [weak self] devices in
        self?.handleDeviceUpdate(devices)
    }
    private let postProcessor: (any PostProcessor)?

    private var windowCoordinator: WindowCoordinator?
    private var timer: Timer?
    private var bootstrapCompleted = false
    private var segmentTasks: [UUID: Task<Void, Never>] = [:]

    init(
        settingsStore: SettingsStore = SettingsStore(),
        permissionsService: PermissionsService = PermissionsService(),
        hotKeyService: HotKeyService = HotKeyService(),
        outputService: OutputService = OutputService(),
        modelManager: ModelManager = ModelManager(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        postProcessor: (any PostProcessor)? = nil
    ) {
        self.settingsStore = settingsStore
        self.permissionsService = permissionsService
        self.hotKeyService = hotKeyService
        self.outputService = outputService
        self.modelManager = modelManager
        self.audioCaptureService = audioCaptureService
        self.postProcessor = postProcessor
        self.settings = settingsStore.load()
        self.whisperEngine = WhisperCPPTranscriptionEngine(modelManager: modelManager, configuration: settingsStore.load().whisperConfiguration)
    }

    func attach(windowCoordinator: WindowCoordinator) {
        self.windowCoordinator = windowCoordinator
    }

    func bootstrap() {
        guard !bootstrapCompleted else { return }
        bootstrapCompleted = true
        permissionsService.refresh()
        audioDeviceMonitor.start()
        configureHotKeys()
        refreshModelStatus()
        if !settings.hasCompletedOnboarding {
            windowCoordinator?.showOnboarding()
        } else if !hasTranscriptionBackendReady {
            statusMessage = recordingReadinessMessage
        }
    }

    var isRecordingActive: Bool {
        guard let session else { return false }
        switch session.state {
        case .recording, .preparing, .finalizing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var hasTranscriptionBackendReady: Bool {
        installationStatus.runtimeExists && installationStatus.modelExists
    }

    var canStartRecording: Bool {
        isRecordingActive || hasTranscriptionBackendReady
    }

    var recordingHotKeyDisplayString: String {
        settings.recordingHotKey?.displayString ?? "Not set"
    }

    var checkpointHotKeyDisplayString: String {
        settings.checkpointHotKey?.displayString ?? "Not set"
    }

    var recordingReadinessMessage: String {
        if isRecordingActive {
            return "Recording in progress."
        }
        if !installationStatus.runtimeExists && !installationStatus.modelExists {
            return "Install or configure the Whisper runtime and model in Settings."
        }
        if !installationStatus.runtimeExists {
            return "Install or configure the Whisper runtime in Settings."
        }
        if !installationStatus.modelExists {
            return "Install or configure a Whisper model in Settings."
        }
        return "Ready to record."
    }

    func toggleRecording() {
        Task {
            if isRecordingActive {
                await finalizeSession(deviceDisconnected: false)
            } else {
                await startSession()
            }
        }
    }

    func createCheckpoint() {
        Task {
            await checkpoint()
        }
    }

    func openDraftWindow() {
        windowCoordinator?.showDraft()
    }

    func openSettingsWindow() {
        windowCoordinator?.showSettings()
    }

    func openOnboardingWindow() {
        windowCoordinator?.showOnboarding()
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await permissionsService.requestMicrophoneAccess()
            if !granted {
                statusMessage = "Microphone permission is required for recording."
            }
        }
    }

    func requestAccessibilityPermission() {
        let granted = permissionsService.requestAccessibilityAccess(prompt: true)
        if !granted {
            statusMessage = "Accessibility remains optional unless you want auto-paste."
        }
    }

    func runMicrophoneSelfTest() {
        Task {
            await microphoneSelfTest()
        }
    }

    func completeOnboarding(openSettings: Bool) {
        settings.hasCompletedOnboarding = true
        persistSettings()
        windowCoordinator?.hideOnboarding()
        if openSettings {
            openSettingsWindow()
        }
    }

    func setRecordingHotKey(_ hotKey: HotKey?) -> Bool {
        if let hotKey, hotKey == settings.checkpointHotKey {
            settings.checkpointHotKey = nil
            settings.recordingHotKey = hotKey
            persistSettings()
            statusMessage = "Moved shortcut from Checkpoint to Start / Stop."
            return true
        }
        guard settings.recordingHotKey != hotKey else { return true }
        settings.recordingHotKey = hotKey
        persistSettings()
        return true
    }

    func setCheckpointHotKey(_ hotKey: HotKey?) -> Bool {
        if let hotKey, hotKey == settings.recordingHotKey {
            settings.recordingHotKey = nil
            settings.checkpointHotKey = hotKey
            persistSettings()
            statusMessage = "Moved shortcut from Start / Stop to Checkpoint."
            return true
        }
        guard settings.checkpointHotKey != hotKey else { return true }
        settings.checkpointHotKey = hotKey
        persistSettings()
        return true
    }

    func beginHotKeyCapture() {
        hotKeyService.setSuspended(true)
    }

    func endHotKeyCapture() {
        hotKeyService.setSuspended(false)
    }

    func setOutputAction(_ action: OutputAction) {
        settings.outputAction = action
        persistSettings()
    }

    func updateWhisperConfiguration(_ mutation: (inout WhisperConfiguration) -> Void) {
        mutation(&settings.whisperConfiguration)
        persistSettings()
        refreshModelStatus()
    }

    func updateManualBlock(id: UUID, text: String) {
        guard var session else { return }
        session.updateManualBlock(id, text: text)
        self.session = session
    }

    func addPreferredDevice(_ device: AudioInputDevice) {
        guard !settings.devicePreferences.contains(where: { $0.uid == device.uid }) else { return }
        settings.devicePreferences.append(AudioDevicePreference(uid: device.uid, name: device.name))
        persistSettings()
        updateResolvedDevice()
    }

    func movePreferredDeviceUp(_ deviceID: String) {
        guard let index = settings.devicePreferences.firstIndex(where: { $0.uid == deviceID }), index > 0 else { return }
        settings.devicePreferences.swapAt(index, index - 1)
        persistSettings()
        updateResolvedDevice()
    }

    func movePreferredDeviceDown(_ deviceID: String) {
        guard let index = settings.devicePreferences.firstIndex(where: { $0.uid == deviceID }), index < settings.devicePreferences.count - 1 else { return }
        settings.devicePreferences.swapAt(index, index + 1)
        persistSettings()
        updateResolvedDevice()
    }

    func removePreferredDevice(_ deviceID: String) {
        settings.devicePreferences.removeAll { $0.uid == deviceID }
        persistSettings()
        updateResolvedDevice()
    }

    func chooseWhisperExecutable() {
        if let url = chooseFile(canChooseDirectories: false) {
            updateWhisperConfiguration { $0.executablePath = url.path }
        }
    }

    func chooseWhisperModel() {
        if let url = chooseFile(canChooseDirectories: false) {
            updateWhisperConfiguration { $0.modelPath = url.path }
        }
    }

    func downloadRuntime() {
        Task {
            do {
                let url = try await modelManager.downloadRuntime(configuration: settings.whisperConfiguration)
                settings.whisperConfiguration.executablePath = url.path
                persistSettings()
                statusMessage = "Runtime downloaded."
            } catch {
                statusMessage = error.localizedDescription
            }
            refreshModelStatus()
        }
    }

    func downloadModel() {
        Task {
            do {
                let url = try await modelManager.downloadModel(configuration: settings.whisperConfiguration)
                settings.whisperConfiguration.modelPath = url.path
                persistSettings()
                statusMessage = "Model downloaded."
            } catch {
                statusMessage = error.localizedDescription
            }
            refreshModelStatus()
        }
    }

    private func startSession() async {
        guard !isRecordingActive else { return }
        guard hasTranscriptionBackendReady else {
            statusMessage = recordingReadinessMessage
            windowCoordinator?.showSettings()
            return
        }
        guard await ensureMicrophoneAccess() else {
            statusMessage = "Microphone permission is required."
            return
        }

        await whisperEngine.updateConfiguration(settings.whisperConfiguration)
        refreshModelStatus()

        do {
            try await whisperEngine.prepare()
        } catch {
            session = RecordingSession(state: .failed(error.localizedDescription))
            statusMessage = error.localizedDescription
            windowCoordinator?.showSettings()
            return
        }

        let activeDevice = resolvedDevice
        session = RecordingSession.begin(activeDevice: activeDevice)
        session?.state = .preparing
        statusMessage = activeDevice.map { "Recording with \($0.name)." } ?? "Recording with the default microphone."
        windowCoordinator?.showDraft()
        windowCoordinator?.showHUD()

        do {
            try audioCaptureService.start(device: activeDevice)
            session?.state = .recording
            startTimer()
        } catch {
            session?.state = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            windowCoordinator?.hideHUD()
        }
    }

    private func microphoneSelfTest() async {
        guard !isRecordingActive else {
            let message = "Stop the current recording before running the microphone test."
            microphoneTestState = .failed(message)
            statusMessage = message
            return
        }

        microphoneTestState = .running
        microphoneTestLevel = 0
        microphoneTestPeakLevel = 0

        guard await ensureMicrophoneAccess() else {
            let message = "Microphone permission is required for the self-test."
            microphoneTestState = .failed(message)
            statusMessage = message
            return
        }

        let activeDevice = resolvedDevice
        do {
            audioCaptureService.setLevelObserver { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let normalized = Double(level)
                    self.microphoneTestLevel = normalized
                    self.microphoneTestPeakLevel = max(self.microphoneTestPeakLevel, normalized)
                }
            }
            try audioCaptureService.start(device: activeDevice)
            try await Task.sleep(for: .seconds(3))
            _ = try audioCaptureService.stop(finalSegmentIndex: 0)
            let peakPercent = Int(microphoneTestPeakLevel * 100)
            let message = activeDevice.map {
                "Microphone test succeeded with \($0.name). Peak level: \(peakPercent)%."
            } ?? "Microphone test succeeded with the default input. Peak level: \(peakPercent)%."
            microphoneTestState = .succeeded(message)
            statusMessage = message
        } catch {
            audioCaptureService.cancel()
            microphoneTestLevel = 0
            let message = "Microphone test failed: \(error.localizedDescription)"
            microphoneTestState = .failed(message)
            statusMessage = message
        }
    }

    private func checkpoint() async {
        guard var session else { return }
        guard session.state == .recording else { return }

        do {
            let segment = try audioCaptureService.checkpoint(segmentIndex: session.activeSegmentIndex)
            session.insertCheckpointPlaceholder(for: segment.index)
            self.session = session
            transcribe(segment)
        } catch {
            session.state = .failed(error.localizedDescription)
            self.session = session
            statusMessage = error.localizedDescription
            windowCoordinator?.hideHUD()
        }
    }

    private func finalizeSession(deviceDisconnected: Bool) async {
        guard var session else { return }
        guard session.state == .recording || session.state == .preparing else { return }

        session.state = .finalizing
        self.session = session
        stopTimer()

        do {
            if let segment = try audioCaptureService.stop(finalSegmentIndex: session.activeSegmentIndex) {
                session.insertFinalPlaceholder(for: segment.index)
                self.session = session
                transcribe(segment)
            } else {
                await completeSessionIfPossible()
            }
            if deviceDisconnected {
                statusMessage = "Input device disappeared. Finalizing current draft."
            }
        } catch {
            session.state = .failed(error.localizedDescription)
            self.session = session
            statusMessage = error.localizedDescription
        }
    }

    private func transcribe(_ segment: TranscriptionSegment) {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await whisperEngine.transcribe(segment: segment)
                await MainActor.run {
                    self.apply(result: result)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.apply(error: "Transcription cancelled.", for: segment.index)
                }
            } catch {
                await MainActor.run {
                    self.apply(error: error.localizedDescription, for: segment.index)
                }
            }
        }
        segmentTasks[segment.id] = task
    }

    private func apply(result: TranscriptionResult) {
        guard var session else { return }
        session.markTranscriptReady(result.text, for: result.segmentIndex)
        self.session = session
        statusMessage = "Segment \(result.segmentIndex + 1) transcribed."
        Task { await completeSessionIfPossible() }
    }

    private func apply(error message: String, for segmentIndex: Int) {
        guard var session else { return }
        session.markTranscriptFailed(message, for: segmentIndex)
        self.session = session
        statusMessage = message
        Task { await completeSessionIfPossible() }
    }

    private func completeSessionIfPossible() async {
        guard var session else { return }
        guard session.state == .finalizing else { return }
        guard session.pendingTranscriptCount == 0 else { return }

        let rawText = session.assembledDraft
        let finalText: String
        if let postProcessor {
            do {
                finalText = try await postProcessor.process(
                    text: rawText,
                    context: PostProcessingContext(sessionID: session.id, startedAt: session.startedAt)
                ).processedText
            } catch {
                finalText = rawText
                statusMessage = "Post-processing failed. Using raw transcript."
            }
        } else {
            finalText = rawText
        }

        let delivery = outputService.deliver(text: finalText, action: settings.outputAction)
        session.finalText = finalText
        session.deliveryMessage = delivery.message
        session.state = .completed
        self.session = session
        lastTranscript = finalText
        statusMessage = delivery.message
        windowCoordinator?.hideHUD()
        windowCoordinator?.showDraft()
    }

    private func ensureMicrophoneAccess() async -> Bool {
        if permissionsService.microphoneState == .granted {
            return true
        }
        return await permissionsService.requestMicrophoneAccess()
    }

    private func handleDeviceUpdate(_ devices: [AudioInputDevice]) {
        availableDevices = devices
        updateResolvedDevice()

        if let session, !session.isTerminal, let activeDevice = session.activeDevice, !devices.contains(where: { $0.uid == activeDevice.uid }) {
            Task {
                await finalizeSession(deviceDisconnected: true)
            }
        }
    }

    private func updateResolvedDevice() {
        resolvedDevice = AudioDevicePolicy.resolve(preferences: settings.devicePreferences, availableDevices: availableDevices)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let session = self.session else { return }
                let elapsed = Int(Date().timeIntervalSince(session.startedAt))
                self.elapsedText = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
            }
        }
        timer?.fire()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedText = "00:00"
    }

    private func persistSettings() {
        settingsStore.save(settings)
        configureHotKeys()
        Task {
            await whisperEngine.updateConfiguration(settings.whisperConfiguration)
        }
    }

    private func configureHotKeys() {
        do {
            try hotKeyService.configure(
                recording: settings.recordingHotKey,
                checkpoint: settings.checkpointHotKey,
                onRecording: { [weak self] in self?.toggleRecording() },
                onCheckpoint: { [weak self] in self?.createCheckpoint() }
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshModelStatus() {
        Task {
            let status = await modelManager.status(configuration: settings.whisperConfiguration)
            await MainActor.run {
                self.installationStatus = status
                if !self.isRecordingActive {
                    self.statusMessage = self.recordingReadinessMessage
                }
            }
        }
    }

    private func chooseFile(canChooseDirectories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
