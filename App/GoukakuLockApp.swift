import SwiftUI
import SwiftData
import UserNotifications
import GoukakuKit

@main
struct GoukakuLockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var router: NotificationRouter
    @State private var runtime: AIRuntime
    @State private var companion: CompanionModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 通知・Siri・バックグラウンド更新でも同じものを使うので、共有のインスタンスにする
        let model = AppModel.shared
        let router = NotificationRouter.shared
        UNUserNotificationCenter.current().delegate = router
        CheckInNotifier.registerCategories()   // 通知を長押しして、一言書いて記録できるように
        _model = State(initialValue: model)
        _router = State(initialValue: router)
        // 相棒AI:端末の様子を調べて、使うAIを決める(モデルの読み込みは使うときに)
        _runtime = State(initialValue: AIRuntime.shared)
        _companion = State(initialValue: CompanionModel.shared)
        ModelStore.ensureInbox()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .environment(runtime)
                .environment(companion)
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
