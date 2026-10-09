import Foundation

// MARK: - 緊急解除

public enum EmergencyPolicy {
    /// 申請から解除までの待機(分)。安全の床:変更不可
    public static let waitMinutes = 15
    /// 解除が続く長さ(分)。安全の床:変更不可
    public static let windowMinutes = 120

    /// 申請時刻から窓を作る。開始は「申請+15分」を次の 0 秒に切り上げ(DeviceActivity は分単位のため)。
    public static func makeWindow(requestedAt: Date) -> EmergencyWindow {
        let raw = requestedAt.addingTimeInterval(TimeInterval(waitMinutes * 60))
        let start = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        return EmergencyWindow(requestedAt: requestedAt, startsAt: start,
                               endsAt: start.addingTimeInterval(TimeInterval(windowMinutes * 60)))
    }

    /// 新しく申請できるか(待機中・解除中は重ねて申請できない)
    public static func canRequest(existing: EmergencyWindow?, now: Date) -> Bool {
        guard let e = existing, e.cancelledAt == nil else { return true }
        return now >= e.endsAt
    }
}

// MARK: - 設定変更のルール

/// 設定変更の種類
public enum SettingsChange: Equatable, Sendable {
    case lockTargetsAdded
    case lockTargetsRemoved
    case allowTargetsAdded
    case allowTargetsRemoved
    case lockStartMoved(fromMinute: Int, toMinute: Int, dayStartMinute: Int)
    case modeChanged(from: LockMode, to: LockMode, dayStartMinute: Int)
    case methodChanged(from: VerificationMethod, to: VerificationMethod)
    case habitAdded
    case habitRemoved
    case habitWeekdaysChanged(added: Int, removed: Int)
    case habitTextEdited
    case minimumQuotaChanged(from: Int, to: Int)
    case restQuotaChanged(from: Int, to: Int)
    case enforcementChanged(to: Enforcement)
    case inAppPurchaseBlockChanged(to: Bool)
    case dayStartChanged
    case notificationSettings
}

public enum ChangeDirection: Equatable, Sendable {
    case tighten   // 厳しくする
    case relax     // 緩める
    case neutral   // ロックに関係しない
}

public enum Acceptance: Equatable, Sendable {
    case applyNow
    case applyFromNextCycle
    case requiresRefereeApproval
    case rejected(RejectReason)

    public enum RejectReason: String, Equatable, Sendable {
        case lockedNow       // ロック中(今日が未達成)は緩められない
        case requiresPause   // 一時停止中にだけ変更できる
        case notInFuture     // 休養日は翌サイクル以降にだけ置ける
        case quotaExceeded   // 週の上限を超える
    }
}

public struct ChangeContext: Equatable, Sendable {
    public var canRelaxNow: Bool
    public var hasReferee: Bool
    public var isPaused: Bool

    public init(canRelaxNow: Bool, hasReferee: Bool, isPaused: Bool) {
        self.canRelaxNow = canRelaxNow
        self.hasReferee = hasReferee
        self.isPaused = isPaused
    }
}

public enum ChangePolicy {
    public static func direction(of change: SettingsChange) -> ChangeDirection {
        switch change {
        case .lockTargetsAdded, .allowTargetsRemoved, .habitAdded:
            return .tighten
        case .lockTargetsRemoved, .allowTargetsAdded, .habitRemoved, .habitTextEdited:
            return .relax
        case let .lockStartMoved(from, to, dayStart):
            return compare(offset(to, dayStart), offset(from, dayStart), smallerIs: .tighten)
        case let .modeChanged(from, to, dayStart):
            return modeDirection(from: from, to: to, dayStart: dayStart)
        case let .methodChanged(from, to):
            if from == to { return .neutral }
            return to.strictness > from.strictness ? .tighten : .relax
        case let .habitWeekdaysChanged(added, removed):
            if removed > 0 { return .relax }
            return added > 0 ? .tighten : .neutral
        case let .minimumQuotaChanged(from, to), let .restQuotaChanged(from, to):
            return compare(to, from, smallerIs: .tighten)
        case let .enforcementChanged(to):
            return to == .lock ? .tighten : .relax
        case let .inAppPurchaseBlockChanged(to):
            return to ? .tighten : .relax
        case .dayStartChanged:
            return .relax   // 区切りが動くと記録の意味が変わるため、一時停止中だけ許す
        case .notificationSettings:
            return .neutral
        }
    }

