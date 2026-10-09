import Foundation

/// ロック判定の結果
public struct LockDecision: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        // ロックする理由
        case awaitingCommit                 // 今日の必須コミットが未達成
        case carryOver                      // 夕方型で、前のサイクルが未達成だった(猶予なし)
        case earnWindowExpired              // 稼働型で、解除枠が切れた
        // ロックしない理由
        case achieved                       // 今日の必須コミットをすべて達成
        case earnWindowActive(until: Date)  // 稼働型の解除枠の中
        case emergency(until: Date)         // 緊急解除中
        case paused                         // 一時停止中
        case monitorOnly                    // 見守りモード(記録だけ)
        case restDay                        // 休養日
        case noCommitToday                  // 今日は予定された必須コミットがない
        case beforeLockStart(lockAt: Date)  // 夕方型のロック開始前
        case notStarted                     // 利用開始日より前
    }

    public var shouldLock: Bool
    public var reason: Reason
    public var cycle: CycleID
    /// 今日の必須コミットがすべて達成済みか(緩める変更を受け付けてよいかの判断に使う)
    public var todaySatisfied: Bool
    /// 緊急解除の待機中なら、解除が始まる時刻
    public var emergencyStartsAt: Date?
    /// 判定が変わりうる次の時刻(ウィジェットのタイムライン・本体のタイマーに使う)
    public var nextCheck: Date?

    /// 「緩める変更」を今受け付けてよいか
    public var canRelaxNow: Bool {
        if todaySatisfied { return true }
        switch reason {
        case .restDay, .noCommitToday, .monitorOnly, .paused: return true
        default: return false
        }
    }
}

/// エンジンが共有状態から事実を引き出すための補助。
struct Facts {
    let state: SharedState
    let cal: CycleCalendar
    let achievements: [Achievement]

    init(_ state: SharedState, extra: [Achievement], timeZone: TimeZone) {
        self.state = state
        self.cal = CycleCalendar(dayStartMinute: state.schedule.dayStartMinute, timeZone: timeZone)
        // 拡張が受信箱に書いた達成(extra)を足す。同じ id は本体の state.json 側を優先(却下などの更新を尊重)。
        let known = Set(state.achievements.map(\.id))
        self.achievements = state.achievements + extra.filter { !known.contains($0.id) }
    }

    func requiredHabits(_ cycle: CycleID) -> [HabitSnapshot] {
        let weekday = cal.weekday(of: cycle)
        return state.habits.filter { $0.isRequired && $0.isScheduled(on: cycle, weekday: weekday) }
    }

    func counted(_ cycle: CycleID) -> [Achievement] {
        achievements.filter { $0.cycle == cycle && $0.status.counts }
    }

    /// 必須コミットがすべて達成済みか。必須が1つもない日は false(呼び出し側で別扱い)。
    func isSatisfied(_ cycle: CycleID) -> Bool {
        let required = requiredHabits(cycle)
        guard !required.isEmpty else { return false }
        let done = Set(counted(cycle).map(\.habitID))
        return required.allSatisfy { done.contains($0.id) }
    }

    func pause(at date: Date) -> PausePeriod? {
        state.pauses.first { $0.contains(date) }
    }

    func wasPaused(during cycle: CycleID) -> Bool {
        let from = cal.start(of: cycle), to = cal.end(of: cycle)
        return state.pauses.contains { $0.overlaps(from, to) }
    }

    /// 終わったサイクルが「未達成」だったか(休み・予定なし・一時停止・開始前は未達成ではない)
    func isMissed(_ cycle: CycleID, now: Date) -> Bool {
        guard cycle >= state.activeSince, now >= cal.end(of: cycle) else { return false }
        guard !state.restDays.contains(cycle), !requiredHabits(cycle).isEmpty else { return false }
        return !isSatisfied(cycle) && !wasPaused(during: cycle)
    }

    /// 稼働型:いま有効な解除枠の終わり(複数あれば最も遅いもの)
    func activeEarnWindowEnd(at now: Date) -> Date? {
        achievements.compactMap { a -> Date? in
            guard a.status.counts, let minutes = a.grantsMinutes else { return nil }
            let end = a.at.addingTimeInterval(TimeInterval(minutes * 60))
            return (a.at <= now && now < end) ? end : nil
        }.max()
    }
}

/// ロック判定の芯。純粋関数で、同じ入力には必ず同じ答えを返す。
/// 本体・DeviceActivityMonitor 拡張・Shield 拡張・ウィジェットのどこから呼んでも同じ結論になる。
public enum LockEngine {
    public static func evaluate(_ state: SharedState,
                                extra: [Achievement] = [],
                                now: Date,
                                timeZone: TimeZone = .current) -> LockDecision {
        let facts = Facts(state, extra: extra, timeZone: timeZone)
        let cal = facts.cal
        let cycle = cal.cycle(containing: now)
        let satisfied = facts.isSatisfied(cycle)

        var checkpoints: [Date] = [cal.end(of: cycle)]
        var emergencyStartsAt: Date?
        if let e = state.emergency, e.isPending(at: now) {
            emergencyStartsAt = e.startsAt
            checkpoints.append(e.startsAt)
        }

        func decide(_ lock: Bool, _ reason: LockDecision.Reason, _ extraCheck: Date? = nil) -> LockDecision {
            if let extraCheck { checkpoints.append(extraCheck) }
            return LockDecision(shouldLock: lock, reason: reason, cycle: cycle,
                                todaySatisfied: satisfied, emergencyStartsAt: emergencyStartsAt,
                                nextCheck: checkpoints.filter { $0 > now }.min())
        }

        // 1. 一時停止(全体の非常口)は何より優先
        if let p = facts.pause(at: now) { return decide(false, .paused, p.end) }
        // 2. 見守りモードはロックしない
        if state.enforcement == .monitorOnly { return decide(false, .monitorOnly) }
        // 3. 開始前
        if cycle < state.activeSince { return decide(false, .notStarted, cal.start(of: state.activeSince)) }
        // 4. 緊急解除中
        if let e = state.emergency, e.isActive(at: now) { return decide(false, .emergency(until: e.endsAt), e.endsAt) }
        // 5. 休養日・予定なし
        if state.restDays.contains(cycle) { return decide(false, .restDay) }
        if facts.requiredHabits(cycle).isEmpty { return decide(false, .noCommitToday) }

        // 6. モード別
        switch state.schedule.mode {
        case .morning:
            return satisfied ? decide(false, .achieved) : decide(true, .awaitingCommit)

        case .evening(let lockStartMinute):
            if satisfied { return decide(false, .achieved) }
            let previous = cal.cycle(cycle, offsetBy: -1)
            let carryOverEligible = state.enforcement == .lock
                && cal.start(of: previous) >= state.enforcementChangedAt
            if carryOverEligible && facts.isMissed(previous, now: now) {
                return decide(true, .carryOver)
            }
            let lockAt = cal.date(minuteOfDay: lockStartMinute, in: cycle)
            if now >= lockAt { return decide(true, .awaitingCommit) }
            return decide(false, .beforeLockStart(lockAt: lockAt), lockAt)

        case .earn:
            if let end = facts.activeEarnWindowEnd(at: now) {
                return decide(false, .earnWindowActive(until: end), end)
            }
            return decide(true, facts.counted(cycle).isEmpty ? .awaitingCommit : .earnWindowExpired)
        }
    }
}
