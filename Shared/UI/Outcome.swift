import SwiftUI
import GoukakuCore

/// サイクルの結果の呼び名と、採点の記号
extension CycleOutcome {
    var label: String {
        switch self {
        case .notStarted: return "開始前"
        case .rest: return "休養日"
        case .noCommit: return "予定なし"
        case .achieved: return "達成"
        case .minimum: return "最小版で達成"
        case .pendingReview: return "達成(承認待ち)"
        case .paused: return "一時停止"
        case .inProgress: return "進行中"
        case .missed: return "未達成"
        }
    }

    var mark: OutcomeMark {
        switch self {
        case .achieved, .pendingReview: return .maru
        case .minimum: return .sankaku
        case .missed: return .batsu
        case .rest: return .rest
        case .paused: return .paused
        case .noCommit: return .none
        case .inProgress: return .pending
        case .notStarted: return .blank
        }
    }
}
