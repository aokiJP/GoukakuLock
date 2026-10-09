import Foundation

// MARK: - 使用時間による自動判定

public enum AutoAchievement {
    /// DeviceActivity のしきい値イベントから達成を作る。誤発火・重複・対象外なら nil。
    /// しきい値イベントには早すぎる発火・二重発火の報告があるため、ここで必ずふるいにかける。
    public static func make(habitID: UUID, state: SharedState, existing extra: [Achievement],
                            now: Date, timeZone: TimeZone = .current) -> Achievement? {
        let facts = Facts(state, extra: extra, timeZone: timeZone)
        let cal = facts.cal
        let cycle = cal.cycle(containing: now)
        guard let habit = state.habits.first(where: { $0.id == habitID }),
              habit.method == .appUsage,
              let minutes = habit.targetMinutes, minutes > 0,
              habit.isScheduled(on: cycle, weekday: cal.weekday(of: cycle)) else { return nil }
        // 計測区間は「日付切替 〜 23:59」。区間の始まりから minutes 分たっていなければ物理的にありえない=誤発火
        let intervalStart = cal.start(of: cycle)
        guard now.timeIntervalSince(intervalStart) >= TimeInterval(minutes * 60),
              cal.calendar.isDate(now, inSameDayAs: intervalStart) else { return nil }
        // すでに本来の目標で達成済みなら作らない(二重発火対策)
        guard !facts.counted(cycle).contains(where: { $0.habitID == habitID && $0.kind == .full }) else { return nil }
        let grants: Int?
        if case .earn(let window) = state.schedule.mode { grants = window } else { grants = nil }
        return Achievement(cycle: cycle, habitID: habitID, kind: .full, status: .confirmed,
                           source: .monitor, at: now, grantsMinutes: grants)
    }
}

// MARK: - シールドの文言

public struct ShieldText: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var primaryButton: String
    public var secondaryButton: String

    public init(title: String, subtitle: String, primaryButton: String, secondaryButton: String) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }
}

public enum ShieldCopy {
    public static func make(state: SharedState, extra: [Achievement] = [], now: Date,
                            timeZone: TimeZone = .current) -> ShieldText {
        let decision = LockEngine.evaluate(state, extra: extra, now: now, timeZone: timeZone)
        let facts = Facts(state, extra: extra, timeZone: timeZone)
        let cal = facts.cal
        guard decision.shouldLock else {
            // 判定上は解除済み(シールドが残っているだけ)
            return ShieldText(title: "ロックは外れています",
                              subtitle: "いったん閉じて、もう一度開いてください。",
                              primaryButton: "閉じる", secondaryButton: "閉じる")
        }
        let doneIDs = Set(facts.counted(decision.cycle).map(\.habitID))
        let pending = facts.requiredHabits(decision.cycle).filter { !doneIDs.contains($0.id) }
        let name = pending.first.map { short($0.title) } ?? "今日のコミット"
        let more = pending.count > 1 ? "ほか\(pending.count - 1)件" : ""
        let boundary = clock(cal.end(of: decision.cycle), now: now, cal: cal.calendar)

        var title: String
        var lines: [String]
        switch decision.reason {
        case .carryOver:
            title = "昨日は未達成でした"
            lines = ["今日の「\(name)」\(more)を終えるまでロック中です。"]
        case .earnWindowExpired:
            title = "解除枠が終わりました"
            var unlockFor = ""
            if case .earn(let window) = state.schedule.mode { unlockFor = duration(window) }
            lines = ["もう1回チェックインすると\(unlockFor)使えます。"]
        default:
            title = "「\(name)」\(more)がまだです"
            lines = ["達成すると、お金を使うアプリのロックが外れます。", "切り替え:\(boundary)"]
        }
        if let startsAt = decision.emergencyStartsAt {
            lines.append("緊急解除は \(clock(startsAt, now: now, cal: cal.calendar)) から")
        } else {
            lines.append("急ぐときは本体アプリの緊急解除(15分後に2時間)")
        }
        return ShieldText(title: title, subtitle: lines.joined(separator: "\n"),
                          primaryButton: "チェックインする", secondaryButton: "閉じる")
    }

