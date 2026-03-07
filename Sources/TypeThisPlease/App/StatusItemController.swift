import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appModel: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(appModel: AppModel) {
        self.appModel = appModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        DebugLog.log("StatusItemController init", category: "status")
        configureStatusItem()
        configureMenu()
    }

    deinit {
        DebugLog.log("StatusItemController deinit", category: "status")
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "TypeThisPlease")
        button.imagePosition = .imageLeading
        button.title = ""
        button.toolTip = "TypeThisPlease"
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func rebuildMenu() {
        DebugLog.log(
            "rebuildMenu headline='\(appModel.menuHeadline)' primary='\(appModel.primaryMenuButtonTitle)' canCheckpoint=\(appModel.canTriggerCheckpoint) sessionNil=\(appModel.session == nil)",
            category: "status"
        )

        menu.removeAllItems()

        let titleItem = NSMenuItem(title: "TypeThisPlease", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let headlineItem = NSMenuItem(title: appModel.menuHeadline, action: nil, keyEquivalent: "")
        headlineItem.isEnabled = false
        menu.addItem(headlineItem)

        menu.addItem(.separator())

        let primaryItem = NSMenuItem(title: appModel.primaryMenuButtonTitle, action: #selector(handlePrimaryAction), keyEquivalent: "")
        primaryItem.target = self
        menu.addItem(primaryItem)

        let checkpointItem = NSMenuItem(title: "Checkpoint", action: #selector(handleCheckpointAction), keyEquivalent: "")
        checkpointItem.target = self
        checkpointItem.isEnabled = appModel.canTriggerCheckpoint
        menu.addItem(checkpointItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(handleSettingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let recordingHotKeyItem = NSMenuItem(title: "Recording: \(appModel.recordingHotKeyDisplayString)", action: nil, keyEquivalent: "")
        recordingHotKeyItem.isEnabled = false
        menu.addItem(recordingHotKeyItem)

        let checkpointHotKeyItem = NSMenuItem(title: "Checkpoint: \(appModel.checkpointHotKeyDisplayString)", action: nil, keyEquivalent: "")
        checkpointHotKeyItem.isEnabled = false
        menu.addItem(checkpointHotKeyItem)

        let status = appModel.statusMessage.isEmpty ? "No recent status." : appModel.statusMessage
        let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
    }

    @objc
    private func handlePrimaryAction() {
        DebugLog.log(
            "Primary menu action selected. backendReady=\(appModel.hasTranscriptionBackendReady) sessionNil=\(appModel.session == nil)",
            category: "status"
        )
        if appModel.session == nil && !appModel.hasTranscriptionBackendReady {
            appModel.openSettingsWindow()
        } else {
            appModel.toggleRecording()
        }
    }

    @objc
    private func handleCheckpointAction() {
        DebugLog.log("Checkpoint menu action selected", category: "status")
        appModel.createCheckpoint()
    }

    @objc
    private func handleSettingsAction() {
        DebugLog.log("Settings menu action selected", category: "status")
        appModel.openSettingsWindow()
    }
}
