import SwiftUI

@main
struct TypeThisPleaseApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    private let runtime: AppRuntime

    init() {
        DebugLog.log("App init start.", category: "app")
        self.runtime = AppRuntime.shared
        _ = runtime.statusItemController
        DebugLog.log("App init complete.", category: "app")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
