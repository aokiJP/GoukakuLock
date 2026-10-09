import Foundation
import Observation
import UserNotifications
import GoukakuKit

/// 下のタブ
enum MainTab: Hashable {
    case today, experience, history, settings
}

/// どの画面を開くか(通知・ウィジェット・コントロールセンター・Siri から)
@MainActor @Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    var openCheckIn = false
    var openEmergency = false
    var openTimer = false
    /// いま開いているタブ(ホームのカードから「体験」へ移るときなどに使う)
    var tab: MainTab = .today

    /// goukakulock://checkin などを開く
    func handle(url: URL) {
        switch DeepLink.route(of: url) {
        case .checkin?: openCheckIn = true
        case .emergency?: openEmergency = true
        case .timer?: openTimer = true
        case .home?, nil: break
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        // アクターをまたぐ前に、必要な値だけを取り出しておく
        let info = response.notification.request.content.userInfo
        let route = info[CheckInNotifier.routeKey] as? String
        let habitID = (info[CheckInNotifier.habitKey] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            self.respond(action: action, text: text, habitID: habitID, route: route)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func respond(action: String, text: String?, habitID: UUID?, route: String?) {
        switch action {
        case CheckInNotifier.replyFullAction, CheckInNotifier.replyMinimumAction:
            // 通知に書いた一言で、アプリを開かずに記録する
            let model = AppModel.shared
            let result = model.quickCheckIn(habitID: habitID, minimum: action == CheckInNotifier.replyMinimumAction,
                                            note: text ?? "")
            Self.postResult(result)
        default:
            if route == CheckInNotifier.checkInRoute { openCheckIn = true }
        }
    }

    /// 通知から記録した結果を、通知で返す(失敗なら、もう一度書けるよう同じ種類で)
    static func postResult(_ result: QuickCheckInResult) {
        let content = UNMutableNotificationContent()
        content.title = result.title
        content.body = result.message
        if !result.ok {
            content.categoryIdentifier = CheckInNotifier.categoryID
            content.userInfo = [CheckInNotifier.routeKey: CheckInNotifier.checkInRoute]
        }
        let request = UNNotificationRequest(identifier: "quick-checkin-result", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
