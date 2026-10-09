import Foundation
import Observation
import SwiftData
import FamilyControls
import UserNotifications
import GoukakuCore
import GoukakuKit

/// 画面に出す知らせ(アラート)
struct UserMessage: Identifiable {
    let id = UUID()
    var title: String
    var body: String
}

/// あるサイクルのコミットと達成の要約
struct DaySummary {
    var cycle: CycleID
    var required: [HabitSnapshot]
    var optional: [HabitSnapshot]
    /// ロック解除・ストリークに数える達成(確定・事後承認待ち)
    var counted: [Achievement]

    func latestAchievement(for habitID: UUID) -> Achievement? {
        counted.filter { $0.habitID == habitID }.max { $0.at < $1.at }
    }

    func isDone(_ habitID: UUID) -> Bool {
        counted.contains { $0.habitID == habitID }
    }

    var pendingRequired: [HabitSnapshot] { required.filter { !isDone($0.id) } }
}

/// 統計(ストリーク・最長・通算)
struct HabitStats {
    var streak = 0
    var longest = 0
    var total = 0
}

/// 本体アプリの中心。state.json・targets.json・SwiftData をまとめて扱う。
/// state.json を書くのは AppActions だけで、ここはそれを呼び、結果を画面へ出す。
@MainActor @Observable
final class AppModel {
    let container: ModelContainer
    let store: SharedStateStore
    /// App Group が使えているか(使えないと拡張と状態を共有できない=署名の問題)
    let usesAppGroup: Bool
    let actions: AppActions

    private(set) var state: SharedState?
    private(set) var decision: LockDecision?
    private(set) var targets = LockTargets()
    // 以下は拡張(別ファイル)からも書くので internal にしておく
    var screenTimeApproved = false
    var notificationsAllowed = true
    var recoveredSharedFile = false
    var tamperDetectedAt: Date?
    var reinstallDetectedAt: Date?
    var registrationError: String?
    var message: UserMessage?
    /// 画面の再計算のきっかけ(SwiftData から作る値は自動で追えないため)
    private(set) var revision = 0

    @ObservationIgnored var boundaryTask: Task<Void, Never>?
    @ObservationIgnored var isRunningLifecycle = false
    @ObservationIgnored var lastMark: InstallMarker.Mark?
    @ObservationIgnored var cachedSettings: AppSettings?
    @ObservationIgnored var checkedReinstall = false

    init(container: ModelContainer) {
        self.container = container
        if let groupStore = AppGroup.store {
            store = groupStore
            usesAppGroup = true
        } else {
            let dir = URL.applicationSupportDirectory.appendingPathComponent("LocalShared", isDirectory: true)
            store = SharedStateStore(directory: dir)
            usesAppGroup = false
        }
        actions = AppActions(store: store)
        reload()
    }

    var context: ModelContext { container.mainContext }

    // MARK: 設定(SwiftData に1件)

    var settings: AppSettings {
        if let cachedSettings { return cachedSettings }
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
        let value = existing ?? AppSettings()
        if existing == nil {
            context.insert(value)
            try? context.save()
        }
        cachedSettings = value
        return value
    }

    // MARK: 状態の読み直し

    var needsOnboarding: Bool { state == nil }

    /// state.json・targets.json を読み直し、判定を計算する(ロックの適用はしない)
    func reload() {
        let loaded = try? store.load()
        state = loaded
        targets = TargetsStore.load(from: store.directory) ?? LockTargets()
        if let loaded {
            decision = LockEngine.evaluate(loaded, extra: store.pendingAchievements(), now: Date())
        } else {
            decision = nil
        }
        updateInstallMarker()
        scheduleBoundaryRefresh()
        revision &+= 1
    }

    /// 判定を計算し直してロックに反映する
    func reconcile(source: String) {
        _ = actions.reconcile(source: source)
        reload()
    }

