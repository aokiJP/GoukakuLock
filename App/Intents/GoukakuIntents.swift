import AppIntents
import Foundation
import GoukakuCore

/// Siri・ショートカット・Spotlight から使う操作。アプリを開かずに記録できる(自己申告は一言5文字以上のまま)。

struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource { "チェックインする" }
    static var description: IntentDescription {
        IntentDescription("やったことを一言書いて、今日のコミットを記録します。")
    }

    @Parameter(title: "やったこと")
    var note: String

    @Parameter(title: "最小版で記録", default: false)
    var minimum: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = AppModel.shared.quickCheckIn(habitID: nil, minimum: minimum, note: note)
        return .result(dialog: "\(result.title)。\(result.message)")
    }
}

struct TodayStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "今日の状態" }
    static var description: IntentDescription {
        IntentDescription("ロック中か、今日のコミットが済んだかを答えます。")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.reload()
        guard let summary = model.statusSummary() else {
            return .result(dialog: "はじめの設定が済んでいません。")
        }
        let streak = model.stats().streak
        return .result(dialog: "\(summary.sentence)。連続\(streak)日です。")
    }
}

struct OpenCheckInIntent: AppIntent {
    static var title: LocalizedStringResource { "チェックイン画面を開く" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationRouter.shared.openCheckIn = true
        return .result()
    }
}

struct OpenFocusTimerIntent: AppIntent {
    static var title: LocalizedStringResource { "集中タイマーを開く" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationRouter.shared.openTimer = true
        return .result()
    }
}

struct GoukakuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckInIntent(),
                    phrases: ["\(.applicationName)でチェックイン", "\(.applicationName)に記録"],
                    shortTitle: "チェックイン", systemImageName: "checkmark.seal")
        AppShortcut(intent: TodayStatusIntent(),
                    phrases: ["\(.applicationName)の今日の状態", "\(.applicationName)はロック中"],
                    shortTitle: "今日の状態", systemImageName: "lock")
        AppShortcut(intent: OpenFocusTimerIntent(),
                    phrases: ["\(.applicationName)で集中タイマー"],
                    shortTitle: "集中タイマー", systemImageName: "timer")
    }
}
