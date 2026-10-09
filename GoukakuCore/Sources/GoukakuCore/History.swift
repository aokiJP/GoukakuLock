import Foundation

/// サイクルの結果(履歴・ストリーク・帳簿の元)
public enum CycleOutcome: String, Codable, Sendable {
    case notStarted     // 利用開始前
    case rest           // 休養日
    case noCommit       // 予定された必須コミットがない
    case achieved       // 達成
    case minimum        // 最小版で達成
    case pendingReview  // 達成(執行役の事後承認待ち)
    case paused         // 一時停止(達成していない)
    case inProgress     // まだ終わっていない
    case missed         // 未達成
}

public enum History {
    /// サイクルの結果を判定する。終わったサイクルの結果は、本体がこれで確定させて SwiftData に保存する。
    public static func outcome(of cycle: CycleID,
                               state: SharedState,
                               extra: [Achievement] = [],
                               now: Date,
                               timeZone: TimeZone = .current) -> CycleOutcome {
        let facts = Facts(state, extra: extra, timeZone: timeZone)
        if cycle < state.activeSince { return .notStarted }
        if state.restDays.contains(cycle) { return .rest }
        let required = facts.requiredHabits(cycle)
        if required.isEmpty { return .noCommit }
        if facts.isSatisfied(cycle) {
            let requiredIDs = Set(required.map(\.id))
            let counted = facts.counted(cycle).filter { requiredIDs.contains($0.habitID) }
            if counted.contains(where: { $0.status == .pendingReview }) { return .pendingReview }
            let allFull = required.allSatisfy { habit in
                counted.contains { $0.habitID == habit.id && $0.kind == .full }
            }
            return allFull ? .achieved : .minimum
        }
        if facts.wasPaused(during: cycle) { return .paused }
        if now < facts.cal.end(of: cycle) { return .inProgress }
        return .missed
    }

    /// 新しい順に並べた結果から、いまのストリーク(連続達成日数)を数える。
    /// 休養日・予定なし・進行中の日は数えず途切れさせもしない。未達成・一時停止・開始前で止まる。
    public static func currentStreak(newestFirst outcomes: [CycleOutcome]) -> Int {
        var count = 0
        for outcome in outcomes {
            switch outcome {
            case .achieved, .minimum, .pendingReview:
                count += 1
            case .rest, .noCommit, .inProgress:
                continue
            case .paused, .missed, .notStarted:
                return count
            }
        }
        return count
    }

    /// 通算達成日数(途切れても減らない)
    public static func totalAchieved(_ outcomes: [CycleOutcome]) -> Int {
        outcomes.filter { $0 == .achieved || $0 == .minimum || $0 == .pendingReview }.count
    }
}
