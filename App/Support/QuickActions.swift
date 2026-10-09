import UIKit

/// ホーム画面でアイコンを長押しすると出る「クイックアクション」(Info.plist の UIApplicationShortcutItems)
enum QuickAction: String {
    case checkIn = "com.aokijp.goukakulock.quick.checkin"
    case focusTimer = "com.aokijp.goukakulock.quick.timer"

    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(rawValue: item.type) else { return false }
        switch action {
        case .checkIn: ScreenRouting.open(.checkIn)
        case .focusTimer: ScreenRouting.open(.focusTimer)
        }
        return true
    }
}

/// クイックアクションを受け取るためだけの AppDelegate。画面は SwiftUI の WindowGroup がそのまま作る。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // アプリが閉じていたとき:起動のきっかけになったクイックアクション
        if let item = options.shortcutItem {
            _ = QuickAction.handle(item)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

/// アプリが開いていたとき(バックグラウンドにいたとき)のクイックアクション
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        QuickAction.handle(shortcutItem)
    }
}