    static func short(_ text: String, limit: Int = 16) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)時間\(m)分" }
        return h > 0 ? "\(h)時間" : "\(m)分"
    }

    /// 「今日 21:00」「明日 4:00」「10/12 4:00」
    static func clock(_ date: Date, now: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        let hm = "\(c.hour!):" + String(format: "%02d", c.minute!)
        if cal.isDate(date, inSameDayAs: now) { return "今日 \(hm)" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "明日 \(hm)"
        }
        return "\(c.month!)/\(c.day!) \(hm)"
    }
}

// MARK: - リマインド通知の計画

public struct ReminderSettings: Codable, Equatable, Sendable {
    /// 通知する時刻(0:00 からの分)
    public var minutesOfDay: [Int]
    /// 通知しない時間帯(睡眠を守る)。start > end なら 0:00 をまたぐ
    public var quietStartMinute: Int
    public var quietEndMinute: Int
    /// 1日の上限
    public var maxPerDay: Int

    public init(minutesOfDay: [Int] = [12 * 60, 20 * 60], quietStartMinute: Int = 23 * 60,
                quietEndMinute: Int = 7 * 60, maxPerDay: Int = 4) {
        self.minutesOfDay = minutesOfDay
        self.quietStartMinute = quietStartMinute
        self.quietEndMinute = quietEndMinute
        self.maxPerDay = maxPerDay
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case regular      // 設定した時刻
        case escalation   // 前日未達成のときに1回だけ足す
    }

    public var id: String
    public var cycle: CycleID
    public var fireAt: Date
    public var kind: Kind
}

public enum ReminderPlanner {
    /// 直前のサイクルから数えた連続未達成数(最大 7)。3 以上なら「立て直し」を提案し、通知の強化はやめる。
    public static func consecutiveMisses(state: SharedState, extra: [Achievement] = [], now: Date,
                                         timeZone: TimeZone = .current) -> Int {
        let facts = Facts(state, extra: extra, timeZone: timeZone)
        var count = 0
        var probe = facts.cal.cycle(facts.cal.cycle(containing: now), offsetBy: -1)
        while count < 7 && facts.isMissed(probe, now: now) {
            count += 1
            probe = facts.cal.cycle(probe, offsetBy: -1)
        }
        return count
    }

    /// これから horizon サイクル分の通知を計画する。本体アプリが起動のたびに作り直す(iOS の保留上限 64 件に収まる)。
    public static func plan(state: SharedState, settings: ReminderSettings, extra: [Achievement] = [],
                            now: Date, horizon: Int = 7, timeZone: TimeZone = .current) -> [PlannedReminder] {
        let facts = Facts(state, extra: extra, timeZone: timeZone)
        let cal = facts.cal
        let today = cal.cycle(containing: now)
        let misses = consecutiveMisses(state: state, extra: extra, now: now, timeZone: timeZone)
        var result: [PlannedReminder] = []

        for offset in 0..<horizon {
            let cycle = cal.cycle(today, offsetBy: offset)
            guard cycle >= state.activeSince, !state.restDays.contains(cycle),
                  !facts.requiredHabits(cycle).isEmpty else { continue }
            if offset == 0 && facts.isSatisfied(cycle) { continue }

            var entries: [(Date, PlannedReminder.Kind)] = settings.minutesOfDay
                .map { (cal.date(minuteOfDay: $0, in: cycle), .regular) }
                .sorted { $0.0 < $1.0 }
            if offset == 0, (1...2).contains(misses), let first = entries.first {
                entries.append((first.0.addingTimeInterval(3600), .escalation))
            }
            entries = entries
                .filter { $0.0 > now && !isQuiet($0.0, settings, cal.calendar) && facts.pause(at: $0.0) == nil }
                .sorted { $0.0 < $1.0 }
            for (index, entry) in entries.prefix(settings.maxPerDay).enumerated() {
                result.append(PlannedReminder(id: "remind-\(cycle)-\(index)", cycle: cycle,
                                              fireAt: entry.0, kind: entry.1))
            }
        }
        return result.sorted { $0.fireAt < $1.fireAt }
    }

    static func isQuiet(_ date: Date, _ s: ReminderSettings, _ cal: Calendar) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: date)
        let m = c.hour! * 60 + c.minute!
        if s.quietStartMinute == s.quietEndMinute { return false }
        if s.quietStartMinute < s.quietEndMinute { return m >= s.quietStartMinute && m < s.quietEndMinute }
        return m >= s.quietStartMinute || m < s.quietEndMinute
    }
}
