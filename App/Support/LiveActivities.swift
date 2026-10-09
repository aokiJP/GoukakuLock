import Foundation
import ActivityKit
import GoukakuShared

/// Live Activity / Dynamic Island(仕様書 第9.3節)。
/// 自前のサーバーなしで使えるのは「本体の操作から始まる短い場面」だけなので、緊急解除・集中タイマー・稼働型の解除枠に限る。
/// ActivityKit の呼び出しは、アクターをまたがないよう nonisolated な関数の中で完結させる。
enum LiveActivities {
    typealias State = GoukakuActivityAttributes.ContentState

    /// 表示を始める(同じ種類があれば中身を差し替える)
    static func show(_ state: State) {
        Task.detached(priority: .userInitiated) { await upsert(state) }
    }

    static func end(_ kind: State.Kind) {
        Task.detached(priority: .userInitiated) { await endAll(kind) }
    }

    static func upsert(_ state: State) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: state.endsAt.addingTimeInterval(60))
        if let existing = Activity<GoukakuActivityAttributes>.activities.first(where: { $0.content.state.kind == state.kind }) {
            await existing.update(content)
        } else {
            _ = try? Activity<GoukakuActivityAttributes>.request(
                attributes: GoukakuActivityAttributes(name: state.title), content: content, pushType: nil)
        }
    }

    static func endAll(_ kind: State.Kind) async {
        for activity in Activity<GoukakuActivityAttributes>.activities where activity.content.state.kind == kind {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 起動・前面復帰のたびに、終わった場面の表示を片づける
    static func endExpired(now: Date, emergencyActive: Bool, earnActive: Bool) async {
        for activity in Activity<GoukakuActivityAttributes>.activities {
            let state = activity.content.state
            let expired: Bool
            switch state.kind {
            case .emergency: expired = !emergencyActive || state.endsAt <= now
            case .earn: expired = !earnActive || state.endsAt <= now
            case .focus: expired = false   // 集中タイマーはタイマーの画面が片づける
            }
            if expired { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
