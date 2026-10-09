import Foundation

/// 預け金の1日(サーバーと同じ形:サイクルの日付と、始まり・終わりの時刻)
public struct DepositDay: Codable, Equatable, Sendable {
    public var key: String
    public var startsAt: Date
    public var endsAt: Date

    public init(key: String, startsAt: Date, endsAt: Date) {
        self.key = key
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    public var cycle: CycleID? { CycleID(key) }
}

/// 預け金の1日の見え方
public enum DepositDayMark: String, Codable, Sendable {
    /// 返金した
    case returned
    /// 達成したので、返金を待っている(日付が変わるか、取り消しの時間が過ぎたら手続きする)
    case returning
    /// 未達成・一時停止で、戻らない
    case kept
    /// 今日(まだ決まっていない)
    case today
    /// これからの日
    case upcoming
}

/// 預け金(先に7日分を預けて、達成した日の分が返ってくる)の決まりごと。
/// お金を動かすのはサーバーと Stripe で、その日を返金してよいかの判定はここ(アプリの判定と同じ結果を使う)
public enum DepositRules {
    /// 1回に預ける日数
    public static let days = 7
    /// チェックインを取り消せる時間(これが過ぎた達成は、日付が変わる前でも返金してよい)
    public static let undoWindow: TimeInterval = 5 * 60

    /// 返金する結果か。達成・最小版・休養日・予定のない日は返す。未達成と一時停止は返さない。
    /// 事後承認待ちは、却下されると未達成に戻るので、承認されて達成になるまで返さない(サーバーも同じ)
    public static func isRefundable(_ outcome: CycleOutcome) -> Bool {
        switch outcome {
        case .achieved, .minimum, .rest, .noCommit, .notStarted:
            return true
        case .paused, .missed, .inProgress, .pendingReview:
            return false
        }
    }

    /// 結果が決まり、サーバーに知らせてよいか。
    /// 日付が変わったら決まり。達成(最小版も)は、最後のチェックインから取り消しの時間が過ぎたら決まり
    public static func isFinal(outcome: CycleOutcome, cycleEnd: Date, lastCheckIn: Date?, now: Date) -> Bool {
        if now >= cycleEnd { return outcome != .inProgress }
        switch outcome {
        case .achieved, .minimum:
            guard let lastCheckIn else { return false }
            return now.timeIntervalSince(lastCheckIn) >= undoWindow
        default:
            return false
        }
    }

    /// 返金をサーバーに頼むか(返金できる結果で、結果が決まっていて、まだ返していない)
    public static func shouldReport(outcome: CycleOutcome, cycleEnd: Date, lastCheckIn: Date?,
                                    alreadyRefunded: Bool, now: Date) -> Bool {
        !alreadyRefunded && isRefundable(outcome)
            && isFinal(outcome: outcome, cycleEnd: cycleEnd, lastCheckIn: lastCheckIn, now: now)
    }

    /// first から 7 日分(サイクルの日付と、始まり・終わり)
    public static func plan(startingAt first: CycleID, calendar: CycleCalendar) -> [DepositDay] {
        (0..<days).map { i in
            let cycle = calendar.cycle(first, offsetBy: i)
            return DepositDay(key: cycle.description, startsAt: calendar.start(of: cycle), endsAt: calendar.end(of: cycle))
        }
    }

    /// 1日の見え方
    public static func mark(startsAt: Date, endsAt: Date, refunded: Bool, outcome: CycleOutcome?, now: Date) -> DepositDayMark {
        if refunded { return .returned }
        if now < startsAt { return .upcoming }
        guard let outcome else { return now < endsAt ? .today : .kept }
        if isRefundable(outcome), outcome != .inProgress {
            // 今日でも、達成していれば「返ってくる」
            return .returning
        }
        if now < endsAt { return .today }
        return outcome == .inProgress ? .today : .kept
    }
}

/// 1週の預け金の内わけ(画面に出す額)
public struct DepositBreakdown: Equatable, Sendable {
    /// 返金した額
    public var returned = 0
    /// 返金を待っている額(達成ずみ)
    public var returning = 0
    /// 戻らない額
    public var kept = 0
    /// まだ決まっていない額(今日とこれから)
    public var open = 0

    public init(returned: Int = 0, returning: Int = 0, kept: Int = 0, open: Int = 0) {
        self.returned = returned
        self.returning = returning
        self.kept = kept
        self.open = open
    }

    public static func make(marks: [DepositDayMark], daily: Int, refundedAmounts: [Int]? = nil) -> DepositBreakdown {
        var b = DepositBreakdown()
        for (i, mark) in marks.enumerated() {
            switch mark {
            case .returned: b.returned += refundedAmounts?[i] ?? daily
            case .returning: b.returning += daily
            case .kept: b.kept += daily
            case .today, .upcoming: b.open += daily
            }
        }
        return b
    }
}
