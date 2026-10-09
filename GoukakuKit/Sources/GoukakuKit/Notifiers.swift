import Foundation
import UserNotifications
import DeviceActivity
import GoukakuCore
import GoukakuShared

/// シールドのボタンから本体アプリへ誘導する通知。
/// シールドから本体アプリを直接開く API はない(ShieldActionResponse は none / close / defer のみ)ため、通知を経由する。
public enum CheckInNotifier {
    public static var routeKey: String { "route" }
    public static var checkInRoute: String { "checkin" }
    /// どのコミットの通知か(userInfo に UUID の文字列で入れる)
    public static var habitKey: String { "habitID" }

    /// 通知から直接チェックインできる種類(長押しで一言を書いて記録)
    public static var categoryID: String { "goukaku.checkin" }
    public static var replyFullAction: String { "checkin.full" }
    public static var replyMinimumAction: String { "checkin.minimum" }

    /// 本体アプリが起動時に登録する(拡張が出す通知も、本体の種類として扱われる)
    public static func registerCategories() {
        let full = UNTextInputNotificationAction(identifier: replyFullAction, title: "一言書いて記録",
                                                 options: [], textInputButtonTitle: "記録",
                                                 textInputPlaceholder: "やったこと(5文字以上)")
        let minimum = UNTextInputNotificationAction(identifier: replyMinimumAction, title: "最小版で記録",
                                                    options: [], textInputButtonTitle: "記録",
                                                    textInputPlaceholder: "やったこと(5文字以上)")
        let category = UNNotificationCategory(identifier: categoryID, actions: [full, minimum],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// 通知を登録し終えるまで(最大2秒)待ってから戻る
    public static func postAndWait() {
        let content = UNMutableNotificationContent()
        content.title = "チェックインしよう"
        content.body = "タップで今日のコミットを開きます。長押しすれば、一言書いてそのまま記録できます。"
        content.userInfo = [routeKey: checkInRoute]
        content.categoryIdentifier = categoryID
        content.sound = .default
        let request = UNNotificationRequest(identifier: "shield-checkin", content: content, trigger: nil)
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 2)
    }
}

/// 使用時間のしきい値イベントを達成として受信箱に置く(DeviceActivityMonitor 拡張から呼ぶ)
public enum UsageRecorder {
    public static func record(event: DeviceActivityEvent.Name, store: SharedStateStore? = AppGroup.store,
                              now: Date = Date()) {
        guard let habitID = event.usageHabitID, let store, let state = try? store.load() else { return }
        if let achievement = AutoAchievement.make(habitID: habitID, state: state,
                                                  existing: store.pendingAchievements(), now: now) {
            _ = try? store.appendInbox(.achievement(achievement), now: now)
            // その日のリマインドは不要になる
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: (0..<6).map { "remind-\(achievement.cycle)-\($0)" })
        } else {
            _ = try? store.appendInbox(.log(LogEntry(at: now, kind: "usageIgnored", detail: event.rawValue)), now: now)
        }
    }
}

/// 緊急解除の開始と終了10分前の通知(申請時に本体が予約する)
public enum EmergencyNotifier {
    public static var identifiers: [String] { ["emergency-start", "emergency-end"] }

    public static func schedule(_ window: EmergencyWindow, calendar: Calendar = .current) {
        let items: [(id: String, at: Date, title: String, body: String)] = [
            ("emergency-start", window.startsAt, "緊急解除が始まりました", "2時間使えます。アプリを開くと確実に反映されます。"),
            ("emergency-end", window.endsAt.addingTimeInterval(-600), "あと10分で再ロック", "まだなら、今日のコミットを済ませよう。"),
        ]
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.userInfo = [CheckInNotifier.routeKey: CheckInNotifier.checkInRoute]
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    public static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// リマインド通知を作り直す(本体アプリが起動・前面に来るたびに呼ぶ)
public enum ReminderScheduler {
    public static func replace(with plan: [PlannedReminder], titles: [CycleID: String],
                               habitIDs: [CycleID: UUID] = [:], calendar: Calendar = .current) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            // @Sendable クロージャの中で取り直す(外の center を捕まえると Swift 6 でエラーになる)
            let center = UNUserNotificationCenter.current()
            let old = pending.map(\.identifier).filter { $0.hasPrefix("remind-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for reminder in plan {
                let content = UNMutableNotificationContent()
                let title = titles[reminder.cycle] ?? "今日のコミット"
                switch reminder.kind {
                case .regular:
                    content.title = "「\(title)」はまだです"
                    content.body = "終わると、お金を使うアプリのロックが外れます。"
                case .escalation:
                    content.title = "昨日は未達成でした"
                    content.body = "今日は最小版でもOK。小さく続けよう。"
                }
                var info: [String: String] = [CheckInNotifier.routeKey: CheckInNotifier.checkInRoute]
                if let habitID = habitIDs[reminder.cycle] { info[CheckInNotifier.habitKey] = habitID.uuidString }
                content.userInfo = info
                content.categoryIdentifier = CheckInNotifier.categoryID   // 長押しで一言書いて記録できる
                content.sound = .default
                content.badge = 1   // 未達成あり。本体を開いたら実数に直し、達成したら消す(setBadgeCount)
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            }
        }
    }

    public static func cancel(cycle: CycleID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (0..<6).map { "remind-\(cycle)-\($0)" })
    }
}
