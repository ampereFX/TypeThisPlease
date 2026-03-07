import Foundation

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let appModel: AppModel
    let windowCoordinator: WindowCoordinator
    let statusItemController: StatusItemController

    private init() {
        DebugLog.log("AppRuntime init start.", category: "runtime")
        let appModel = AppModel()
        let windowCoordinator = WindowCoordinator(appModel: appModel)
        let statusItemController = StatusItemController(appModel: appModel)
        appModel.attach(windowCoordinator: windowCoordinator)

        self.appModel = appModel
        self.windowCoordinator = windowCoordinator
        self.statusItemController = statusItemController

        DispatchQueue.main.async {
            DebugLog.log("AppRuntime triggering bootstrap.", category: "runtime")
            appModel.bootstrap()
        }
        DebugLog.log("AppRuntime init complete.", category: "runtime")
    }
}
