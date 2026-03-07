import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let appModel: AppModel
    private weak var recordingWindow: NSWindow?
    private lazy var recordingPanelController = makeRecordingPanel()
    private lazy var settingsWindowController = makeSettingsWindow()
    private lazy var onboardingWindowController = makeOnboardingWindow()

    init(appModel: AppModel) {
        self.appModel = appModel
        DebugLog.log("WindowCoordinator init.", category: "window")
    }

    func showRecordingPanel(activate: Bool = true) {
        DebugLog.log("showRecordingPanel activate=\(activate)", category: "window")
        DebugLog.log("showRecordingPanel before lazy controller resolve", category: "window")
        let controller = recordingPanelController
        DebugLog.log("showRecordingPanel after lazy controller resolve", category: "window")
        DebugLog.log("showRecordingPanel controller.window nil=\(controller.window == nil)", category: "window")
        show(windowController: controller, activate: activate)
        DebugLog.log("showRecordingPanel after show(windowController:)", category: "window")
    }

    func hideRecordingPanel() {
        DebugLog.log("hideRecordingPanel", category: "window")
        recordingWindow?.orderOut(nil)
    }

    func showSettings() {
        DebugLog.log("showSettings", category: "window")
        show(windowController: settingsWindowController, activate: true)
    }

    func showOnboarding() {
        DebugLog.log("showOnboarding", category: "window")
        show(windowController: onboardingWindowController, activate: true)
    }

    func hideOnboarding() {
        DebugLog.log("hideOnboarding", category: "window")
        onboardingWindowController.window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        DebugLog.log("windowDidMove", category: "window")
        guard let window = notification.object as? NSWindow, window === recordingWindow else { return }
        persistRecordingPanelFrame(window: window)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        DebugLog.log("windowDidEndLiveResize", category: "window")
        guard let window = notification.object as? NSWindow, window === recordingWindow else { return }
        persistRecordingPanelFrame(window: window)
    }

    private func show(windowController: NSWindowController, activate: Bool) {
        DebugLog.log("show window controller=\(String(describing: type(of: windowController))) activate=\(activate)", category: "window")
        windowController.showWindow(nil)
        DebugLog.log("showWindow returned. window nil=\(windowController.window == nil)", category: "window")
        guard let window = windowController.window else {
            DebugLog.log("show aborted: windowController.window is nil", category: "window")
            return
        }
        if window === recordingWindow {
            window.delegate = self
        }

        DebugLog.log(
            "window state before front isVisible=\(window.isVisible) isKey=\(window.isKeyWindow) frame=\(NSStringFromRect(window.frame)) screen='\(window.screen?.localizedName ?? "nil")'",
            category: "window"
        )

        if window.frame.isEmpty {
            DebugLog.log("window frame empty -> center()", category: "window")
            window.center()
        }
        if let panel = window as? NSPanel {
            DebugLog.log("orderFrontRegardless panel level=\(panel.level.rawValue) floating=\(panel.isFloatingPanel)", category: "window")
            panel.orderFrontRegardless()
        }
        window.makeKeyAndOrderFront(nil)
        DebugLog.log("makeKeyAndOrderFront done", category: "window")
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            DebugLog.log("NSApp.activate done", category: "window")
        }

        if !window.isVisible {
            DebugLog.log("window still not visible after show; forcing centered fallback", category: "window")
            window.setFrame(centerRect(window.frame.isEmpty ? NSRect(x: 0, y: 0, width: 640, height: 420) : window.frame), display: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            if activate {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        DebugLog.log(
            "window state after front isVisible=\(window.isVisible) isKey=\(window.isKeyWindow) frame=\(NSStringFromRect(window.frame)) occlusion=\(window.occlusionState.rawValue)",
            category: "window"
        )
    }

    private func makeRecordingPanel() -> NSWindowController {
        DebugLog.log("makeRecordingPanel frame=\(NSStringFromRect(resolvedRecordingPanelFrame()))", category: "window")
        let panel = KeyPanel(
            contentRect: resolvedRecordingPanelFrame(),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "TypeThisPlease Draft"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: 460, height: 380)
        recordingWindow = panel

        let rootView = DraftWindowView().environmentObject(appModel)
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
        let controller = NSWindowController(window: panel)
        DebugLog.log("makeRecordingPanel complete", category: "window")
        return controller
    }

    private func makeSettingsWindow() -> NSWindowController {
        DebugLog.log("makeSettingsWindow", category: "window")
        let window = DismissOnEscapeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TypeThisPlease Settings"
        window.setContentSize(NSSize(width: 760, height: 760))
        window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(appModel))
        return NSWindowController(window: window)
    }

    private func makeOnboardingWindow() -> NSWindowController {
        DebugLog.log("makeOnboardingWindow", category: "window")
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "TypeThisPlease Setup"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(rootView: OnboardingView().environmentObject(appModel))
        return NSWindowController(window: panel)
    }

    private func persistRecordingPanelFrame(window: NSWindow) {
        DebugLog.log("persistRecordingPanelFrame frame=\(NSStringFromRect(window.frame))", category: "window")
        appModel.updateFloatingPanelFrame(window.frame)
    }

    private func resolvedRecordingPanelFrame() -> NSRect {
        let defaultFrame = NSRect(x: 0, y: 0, width: 640, height: 420)
        guard let frame = appModel.settings.floatingPanelFrame else {
            return centerRect(defaultFrame)
        }

        let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        let visibleScreens = NSScreen.screens.map(\.visibleFrame)
        guard visibleScreens.contains(where: { $0.intersects(rect) }) else {
            DebugLog.log("Saved panel frame no longer visible; falling back to centered default.", category: "window")
            return centerRect(defaultFrame)
        }
        DebugLog.log("Restoring saved panel frame=\(NSStringFromRect(rect))", category: "window")
        return rect
    }

    private func centerRect(_ rect: NSRect) -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return rect }
        return NSRect(
            x: screen.visibleFrame.midX - rect.width / 2,
            y: screen.visibleFrame.midY - rect.height / 2,
            width: rect.width,
            height: rect.height
        )
    }
}

private final class DismissOnEscapeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

