import Foundation

/// ウィジェット拡張の中では何もしない(画面を開くのは、本体で OpenGoukakuScreenIntent が実行されたとき)
enum ScreenRouting {
    @MainActor
    static func open(_ screen: GoukakuScreen) {}
}