    public static func acceptance(for change: SettingsChange, context: ChangeContext) -> Acceptance {
        if change == .dayStartChanged {
            return context.isPaused ? .applyNow : .rejected(.requiresPause)
        }
        if context.isPaused { return .applyNow }   // 一時停止中はロックがないので自由に直せる(執行役には再開時に通知)

        switch direction(of: change) {
        case .neutral:
            return .applyNow
        case .tighten:
            switch change {
            case .habitAdded, .habitWeekdaysChanged, .modeChanged:
                return .applyFromNextCycle   // 今日の条件は途中で変えない
            default:
                return .applyNow
            }
        case .relax:
            if context.hasReferee { return .requiresRefereeApproval }
            return context.canRelaxNow ? .applyFromNextCycle : .rejected(.lockedNow)
        }
    }

    /// 休養日の追加(週の上限内なら執行役の承認は不要。翌サイクル以降のみ)
    public static func restDayAcceptance(day: CycleID, current: CycleID, canRelaxNow: Bool,
                                         usedInThatWeek: Int, weeklyQuota: Int, isPaused: Bool) -> Acceptance {
        guard day > current else { return .rejected(.notInFuture) }
        guard usedInThatWeek < weeklyQuota else { return .rejected(.quotaExceeded) }
        return (isPaused || canRelaxNow) ? .applyNow : .rejected(.lockedNow)
    }

    /// 最小版で達成してよいか(週の上限)
    public static func canUseMinimum(usedThisWeek: Int, weeklyQuota: Int) -> Bool {
        usedThisWeek < weeklyQuota
    }

    // MARK: private

    private static func offset(_ minute: Int, _ dayStart: Int) -> Int {
        (minute - dayStart + 1440) % 1440
    }

    private static func compare(_ new: Int, _ old: Int, smallerIs: ChangeDirection) -> ChangeDirection {
        if new == old { return .neutral }
        if new < old { return smallerIs }
        return smallerIs == .tighten ? .relax : .tighten
    }

    private static func rank(_ mode: LockMode) -> Int {
        switch mode {
        case .evening: return 0
        case .morning: return 1
        case .earn: return 2
        }
    }

    private static func modeDirection(from: LockMode, to: LockMode, dayStart: Int) -> ChangeDirection {
        switch (from, to) {
        case let (.evening(a), .evening(b)):
            return compare(offset(b, dayStart), offset(a, dayStart), smallerIs: .tighten)
        case let (.earn(a), .earn(b)):
            return compare(b, a, smallerIs: .tighten)
        case (.morning, .morning):
            return .neutral
        default:
            return rank(to) > rank(from) ? .tighten : .relax
        }
    }
}

// MARK: - 時刻改ざんの検知

/// 壁時計と単調時計(スリープ中も進む)の組。本体が起動のたびに記録する。
public struct ClockAnchor: Codable, Equatable, Sendable {
    public var wall: Date
    public var monotonicNanos: UInt64
    public var bootSessionID: String

    public init(wall: Date, monotonicNanos: UInt64, bootSessionID: String) {
        self.wall = wall
        self.monotonicNanos = monotonicNanos
        self.bootSessionID = bootSessionID
    }
}

public enum TamperDetector {
    public static let toleranceSeconds: TimeInterval = 120

    /// 同じ起動セッションの中で、壁時計の進みが単調時計とずれていれば、そのずれ(秒、正=未来へ)を返す。
    /// 再起動をはさむと単調時計がリセットされるので判定しない(nil)。
    public static func clockSkew(from a: ClockAnchor, to b: ClockAnchor) -> TimeInterval? {
        guard a.bootSessionID == b.bootSessionID, b.monotonicNanos >= a.monotonicNanos else { return nil }
        let elapsedMono = TimeInterval(b.monotonicNanos - a.monotonicNanos) / 1_000_000_000
        let skew = b.wall.timeIntervalSince(a.wall) - elapsedMono
        return abs(skew) > toleranceSeconds ? skew : nil
    }
}
