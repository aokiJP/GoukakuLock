import Foundation
import GoukakuCore
import GoukakuKit

public enum ActionError: Error, Equatable {
    case notConfigured
    case emergencyAlreadyRequested
    case notAllowedWhileLocked
    case undoWindowPassed
    case rejected(Acceptance)
}

/// 本体アプリの操作。state.json を書くのはここだけ。メインアクターで直列に呼ぶ。
@MainActor
public final class AppActions {
    public let store: SharedStateStore
    /// 時計(テストでは差し替える)。拡張メソッド(AppActions+Settings.swift)からも使う
    let clock: () -> Date

    public init(store: SharedStateStore, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.clock = clock
    }

    public func currentState() throws -> SharedState {
        guard let state = try store.load() else { throw ActionError.notConfigured }
        return state
    }

    /// state.json が壊れていたら、1つ前の保存から戻す。戻したら true(呼び出し側で回避ログに「復旧」と残す)
    @discardableResult
    public func recoverIfCorrupted() -> Bool {
        guard (try? store.load()) == nil, FileManager.default.fileExists(atPath: store.stateURL.path),
              let backup = try? store.loadBackup() else { return false }
        return (try? store.save(backup)) != nil
    }

    public func decision(at now: Date? = nil) throws -> LockDecision {
        LockEngine.evaluate(try currentState(), extra: store.pendingAchievements(), now: now ?? clock())
    }

    @discardableResult
    func mutate(_ body: (inout SharedState) throws -> Void) throws -> SharedState {
        var state = try currentState()
        try body(&state)
        state.updatedAt = clock()
        try store.save(state)
        return state
    }

    // MARK: チェックイン

