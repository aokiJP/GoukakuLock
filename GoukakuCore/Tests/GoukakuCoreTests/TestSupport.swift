import Foundation
@testable import GoukakuCore

let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// 東京時間で日時を作る
func t(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, tz: TimeZone = tokyo) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

func c(_ s: String) -> CycleID { CycleID(s)! }

let studyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let runID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let optionalID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

func study(weekdays: Set<Int> = Set(1...7), from: String = "2026-10-01",
           method: VerificationMethod = .selfReport) -> HabitSnapshot {
    HabitSnapshot(id: studyID, title: "英単語20個", minimumTitle: "英単語5個",
                  weekdays: weekdays, method: method, activeFrom: c(from))
}

func makeState(mode: LockMode = .morning,
               dayStart: Int = 240,
               habits: [HabitSnapshot] = [study()],
               achievements: [Achievement] = [],
               restDays: Set<CycleID> = [],
               emergency: EmergencyWindow? = nil,
               pauses: [PausePeriod] = [],
               enforcement: Enforcement = .lock,
               enforcementChangedAt: Date = t(2026, 9, 30, 12, 0),
               activeSince: CycleID = c("2026-10-01")) -> SharedState {
    SharedState(schedule: ScheduleConfig(dayStartMinute: dayStart, mode: mode),
                enforcement: enforcement,
                enforcementChangedAt: enforcementChangedAt,
                activeSince: activeSince,
                habits: habits,
                achievements: achievements,
                restDays: restDays,
                emergency: emergency,
                pauses: pauses,
                updatedAt: t(2026, 10, 1, 0, 0))
}

func done(_ cycle: String, _ habit: UUID = studyID, at: Date, kind: Achievement.Kind = .full,
          status: Achievement.Status = .confirmed, grants: Int? = nil, id: UUID = UUID()) -> Achievement {
    Achievement(id: id, cycle: c(cycle), habitID: habit, kind: kind, status: status, at: at, grantsMinutes: grants)
}

func evaluate(_ s: SharedState, _ now: Date, extra: [Achievement] = []) -> LockDecision {
    LockEngine.evaluate(s, extra: extra, now: now, timeZone: tokyo)
}
