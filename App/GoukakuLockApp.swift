import SwiftUI
import SwiftData
import UserNotifications

@main
struct GoukakuLockApp: App {
    @State private var model: AppModel
    @State private var router: NotificationRouter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel(container: Persistence.makeContainer())
        let router = NotificationRouter()
        UNUserNotificationCenter.current().delegate = router
        _model = State(initialValue: model)
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .modelContainer(model.container)
                .tint(Theme.seal)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await model.onLaunchOrForeground() }
        }
        .backgroundTask(.appRefresh(AppConstants.refreshTaskID)) { [model] in
            await model.onLaunchOrForeground()   // 第16.4節の 1〜8 と同じ
            scheduleNextRefresh()
        }
    }
}