    /// 判定が変わる時刻(nextCheck)に、自分で判定し直す(前面にいる間の表示とロックを合わせる)
    func scheduleBoundaryRefresh() {
        boundaryTask?.cancel()
        guard let next = decision?.nextCheck else { return }
        let delay = max(1, min(next.timeIntervalSinceNow + 1, 3600))
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.boundaryReached()
        }
    }

    private func boundaryReached() {
        reconcile(source: "boundary")
        rebuildReminders()
        Task { await updateBadge() }
    }

    private func updateInstallMarker() {
        guard state != nil else { return }
        let locked = decision?.shouldLock ?? false
        guard lastMark?.locked != locked else { return }
        let mark = InstallMarker.Mark(locked: locked, at: Date())
        InstallMarker.write(mark)
        lastMark = mark
    }

    // MARK: 暦

    var cycleCalendar: CycleCalendar {
        CycleCalendar(dayStartMinute: state?.schedule.dayStartMinute ?? 240)
    }

    var currentCycle: CycleID { cycleCalendar.cycle(containing: Date()) }
    var nextCycle: CycleID { cycleCalendar.cycle(currentCycle, offsetBy: 1) }

    // MARK: 問い合わせ

    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    var habits: [Habit] {
        _ = revision
        return fetchAll(Habit.self).sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func habit(_ id: UUID) -> Habit? {
        fetchAll(Habit.self).first { $0.id == id }
    }

    /// 本体の記録と、拡張が受信箱に置いた達成を合わせたもの(同じ id は本体側を優先)
    var allAchievements: [Achievement] {
        guard let state else { return [] }
        let known = Set(state.achievements.map(\.id))
        return state.achievements + store.pendingAchievements().filter { !known.contains($0.id) }
    }

    func summary(for cycle: CycleID) -> DaySummary? {
        guard let state else { return nil }
        let weekday = cycleCalendar.weekday(of: cycle)
        let order = Dictionary(fetchAll(Habit.self).map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { a, _ in a })
        let scheduled = state.habits
            .filter { $0.isScheduled(on: cycle, weekday: weekday) }
            .sorted { (order[$0.id] ?? 0, $0.title) < (order[$1.id] ?? 0, $1.title) }
        let counted = allAchievements.filter { $0.cycle == cycle && $0.status.counts }
        return DaySummary(cycle: cycle, required: scheduled.filter(\.isRequired),
                          optional: scheduled.filter { !$0.isRequired }, counted: counted)
    }

    var today: DaySummary? {
        _ = revision
        return summary(for: decision?.cycle ?? currentCycle)
    }

    /// 今週(月曜はじまり)に最小版を使った回数
    func minimumUsesThisWeek() -> Int {
        let cal = cycleCalendar
        let week = cal.weekStart(of: currentCycle)
        return allAchievements.filter {
            $0.kind == .minimum && $0.status.counts && cal.weekStart(of: $0.cycle) == week
        }.count
    }

    func canUseMinimum() -> Bool {
        ChangePolicy.canUseMinimum(usedThisWeek: minimumUsesThisWeek(), weeklyQuota: settings.minimumWeeklyQuota)
    }

    var emergencyRecords: [EmergencyRecord] {
        _ = revision
        return fetchAll(EmergencyRecord.self).sorted { $0.requestedAt > $1.requestedAt }
    }

    /// 今週、緊急解除が始まった回数
    func emergencyCountThisWeek() -> Int {
        let cal = cycleCalendar
        let week = cal.weekStart(of: currentCycle)
        let now = Date()
        return emergencyRecords.filter {
            $0.didStart(asOf: now) && cal.weekStart(of: cal.cycle(containing: $0.startsAt)) == week
        }.count
    }

    /// 連続で未達成のサイクル数(3 以上なら「立て直し」を出す)
    var consecutiveMisses: Int {
        guard let state else { return 0 }
        return ReminderPlanner.consecutiveMisses(state: state, extra: store.pendingAchievements(), now: Date())
    }

    /// サイクルごとの結果。確定済みは SwiftData、まだ確定していないものはその場で計算する
    func outcomeMap() -> [CycleID: CycleOutcome] {
        guard let state else { return [:] }
        var map: [CycleID: CycleOutcome] = [:]
        for record in fetchAll(CycleRecord.self) {
            if let cycle = record.cycle { map[cycle] = record.outcome }
        }
        let cal = cycleCalendar
        let now = Date()
        let extra = store.pendingAchievements()
        var cycle = currentCycle
        var steps = 0
        while cycle >= state.activeSince && map[cycle] == nil && steps < 400 {
            map[cycle] = History.outcome(of: cycle, state: state, extra: extra, now: now)
            cycle = cal.cycle(cycle, offsetBy: -1)
            steps += 1
        }
        return map
    }

    func stats() -> HabitStats {
        guard let state else { return HabitStats() }
        let map = outcomeMap()
        let cal = cycleCalendar
        var newestFirst: [CycleOutcome] = []
        var cycle = currentCycle
        while cycle >= state.activeSince && newestFirst.count < 3660 {
            newestFirst.append(map[cycle] ?? .missed)
            cycle = cal.cycle(cycle, offsetBy: -1)
        }
        var stats = HabitStats()
        stats.streak = History.currentStreak(newestFirst: newestFirst)
        stats.total = History.totalAchieved(newestFirst)
        var run = 0
        for outcome in newestFirst.reversed() {
            switch outcome {
            case .achieved, .minimum, .pendingReview:
                run += 1
                stats.longest = max(stats.longest, run)
            case .rest, .noCommit, .inProgress:
                continue
            case .paused, .missed, .notStarted:
                run = 0
            }
        }
        return stats
    }

    /// 直近 days サイクルの達成率(予定のあった日のうち達成した割合)。予定日が少なければ nil
    func achievementRate(lastDays days: Int, minimumScheduled: Int) -> Double? {
        guard state != nil else { return nil }
        let map = outcomeMap()
        let cal = cycleCalendar
        var achieved = 0, scheduled = 0
        var cycle = cal.cycle(currentCycle, offsetBy: -1)
        for _ in 0..<days {
            switch map[cycle] {
            case .achieved, .minimum, .pendingReview: achieved += 1; scheduled += 1
            case .missed: scheduled += 1
            default: break
            }
            cycle = cal.cycle(cycle, offsetBy: -1)
        }
        guard scheduled >= minimumScheduled else { return nil }
        return Double(achieved) / Double(scheduled)
    }

    // MARK: 記録

    func log(_ kind: String, _ detail: String, at date: Date = Date()) {
        context.insert(EventLog(at: date, kind: kind, detail: detail))
    }

    func save() {
        try? context.save()
        revision &+= 1
    }

    func show(_ title: String, _ body: String) {
        message = UserMessage(title: title, body: body)
    }

    func show(error: Error) {
        show("うまくいきませんでした", "\(error.localizedDescription)")
    }
}
