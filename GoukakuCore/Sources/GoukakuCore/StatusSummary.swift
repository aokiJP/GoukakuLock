import Foundation

/// いまの状態の言い方(仕様書 第5.2節の表)。本体のホーム・ウィジェット・Live Activity・Siri が同じ言葉を使う。
public struct StatusSummary: Equatable, Sendable {
    /// 印の色合い(本体とウィジェットが色に置き換える)
    public enum Tone: String, Codable, Sendable {
        case locked      // ロック中(墨)
        case achieved    // 達成(朱で塗る)
        case grace       // 夕方からロックの猶予中
        case emergency   // 緊急解除(琥珀)
        case earn        // 稼働型の解除枠
        case rest        // 休養日・見守り
        case idle        // 予定なし・一時停止・開始前
    }

    /// 丸い印の文字(合格・未・猶・急・解・休・空・停・見・待)
    public var seal: String
    public var tone: Tone
    /// ホームの見出し
    public var headline: String
    /// ウィジェット・ロック画面用の短い見出し
    public var shortHeadline: String
    public var detail: String?
    /// 残り時間を数える先(なければ数えない)
    public var countdownTo: Date?
    public var countdownLabel: String
    public var shouldLock: Bool
    public var cycle: CycleID
    public var nextCheck: Date?
    /// 今日の必須コミット(名前と達成済みか)
    public var required: [Item]
    public var optional: [Item]

    public struct Item: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var done: Bool
        public var minimum: Bool
        public var method: VerificationMethod

