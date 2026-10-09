import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import GoukakuCore

extension DeviceActivityName {
    public static var cycleMain: Self { Self(ActivityPlan.Name.cycleMain.rawValue) }
    public static var lockStart: Self { Self(ActivityPlan.Name.lockStart.rawValue) }
    public static var emergency: Self { Self("emergency") }
    public static var earnWindow: Self { Self("earnWindow") }
}

extension DeviceActivityEvent.Name {
    /// ロック対象アプリが合計1分使われたら判定をやり直す保険
    public static var tripwire: Self { Self("tripwire") }

    public static func usage(_ habitID: UUID) -> Self { Self("usage-\(habitID.uuidString)") }

    public var usageHabitID: UUID? {
        guard rawValue.hasPrefix("usage-") else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst("usage-".count)))
    }
}

/// 使用時間で達成を判定するコミット
public struct UsageSource {
    public var habitID: UUID
    public var minutes: Int
    public var selection: FamilyActivitySelection

    public init(habitID: UUID, minutes: Int, selection: FamilyActivitySelection) {
        self.habitID = habitID
        self.minutes = minutes
        self.selection = selection
    }
}

/// DeviceActivity への登録(本体アプリから呼ぶ)
public enum ScheduleRegistrar {
    /// 毎日の区間を登録し直す。区間は 0:00 をまたがない(しきい値イベントが 0:00 またぎで効かない報告があるため)。
    public static func registerDaily(config: ScheduleConfig, targets: LockTargets, usage: [UsageSource]) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.cycleMain, .lockStart])
        let plans = SchedulePlanner.plans(for: config,
                                          usageEvents: usage.map { .init(habitID: $0.habitID, minutes: $0.minutes) })
        for plan in plans {
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            if plan.tripwire && !targets.isEmpty {
                events[.tripwire] = DeviceActivityEvent(
                    applications: targets.lock.applicationTokens,
                    categories: targets.lock.categoryTokens,
                    webDomains: targets.lock.webDomainTokens,
                    threshold: DateComponents(minute: 1))
            }
            for source in usage where plan.usageEvents.contains(where: { $0.habitID == source.habitID }) {
                events[.usage(source.habitID)] = DeviceActivityEvent(
                    applications: source.selection.applicationTokens,
                    categories: source.selection.categoryTokens,
                    webDomains: source.selection.webDomainTokens,
                    threshold: DateComponents(minute: source.minutes),
                    includesPastActivity: true)   // 登録し直しても、その日の利用分を数える
            }
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: plan.startMinute / 60, minute: plan.startMinute % 60),
                intervalEnd: DateComponents(hour: plan.endMinute / 60, minute: plan.endMinute % 60),
                repeats: true)
            try center.startMonitoring(DeviceActivityName(plan.name.rawValue), during: schedule, events: events)
        }
    }

    /// 単発の区間(緊急解除・稼働型の解除枠)。時:分で指定し、終わりが始まりより前なら翌日の時刻と解釈される前提
    /// (実機スパイク SP-05 で確認。だめなら年月日を含めた DateComponents に切り替える)。
    public static func registerOneOff(_ name: DeviceActivityName, from start: Date, to end: Date,
                                      calendar: Calendar = .current) throws {
        let parts: Set<Calendar.Component> = [.hour, .minute]
        // 終わりは次の 0 秒に切り上げる(秒の端数で、終了の合図の時点ではまだ枠内と判定されるのを防ぐ)
        let roundedEnd = Date(timeIntervalSinceReferenceDate: (end.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: roundedEnd),
            repeats: false)
        let center = DeviceActivityCenter()
        center.stopMonitoring([name])
        try center.startMonitoring(name, during: schedule)
    }

    public static func cancel(_ name: DeviceActivityName) {
        DeviceActivityCenter().stopMonitoring([name])
    }

    /// いま監視している区間に、毎日の区間が揃っているか(揃っていなければ登録し直す)
    public static func isDailyRegistered(config: ScheduleConfig) -> Bool {
        let expected = Set(SchedulePlanner.plans(for: config).map { DeviceActivityName($0.name.rawValue) })
        return expected.isSubset(of: Set(DeviceActivityCenter().activities))
    }
}
