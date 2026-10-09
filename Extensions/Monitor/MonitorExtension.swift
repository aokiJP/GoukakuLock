import Foundation
import DeviceActivity
import GoukakuKit

/// DeviceActivityMonitor 拡張(本体が起動していなくても、区間の始まり・終わり・しきい値でシステムが呼ぶ)。
/// メモリ上限は 6MB。SwiftData・SwiftUI・大きな依存は読み込まない。すべての合図で同じ Reconciler を呼ぶだけ。
final class MonitorExtension: DeviceActivityMonitor {
    /// 境目の合図は、少し先の時刻で判定する(合図がわずかに早く届いても、境目の向こう側の結論を適用する)
    private var boundaryNow: Date { Date().addingTimeInterval(Reconciler.callbackLeadSeconds) }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        Reconciler.run(now: boundaryNow, source: "start:\(activity.rawValue)", logToInbox: true)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        Reconciler.run(now: boundaryNow, source: "end:\(activity.rawValue)", logToInbox: true)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        UsageRecorder.record(event: event)   // 使用時間の自動判定(誤発火はコアでふるい落とす)
        Reconciler.run(source: "event:\(event.rawValue)", logToInbox: true)
    }
}
