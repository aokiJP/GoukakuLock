import Foundation
import ManagedSettings
import GoukakuKit

/// シールドのボタン処理。本体アプリを直接は開けないので、通知で誘導する。
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            // まず判定し直す(使用時間の自動判定などで、すでに達成済みならここでロックが外れる)
            if Reconciler.run(source: "shield", logToInbox: true)?.shouldLock == false {
                return .none   // シールドの設定は外れている。何もしなければ元のアプリに戻れる
            }
            CheckInNotifier.postAndWait()   // 「タップしてチェックイン」の通知を出してから閉じる
            return .close
        case .secondaryButtonPressed:
            return .close
        @unknown default:
            return .close
        }
    }
}
