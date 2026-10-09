import Foundation

/// OpenGoukakuScreenIntent が本体で実行されたときの行き先
enum ScreenRouting {
    @MainActor
    static func open(_ screen: GoukakuScreen) {
        let router = NotificationRouter.shared
        switch screen {
        case .checkIn: router.openCheckIn = true
        case .focusTimer: router.openTimer = true
        case .emergency: router.openEmergency = true
        }
    }
}