        public init(id: UUID, title: String, done: Bool, minimum: Bool, method: VerificationMethod) {
            self.id = id
            self.title = title
            self.done = done
            self.minimum = minimum
            self.method = method
        }
    }

    public var doneCount: Int { required.filter(\.done).count }
    public var pending: [Item] { required.filter { !$0.done } }

    public init(seal: String, tone: Tone, headline: String, shortHeadline: String, detail: String? = nil,
                countdownTo: Date? = nil, countdownLabel: String = "あと", shouldLock: Bool,
                cycle: CycleID, nextCheck: Date? = nil, required: [Item] = [], optional: [Item] = []) {
        self.seal = seal
        self.tone = tone
        self.headline = headline
        self.shortHeadline = shortHeadline
        self.detail = detail
        self.countdownTo = countdownTo
        self.countdownLabel = countdownLabel
        self.shouldLock = shouldLock
        self.cycle = cycle
        self.nextCheck = nextCheck
        self.required = required
        self.optional = optional
    }

    public static func make(state: SharedState, extra: [Achievement] = [], now: Date,
                            timeZone: TimeZone = .current) -> StatusSummary {
        let decision = LockEngine.evaluate(state, extra: extra, now: now, timeZone: timeZone)
        let cal = CycleCalendar(dayStartMinute: state.schedule.dayStartMinute, timeZone: timeZone)
        let clockCal = ClockText.calendar(timeZone: timeZone)
        func clock(_ date: Date) -> String { ClockText.relative(date, now: now, calendar: clockCal) }

        // 今日のコミットと達成(同じ id は本体の state.json 側を優先)
        let weekday = cal.weekday(of: decision.cycle)
        let known = Set(state.achievements.map(\.id))
        let counted = (state.achievements + extra.filter { !known.contains($0.id) })
            .filter { $0.cycle == decision.cycle && $0.status.counts }
        func item(_ habit: HabitSnapshot) -> Item {
            let hits = counted.filter { $0.habitID == habit.id }
            return Item(id: habit.id, title: habit.title, done: !hits.isEmpty,
                        minimum: !hits.isEmpty && hits.allSatisfy { $0.kind == .minimum }, method: habit.method)
        }
        let scheduled = state.habits.filter { $0.isScheduled(on: decision.cycle, weekday: weekday) }
        let required = scheduled.filter(\.isRequired).map(item)
        let optional = scheduled.filter { !$0.isRequired }.map(item)
        let pending = required.filter { !$0.done }
        let name = pending.first.map { "「\(ClockText.short($0.title, limit: 24))」" } ?? "今日のコミット"
        let shortName = pending.first.map { "「\(ClockText.short($0.title, limit: 10))」" } ?? "今日の分"
        let more = pending.count > 1 ? "ほか\(pending.count - 1)件" : ""
        let boundary = cal.end(of: decision.cycle)

        var s: StatusSummary
        switch decision.reason {
        case .awaitingCommit:
            s = StatusSummary(seal: "未", tone: .locked, headline: "今日の\(name)\(more)がまだです",
                              shortHeadline: "\(shortName)がまだ",
                              detail: "ロック中。達成すると、お金を使うアプリのロックが外れます。",
                              shouldLock: true, cycle: decision.cycle)
        case .carryOver:
            s = StatusSummary(seal: "未", tone: .locked, headline: "昨日は未達成。今日の分を終えるまでロック中",
                              shortHeadline: "昨日は未達成・ロック中",
                              detail: "今日の\(name)\(more)を終えると外れます。",
                              shouldLock: true, cycle: decision.cycle)
        case .earnWindowExpired:
            var window = ""
            if case .earn(let minutes) = state.schedule.mode { window = ClockText.duration(minutes: minutes) }
            s = StatusSummary(seal: "未", tone: .locked, headline: "解除枠が終わりました。もう1回で\(window)",
                              shortHeadline: "解除枠が終了",
                              detail: "チェックインするたびに\(window)使えます。",
                              shouldLock: true, cycle: decision.cycle)
        case .achieved:
            s = StatusSummary(seal: "合格", tone: .achieved, headline: "今日は達成。\(clock(boundary)) まで使えます",
                              shortHeadline: "今日は達成", detail: nil,
                              countdownTo: boundary, countdownLabel: "切り替えまで",
                              shouldLock: false, cycle: decision.cycle)
        case .earnWindowActive(let until):
            s = StatusSummary(seal: "解", tone: .earn, headline: "解除中", shortHeadline: "解除中",
                              detail: "\(clock(until)) に判定し直します。", countdownTo: until,
                              shouldLock: false, cycle: decision.cycle)
        case .emergency(let until):
            s = StatusSummary(seal: "急", tone: .emergency, headline: "緊急解除中", shortHeadline: "緊急解除中",
                              detail: "\(clock(until)) に判定し直します。", countdownTo: until,
                              shouldLock: false, cycle: decision.cycle)
        case .beforeLockStart(let lockAt):
            s = StatusSummary(seal: "猶", tone: .grace, headline: "\(ClockText.hm(lockAt, calendar: clockCal)) からロック。それまでにやろう",
                              shortHeadline: "\(ClockText.hm(lockAt, calendar: clockCal)) からロック",
                              detail: "今日の\(name)\(more)を終えれば、ロックはかかりません。",
                              countdownTo: lockAt, countdownLabel: "ロックまで",
                              shouldLock: false, cycle: decision.cycle)
        case .restDay:
            s = StatusSummary(seal: "休", tone: .rest, headline: "今日は休養日", shortHeadline: "今日は休養日",
                              detail: "ロックはかかりません。ストリークも途切れません。",
                              shouldLock: false, cycle: decision.cycle)
        case .noCommitToday:
            s = StatusSummary(seal: "空", tone: .idle, headline: "今日は予定なし", shortHeadline: "今日は予定なし",
                              detail: "予定された必須コミットがない日はロックしません。",
                              shouldLock: false, cycle: decision.cycle)
        case .paused:
            let end = state.pauses.first { $0.contains(now) }?.end
            s = StatusSummary(seal: "停", tone: .idle, headline: "一時停止中", shortHeadline: "一時停止中",
                              detail: end.map { "\(clock($0)) に再開します。" } ?? "無期限。再開するまでロックしません。",
                              shouldLock: false, cycle: decision.cycle)
        case .monitorOnly:
            s = StatusSummary(seal: "見", tone: .rest, headline: "見守りモード(記録だけ)", shortHeadline: "見守りモード",
                              detail: "ロックはせず、記録とストリークだけを続けます。",
                              shouldLock: false, cycle: decision.cycle)
        case .notStarted:
            let start = cal.start(of: state.activeSince)
            s = StatusSummary(seal: "待", tone: .idle, headline: "\(clock(start)) から始まります",
                              shortHeadline: "\(clock(start)) から開始",
                              detail: "それまではロックしません。", countdownTo: start, countdownLabel: "開始まで",
                              shouldLock: false, cycle: decision.cycle)
        }
        if decision.shouldLock {
            s.detail = [s.detail, "切り替え:\(clock(boundary))"].compactMap { $0 }.joined(separator: "\n")
            if s.countdownTo == nil {
                s.countdownTo = boundary
                s.countdownLabel = "切り替えまで"
            }
        }
        if let startsAt = decision.emergencyStartsAt {
            s.detail = [s.detail, "緊急解除は \(clock(startsAt)) から"].compactMap { $0 }.joined(separator: "\n")
            s.countdownTo = startsAt
            s.countdownLabel = "緊急解除まで"
        }
        s.nextCheck = decision.nextCheck
        s.required = required
        s.optional = optional
        return s
    }

    /// Siri やログ向けの一文
    public var sentence: String {
        var parts = [headline]
        if !pending.isEmpty && shouldLock {
            parts.append("残り\(pending.count)件")
        }
        return parts.joined(separator: "。")
    }
}
