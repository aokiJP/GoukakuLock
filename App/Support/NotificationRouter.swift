import Foundation
import Observation
import UserNotifications
import GoukakuKit

/// 通知からチェックイン画面へ(シールドのボタン・リマインド・緊急解除の通知はどれも route=checkin を持つ)
@MainActor @Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var openCheckIn = false

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo[CheckInNotifier.routeKey] as? String
        if route == CheckInNotifier.checkInRoute {
            await MainActor.run { self.openCheckIn = true }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
