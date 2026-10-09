import Foundation

/// DeviceActivity に登録する毎日の区間の設計図(iOS 側でこれを DeviceActivitySchedule に変換する)。
/// 規則:区間は 0:00 をまたがない/長さ 15 分以上/同じ日付の中で start < end。
public struct ActivityPlan: Equatable, Sendable {
    public enum Name: String, Sendable {
        case cycleMain   // 日付切替 〜 23:59。サイクル開始の合図+トリップワイヤー+使用時間の判定
        case lockStart   // 夕方型のロック開始 〜 区間の終わり。ロック開始の合図+トリップワイヤー
    }

    public struct UsageEvent: Equatable, Sendable {
        public var habitID: UUID
        public var minutes: Int
        public init(habitID: UUID, minutes: Int) {
            self.habitID = habitID
            self.minutes = minutes
        }
    }

    public var name: Name
    /// 0:00 からの分(区間の始まり)
    public var startMinute: Int
    /// 0:00 からの分(区間の終わり。この分を含む)
    public var endMinute: Int
    /// ロック対象アプリが合計1分使われたら判定をやり直す「保険」のイベントを付けるか
    public var tripwire: Bool
    /// 使用時間で達成を判定するコミット
    public var usageEvents: [UsageEvent]

    public var lengthMinutes: Int { endMinute - startMinute + 1 }
}

public enum SchedulePlanner {
    public static let lastMinuteOfDay = 23 * 60 + 59
    public static let minimumIntervalMinutes = 15
    /// アプリとその拡張が同時に監視できる区間の上限(Apple の文書による)
    public static let maxMonitoredActivities = 20

    /// 日付切替時刻:0:00〜6:00、30 分刻み
    public static func isValidDayStart(_ minute: Int) -> Bool {
        (0...360).contains(minute) && minute % 30 == 0
    }

    /// 夕方型のロック開始時刻:30 分刻み、日付切替の 30 分後〜20 時間後
    /// (ロックしている時間が最低 4 時間あり、区間が 15 分以上になることを保証する)
    public static func isValidLockStart(_ minute: Int, dayStartMinute: Int) -> Bool {
        guard (0..<1440).contains(minute), minute % 30 == 0 else { return false }
        let offset = (minute - dayStartMinute + 1440) % 1440
        return (30...1200).contains(offset)
    }

    /// 稼働型の解除枠:30 分〜6 時間、30 分刻み
    public static func isValidEarnWindow(_ minutes: Int) -> Bool {
        (30...360).contains(minutes) && minutes % 30 == 0
    }

    public static func isValid(_ config: ScheduleConfig) -> Bool {
        guard isValidDayStart(config.dayStartMinute) else { return false }
        switch config.mode {
        case .morning: return true
        case .evening(let m): return isValidLockStart(m, dayStartMinute: config.dayStartMinute)
        case .earn(let w): return isValidEarnWindow(w)
        }
    }

    /// 毎日くり返す区間の一覧。緊急解除・稼働型の解除枠は単発の区間として別に登録する。
    public static func plans(for config: ScheduleConfig, usageEvents: [ActivityPlan.UsageEvent] = []) -> [ActivityPlan] {
        var result = [
            ActivityPlan(name: .cycleMain, startMinute: config.dayStartMinute, endMinute: lastMinuteOfDay,
                         tripwire: true, usageEvents: usageEvents)
        ]
        if case .evening(let lockStart) = config.mode {
            // 日付切替より後の時刻なら当日 23:59 まで、0:00 以降なら日付切替の 1 分前まで
            let end = lockStart > config.dayStartMinute ? lastMinuteOfDay : config.dayStartMinute - 1
            result.append(ActivityPlan(name: .lockStart, startMinute: lockStart, endMinute: end,
                                       tripwire: true, usageEvents: []))
        }
        return result
    }
}
