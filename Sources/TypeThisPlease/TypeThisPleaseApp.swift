import SwiftUI

@main
struct TypeThisPleaseApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    private let windowCoordinator: WindowCoordinator

    init() {
        let appModel = AppModel()
        let windowCoordinator = WindowCoordinator(appModel: appModel)
        appModel.attach(windowCoordinator: windowCoordinator)
        _appModel = StateObject(wrappedValue: appModel)
        self.windowCoordinator = windowCoordinator
    }

    var body: some Scene {
        MenuBarExtra("TypeThisPlease", systemImage: appModel.isRecordingActive ? "waveform.circle.fill" : "waveform.circle") {
            MenuBarMenuView()
                .environmentObject(appModel)
                .onAppear {
                    appModel.bootstrap()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
