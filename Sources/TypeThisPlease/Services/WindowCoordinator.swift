import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let appModel: AppModel
    private lazy var draftWindowController = makeDraftWindow()
    private lazy var settingsWindowController = makeSettingsWindow()
    private lazy var hudWindowController = makeHUDWindow()

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func showDraft(activate: Bool = true) {
        show(windowController: draftWindowController, activate: activate)
    }

    func showSettings() {
        show(windowController: settingsWindowController, activate: true)
    }

    func showHUD() {
        show(windowController: hudWindowController, activate: false)
    }

    func hideHUD() {
        hudWindowController.window?.orderOut(nil)
    }

    private func show(windowController: NSWindowController, activate: Bool) {
        windowController.showWindow(nil)
        windowController.window?.center()
        windowController.window?.makeKeyAndOrderFront(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeDraftWindow() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TypeThisPlease Draft"
        window.setContentSize(NSSize(width: 640, height: 720))
        window.contentView = NSHostingView(rootView: DraftWindowView().environmentObject(appModel))
        return NSWindowController(window: window)
    }

    private func makeSettingsWindow() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TypeThisPlease Settings"
        window.setContentSize(NSSize(width: 760, height: 760))
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(appModel))
        return NSWindowController(window: window)
    }

    private func makeHUDWindow() -> NSWindowController {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: RecordingHUDView().environmentObject(appModel))
        return NSWindowController(window: panel)
    }
}