    /// 達成を記録してロックを外す。status は確認方法で決める:
    /// 自己申告・写真・タイマー = confirmed/事後承認 = pendingReview/同期承認 = awaitingApproval
    @discardableResult
    public func checkIn(habitID: UUID, kind: Achievement.Kind,
                        status: Achievement.Status = .confirmed) throws -> Achievement {
        let now = clock()
        let state = try currentState()
        let cycle = LockEngine.evaluate(state, extra: store.pendingAchievements(), now: now).cycle
        var grants: Int?
        if case .earn(let window) = state.schedule.mode { grants = window }
        let achievement = Achievement(cycle: cycle, habitID: habitID, kind: kind, status: status,
                                      source: .app, at: now, grantsMinutes: grants)
        try mutate { $0.achievements.append(achievement) }
        if let minutes = grants, status.counts {
            try? ScheduleRegistrar.registerOneOff(.earnWindow, from: now,
                                                  to: now.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        let after = Reconciler.run(store: store, now: now, source: "checkin", logToInbox: false)
        if after?.todaySatisfied == true {
            ReminderScheduler.cancel(cycle: cycle)
            EmergencyNotifier.cancel()   // 解除中に達成したなら「あと10分で再ロック」は不要
            // 緊急解除の待機中に達成したら、待機を取り消す(回数に数えない)
            if let e = try? currentState().emergency, e.isPending(at: now) { try? cancelEmergency() }
        }
        return achievement
    }

    /// 押し間違いの取り消し(5分以内)。取り消すと判定し直し、必要ならロックが戻る。
    public func undoCheckIn(id: UUID) throws {
        let now = clock()
        try mutate { state in
            guard let i = state.achievements.firstIndex(where: { $0.id == id }) else { return }
            guard now.timeIntervalSince(state.achievements[i].at) <= 300 else { throw ActionError.undoWindowPassed }
            state.achievements[i].status = .undone
        }
        Reconciler.run(store: store, now: now, source: "undo", logToInbox: false)
    }

    // MARK: 緊急解除(安全の床:いつでも・ひとりで使える)

    /// makeWindow はデバッグメニューの「緊急解除を短くする」だけが渡す(通常は 15 分後から 2 時間で固定)
    public func requestEmergency(makeWindow: ((Date) -> EmergencyWindow)? = nil) throws -> EmergencyWindow {
        let now = clock()
        let state = try currentState()
        guard EmergencyPolicy.canRequest(existing: state.emergency, now: now) else {
            throw ActionError.emergencyAlreadyRequested
        }
        let window = makeWindow?(now) ?? EmergencyPolicy.makeWindow(requestedAt: now)
        try mutate { $0.emergency = window }
        // 登録に失敗しても非常口は止めない。開始時刻の通知から本体を開けば Reconciler が解除する。
        try? ScheduleRegistrar.registerOneOff(.emergency, from: window.startsAt, to: window.endsAt)
        EmergencyNotifier.schedule(window)
        return window
    }

    public func cancelEmergency() throws {
        let now = clock()
        try mutate { state in
            guard var e = state.emergency, e.cancelledAt == nil, now < e.endsAt else { return }
            e.cancelledAt = now
            state.emergency = e
        }
        ScheduleRegistrar.cancel(.emergency)
        EmergencyNotifier.cancel()
        Reconciler.run(store: store, now: now, source: "emergencyCancel", logToInbox: false)
    }

    // MARK: 一時停止(全体の非常口)

    /// ロックが外れているときだけ。ロック中は緊急解除(15分)を経てから。
    public func pause(until end: Date?) throws {
        let now = clock()
        guard try decision(at: now).shouldLock == false else { throw ActionError.notAllowedWhileLocked }
        try mutate { $0.pauses.append(PausePeriod(start: now, end: end)) }
        Reconciler.run(store: store, now: now, source: "pause", logToInbox: false)
    }

    public func resume() throws {
        let now = clock()
        try mutate { state in
            for i in state.pauses.indices where state.pauses[i].contains(now) {
                state.pauses[i].end = now
            }
        }
        Reconciler.run(store: store, now: now, source: "resume", logToInbox: false)
    }

    // MARK: 休養日(事前・週の上限内)

    public func addRestDay(_ day: CycleID, weeklyQuota: Int) throws {
        let now = clock()
        let state = try currentState()
        let d = LockEngine.evaluate(state, extra: store.pendingAchievements(), now: now)
        let cal = CycleCalendar(dayStartMinute: state.schedule.dayStartMinute)
        let week = cal.weekStart(of: day)
        let used = state.restDays.filter { cal.weekStart(of: $0) == week }.count
        let verdict = ChangePolicy.restDayAcceptance(day: day, current: d.cycle, canRelaxNow: d.canRelaxNow,
                                                     usedInThatWeek: used, weeklyQuota: weeklyQuota,
                                                     isPaused: d.reason == .paused)
        guard verdict == .applyNow else { throw ActionError.rejected(verdict) }
        try mutate { $0.restDays.insert(day) }
    }
}

/// 本体アプリが起動・前面に戻るたびに行う処理(冪等)。
/// このあと呼び出し側で:確定したサイクルを SwiftData に保存/待機中の設定変更を反映/
/// 区間登録の確認(ScheduleRegistrar.isDailyRegistered)/リマインドの作り直し/改ざん検知 を行う。
@MainActor
public struct LaunchTasks {
    public struct Report {
        public var recovered = false
        public var logs: [LogEntry] = []
        public var finalized: [(cycle: CycleID, outcome: CycleOutcome)] = []
        public var decision: LockDecision?
    }

    public let actions: AppActions

    public init(actions: AppActions) {
        self.actions = actions
    }

    /// lastFinalized:SwiftData 側で最後に確定したサイクル(初回は nil)
    public func run(lastFinalized: CycleID?, now: Date = Date()) throws -> Report {
        var report = Report()
        let store = actions.store
        report.recovered = actions.recoverIfCorrupted()
        // 1. 受信箱を取り込む(先に state.json に書き、あとでファイルを消す=途中で落ちても重複しない)
        let inbox = store.readInbox()
        var state = try actions.currentState()
        let known = Set(state.achievements.map(\.id))
        for entry in inbox {
            switch entry.item {
            case .achievement(let a):
                if !known.contains(a.id) { state.achievements.append(a) }
            case .log(let log):
                report.logs.append(log)
            }
        }
        // 2. 終わったサイクルの結果を確定する(保存は呼び出し側)
        let cal = CycleCalendar(dayStartMinute: state.schedule.dayStartMinute)
        let current = cal.cycle(containing: now)
        var cycle = lastFinalized.map { cal.cycle($0, offsetBy: 1) } ?? state.activeSince
        while cycle < current {
            report.finalized.append((cycle, History.outcome(of: cycle, state: state, now: now)))
            cycle = cal.cycle(cycle, offsetBy: 1)
        }
        // 3. 14 サイクルより古いものを state.json から削る(履歴は SwiftData にある)
        let cutoff = cal.cycle(current, offsetBy: -14)
        state.achievements.removeAll { $0.cycle < cutoff }
        state.restDays = state.restDays.filter { $0 >= cutoff }
        state.habits.removeAll { $0.activeUntil.map { $0 < cutoff } ?? false }
        state.pauses.removeAll { $0.end.map { $0 < cal.start(of: cutoff) } ?? false }
        state.updatedAt = now
        try store.save(state)
        store.removeInbox(inbox.map(\.url))
        // 4. 判定してロックを適用
        report.decision = Reconciler.run(store: store, now: now, source: "launch", logToInbox: false)
        return report
    }
}
