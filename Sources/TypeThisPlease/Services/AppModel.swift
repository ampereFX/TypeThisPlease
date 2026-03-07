import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static let logger = Logger(subsystem: "TypeThisPlease", category: "AppModel")

    struct Notice: Equatable {
        let message: String
        let isError: Bool
    }

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
    @Published private(set) var waveformSamples: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var transientNotice: Notice?
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
    private var editorHasFocus = false
    private var noticeTask: Task<Void, Never>?

    deinit {
        DebugLog.log("AppModel deinit", category: "app")
    }

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
        Self.logger.notice("Bootstrap started. executablePath: \(self.settings.whisperConfiguration.executablePath, privacy: .public), modelPath: \(self.settings.whisperConfiguration.modelPath, privacy: .public)")
        DebugLog.log("bootstrap executablePath='\(self.settings.whisperConfiguration.executablePath)' modelPath='\(self.settings.whisperConfiguration.modelPath)'", category: "app")
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
        case .recording, .preparing:
            return true
        case .review, .finalizing, .idle, .completed, .failed:
            return false
        }
    }

    var isReviewing: Bool {
        session?.state == .review
    }

    var hasTranscriptionBackendReady: Bool {
        installationStatus.runtimeExists && installationStatus.modelExists
    }

    var canStartRecording: Bool {
        true
    }

    var canTriggerCheckpoint: Bool {
        session?.canCheckpoint == true
    }

    var canFinalizeReview: Bool {
        guard let session else { return false }
        return session.state == .review && !session.hasPendingTranscription
    }

    var shouldShowEditor: Bool {
        session != nil || !lastTranscript.isEmpty
    }

    var menuHeadline: String {
        if let session {
            switch session.state {
            case .preparing, .recording:
                return "Recording pipeline active"
            case .review:
                return session.hasPendingTranscription ? "Waiting for transcription" : "Review before delivery"
            case .finalizing:
                return "Finalizing transcript"
            case .completed:
                return "Transcript completed"
            case .failed:
                return "Session failed"
            case .idle:
                break
            }
        }
        return hasTranscriptionBackendReady ? "Ready" : "Setup Required"
    }

    var panelSubtitle: String {
        guard let session else { return "Ready for the next capture." }
        switch session.state {
        case .preparing:
            return "Preparing \(session.activeDevice?.name ?? "default microphone")"
        case .recording:
            return session.activeDevice?.name ?? "Default microphone"
        case .review:
            return session.hasPendingTranscription ? "Waiting for remaining transcription…" : "Review the draft before delivery."
        case .finalizing:
            return "Finalizing transcript…"
        case .completed:
            return session.deliveryMessage ?? "Transcript completed."
        case .failed(let message):
            return message
        case .idle:
            return "Idle"
        }
    }

    var hotKeyHints: [(title: String, shortcut: String, isEnabled: Bool, action: () -> Void)] {
        [
            ("Start / Stop", recordingHotKeyDisplayString, true, { [weak self] in self?.toggleRecording() }),
            ("Checkpoint", checkpointHotKeyDisplayString, canTriggerCheckpoint, { [weak self] in self?.createCheckpoint() })
        ]
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

    var primaryMenuButtonTitle: String {
        if session == nil {
            return hasTranscriptionBackendReady ? "Start Recording" : "Open Setup"
        }
        return isRecordingActive ? "Stop Recording" : "Finish Review"
    }

    func toggleRecording() {
        Task {
            Self.logger.notice("toggleRecording called. session nil: \(self.session == nil, privacy: .public), backend ready: \(self.hasTranscriptionBackendReady, privacy: .public)")
            DebugLog.log("toggleRecording sessionNil=\(self.session == nil) backendReady=\(self.hasTranscriptionBackendReady) state='\(String(describing: self.session?.state))'", category: "app")
            if session == nil {
                await startSession()
                return
            }

            if isRecordingActive {
                await stopOrReviewSession(deviceDisconnected: false)
            } else if canFinalizeReview {
                await deliverReviewedSession()
            } else if isReviewing {
                showNotice("Waiting for remaining transcription before delivery.", isError: false)
            }
        }
    }

    func createCheckpoint() {
        Task {
            DebugLog.log("createCheckpoint requested state='\(String(describing: self.session?.state))'", category: "app")
            await checkpoint()
        }
    }

    func openSettingsWindow() {
        Self.logger.notice("Opening settings window.")
        DebugLog.log("openSettingsWindow", category: "app")
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

    func applyEditorChange(range: NSRange, replacement: String, renderedSegments: [RenderedEditorSegment]) {
        guard var session else { return }
        session.applyEditorChange(range: range, replacement: replacement, renderedSegments: renderedSegments)
        self.session = session
    }

    func setEditorFocus(_ isFocused: Bool) {
        editorHasFocus = isFocused
    }

    func updateFloatingPanelFrame(_ frame: CGRect) {
        settings.floatingPanelFrame = FloatingPanelFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
        persistSettings()
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
        DebugLog.log("beginHotKeyCapture", category: "app")
        hotKeyService.setSuspended(true)
    }

    func endHotKeyCapture() {
        DebugLog.log("endHotKeyCapture", category: "app")
        hotKeyService.setSuspended(false)
    }

    func setOutputAction(_ action: OutputAction) {
        settings.outputAction = action
        persistSettings()
    }

    func updateFinalizeBehavior(_ behavior: FinalizeBehavior) {
        settings.finalizeBehavior = behavior
        persistSettings()
    }

    func updateWhisperConfiguration(_ mutation: (inout WhisperConfiguration) -> Void) {
        mutation(&settings.whisperConfiguration)
        persistSettings()
        refreshModelStatus()
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
        guard session == nil else { return }
        Self.logger.notice("startSession preflight. backend ready: \(self.hasTranscriptionBackendReady, privacy: .public), executablePath: \(self.settings.whisperConfiguration.executablePath, privacy: .public), modelPath: \(self.settings.whisperConfiguration.modelPath, privacy: .public)")
        DebugLog.log("startSession preflight backendReady=\(self.hasTranscriptionBackendReady) executablePath='\(self.settings.whisperConfiguration.executablePath)' modelPath='\(self.settings.whisperConfiguration.modelPath)'", category: "app")
        guard hasTranscriptionBackendReady else {
            statusMessage = recordingReadinessMessage
            showNotice(recordingReadinessMessage, isError: false)
            windowCoordinator?.showSettings()
            return
        }
        guard await ensureMicrophoneAccess() else {
            statusMessage = "Microphone permission is required."
            DebugLog.log("startSession microphone access denied", category: "app")
            return
        }

        await whisperEngine.updateConfiguration(settings.whisperConfiguration)
        DebugLog.log("startSession updated whisper configuration", category: "app")
        refreshModelStatus()

        do {
            try await whisperEngine.prepare()
        } catch {
            DebugLog.log("startSession prepare failed error='\(error.localizedDescription)'", category: "app")
            session = RecordingSession(state: .failed(error.localizedDescription))
            statusMessage = error.localizedDescription
            showNotice(error.localizedDescription, isError: true)
            windowCoordinator?.showSettings()
            return
        }

        let activeDevice = resolvedDevice
        session = RecordingSession.begin(activeDevice: activeDevice)
        session?.state = .preparing
        statusMessage = activeDevice.map { "Recording with \($0.name)." } ?? "Recording with the default microphone."
        resetWaveform(animated: false)
        DebugLog.log("startSession showing recording panel device='\(activeDevice?.name ?? "default")'", category: "app")
        windowCoordinator?.showRecordingPanel()

        do {
            audioCaptureService.setLevelObserver { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.pushWaveformSample(Double(level))
                }
            }
            try audioCaptureService.start(device: activeDevice)
            session?.state = .recording
            DebugLog.log("startSession audioCaptureService.start succeeded", category: "app")
            startTimer()
        } catch {
            session?.state = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            audioCaptureService.setLevelObserver(nil)
            DebugLog.log("startSession audioCaptureService.start failed error='\(error.localizedDescription)'", category: "app")
            showNotice(error.localizedDescription, isError: true)
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
        DebugLog.log("checkpoint begin activeSegmentIndex=\(session.activeSegmentIndex)", category: "app")

        do {
            let segment = try audioCaptureService.checkpoint(segmentIndex: session.activeSegmentIndex)
            session.insertCheckpointPlaceholder(for: segment.index)
            self.session = session
            DebugLog.log("checkpoint created placeholder segmentIndex=\(segment.index) file='\(segment.fileURL.path)'", category: "app")
            transcribe(segment)
        } catch {
            session.state = .failed(error.localizedDescription)
            self.session = session
            statusMessage = error.localizedDescription
            showNotice(error.localizedDescription, isError: true)
        }
    }

    private func stopOrReviewSession(deviceDisconnected: Bool) async {
        guard var session else { return }
        guard session.state == .recording || session.state == .preparing else { return }
        DebugLog.log("stopOrReviewSession deviceDisconnected=\(deviceDisconnected) activeSegmentIndex=\(session.activeSegmentIndex) finalizeBehavior='\(settings.finalizeBehavior.rawValue)'", category: "app")

        session.state = settings.finalizeBehavior == .reviewBeforeDelivery ? .review : .finalizing
        self.session = session
        stopTimer()
        resetWaveform(animated: false)

        do {
            if let segment = try audioCaptureService.stop(finalSegmentIndex: session.activeSegmentIndex) {
                session.insertFinalPlaceholder(for: segment.index)
                self.session = session
                DebugLog.log("stopOrReviewSession final segment index=\(segment.index) file='\(segment.fileURL.path)'", category: "app")
                transcribe(segment)
            } else {
                DebugLog.log("stopOrReviewSession no final segment returned", category: "app")
                await completeSessionIfPossible()
            }
            if deviceDisconnected {
                statusMessage = "Input device disappeared. Finalizing current draft."
                showNotice(statusMessage, isError: true)
            }
        } catch {
            session.state = .failed(error.localizedDescription)
            self.session = session
            statusMessage = error.localizedDescription
            showNotice(error.localizedDescription, isError: true)
        }
    }

    private func transcribe(_ segment: TranscriptionSegment) {
        DebugLog.log("transcribe scheduled segmentIndex=\(segment.index) file='\(segment.fileURL.path)'", category: "app")
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
        DebugLog.log("apply result segmentIndex=\(result.segmentIndex) length=\(result.text.count)", category: "app")
        session.markTranscriptReady(result.text, for: result.segmentIndex)
        self.session = session
        statusMessage = "Segment \(result.segmentIndex + 1) transcribed."
        Task { await completeSessionIfPossible() }
    }

    private func apply(error message: String, for segmentIndex: Int) {
        guard var session else { return }
        DebugLog.log("apply error segmentIndex=\(segmentIndex) message='\(message)'", category: "app")
        session.markTranscriptFailed(for: segmentIndex)
        self.session = session
        statusMessage = message
        showNotice("A segment could not be transcribed.", isError: true)
        Task { await completeSessionIfPossible() }
    }

    private func completeSessionIfPossible() async {
        guard let session else { return }
        guard session.state == .finalizing || session.state == .review else { return }
        guard session.pendingTranscriptCount == 0 else { return }

        if session.state == .review {
            self.session = session
            return
        }

        await deliver(session: session)
    }

    private func deliverReviewedSession() async {
        guard let session else { return }
        guard session.state == .review, session.pendingTranscriptCount == 0 else { return }
        await deliver(session: session)
    }

    private func deliver(session existingSession: RecordingSession) async {
        var session = existingSession
        let rawText = session.assembledDraft
        DebugLog.log("deliver begin rawTextLength=\(rawText.count) outputAction='\(settings.outputAction.rawValue)' editorHasFocus=\(editorHasFocus)", category: "app")
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

        let outputAction: OutputAction
        if editorHasFocus && settings.outputAction == .copyAndPaste {
            outputAction = .copy
        } else {
            outputAction = settings.outputAction
        }

        let delivery = outputService.deliver(text: finalText, action: outputAction)
        DebugLog.log("deliver finished copiedMessage='\(delivery.message)' finalTextLength=\(finalText.count)", category: "app")
        session.finalText = finalText
        session.deliveryMessage = delivery.message
        session.state = .completed
        self.session = session
        lastTranscript = finalText
        statusMessage = delivery.message
        showNotice(delivery.message, isError: false)
        windowCoordinator?.hideRecordingPanel()
        self.session = nil
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
                await stopOrReviewSession(deviceDisconnected: true)
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

    private func pushWaveformSample(_ value: Double) {
        waveformSamples.append(max(0, min(1, value)))
        if waveformSamples.count > 24 {
            waveformSamples.removeFirst(waveformSamples.count - 24)
        }
    }

    private func resetWaveform(animated: Bool) {
        _ = animated
        waveformSamples = Array(repeating: 0, count: 24)
    }

    private func showNotice(_ message: String, isError: Bool) {
        noticeTask?.cancel()
        transientNotice = Notice(message: message, isError: isError)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                self?.transientNotice = nil
            }
        }
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
            DebugLog.log("refreshModelStatus begin", category: "app")
            let status = await modelManager.status(configuration: settings.whisperConfiguration)
            await MainActor.run {
                self.installationStatus = status
                Self.logger.notice("Model status refreshed. runtimeExists: \(status.runtimeExists, privacy: .public), modelExists: \(status.modelExists, privacy: .public), runtimeURL: \(status.runtimeURL?.path ?? "-", privacy: .public), modelURL: \(status.modelURL?.path ?? "-", privacy: .public)")
                DebugLog.log("refreshModelStatus runtimeExists=\(status.runtimeExists) modelExists=\(status.modelExists) runtimeURL='\(status.runtimeURL?.path ?? "nil")' modelURL='\(status.modelURL?.path ?? "nil")'", category: "app")
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
