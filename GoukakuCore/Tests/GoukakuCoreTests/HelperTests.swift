import XCTest
@testable import GoukakuCore

final class AutoAchievementTests: XCTestCase {
    let usageHabit = HabitSnapshot(id: studyID, title: "英語アプリ30分", method: .appUsage,
                                   targetMinutes: 30, activeFrom: c("2026-10-01"))

    func testCreatesAchievementWhenPlausible() {
        let s = makeState(habits: [usageHabit])
        let a = AutoAchievement.make(habitID: studyID, state: s, existing: [], now: t(2026, 10, 9, 9, 0), timeZone: tokyo)
        XCTAssertEqual(a?.cycle, c("2026-10-09"))
        XCTAssertEqual(a?.source, .monitor)
        XCTAssertNil(a?.grantsMinutes)
        XCTAssertFalse(evaluate(s, t(2026, 10, 9, 9, 1), extra: [a!]).shouldLock)
    }

    func testRejectsPrematureFire() {
        // 日付切替 4:00 から 30 分たっていない 4:10 の発火は誤発火
        let s = makeState(habits: [usageHabit])
        XCTAssertNil(AutoAchievement.make(habitID: studyID, state: s, existing: [], now: t(2026, 10, 9, 4, 10), timeZone: tokyo))
    }

    func testRejectsDuplicatesAndWrongMethod() {
        let s = makeState(habits: [usageHabit])
        let first = AutoAchievement.make(habitID: studyID, state: s, existing: [], now: t(2026, 10, 9, 9, 0), timeZone: tokyo)!
        XCTAssertNil(AutoAchievement.make(habitID: studyID, state: s, existing: [first], now: t(2026, 10, 9, 9, 0), timeZone: tokyo))
        XCTAssertNil(AutoAchievement.make(habitID: studyID, state: makeState(), existing: [], now: t(2026, 10, 9, 9, 0), timeZone: tokyo))
        XCTAssertNil(AutoAchievement.make(habitID: UUID(), state: s, existing: [], now: t(2026, 10, 9, 9, 0), timeZone: tokyo))
    }

    func testRejectsAfterMidnightBecauseIntervalEndsAt2359() {
        let s = makeState(habits: [usageHabit])
        XCTAssertNil(AutoAchievement.make(habitID: studyID, state: s, existing: [], now: t(2026, 10, 10, 1, 0), timeZone: tokyo))
    }

    func testEarnModeGrantsWindow() {
        let s = makeState(mode: .earn(windowMinutes: 120), habits: [usageHabit])
        XCTAssertEqual(AutoAchievement.make(habitID: studyID, state: s, existing: [], now: t(2026, 10, 9, 9, 0), timeZone: tokyo)?.grantsMinutes, 120)
    }
}

final class ShieldCopyTests: XCTestCase {

    func testAwaitingCommitText() {
        let text = ShieldCopy.make(state: makeState(), now: t(2026, 10, 9, 10, 0), timeZone: tokyo)
        XCTAssertEqual(text.title, "「英単語20個」がまだです")
        XCTAssertTrue(text.subtitle.contains("切り替え:明日 4:00"))
        XCTAssertTrue(text.subtitle.contains("緊急解除(15分後に2時間)"))
        XCTAssertEqual(text.primaryButton, "チェックインする")
    }

    func testCarryOverAndEmergencyPending() {
        let s = makeState(mode: .evening(lockStartMinute: 21 * 60),
                          emergency: EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 8, 0)))
        let text = ShieldCopy.make(state: s, now: t(2026, 10, 9, 8, 5), timeZone: tokyo)
        XCTAssertEqual(text.title, "昨日は未達成でした")
        XCTAssertTrue(text.subtitle.contains("緊急解除は 今日 8:15 から"))
    }

    func testMultiplePendingAndLongTitle() {
        let long = HabitSnapshot(id: studyID, title: "TOEIC公式問題集のパート5を2セット解く", activeFrom: c("2026-10-01"))
        let run = HabitSnapshot(id: runID, title: "ランニング", activeFrom: c("2026-10-01"))
        let text = ShieldCopy.make(state: makeState(habits: [long, run]), now: t(2026, 10, 9, 10, 0), timeZone: tokyo)
        XCTAssertEqual(text.title, "「TOEIC公式問題集のパート5…」ほか1件がまだです")
    }

    func testEarnExpiredText() {
        let s = makeState(mode: .earn(windowMinutes: 90),
                          achievements: [done("2026-10-09", at: t(2026, 10, 9, 8, 0), grants: 90)])
        let text = ShieldCopy.make(state: s, now: t(2026, 10, 9, 10, 0), timeZone: tokyo)
        XCTAssertEqual(text.title, "解除枠が終わりました")
        XCTAssertTrue(text.subtitle.contains("1時間30分使えます"))
    }

    func testStaleShieldText() {
        let s = makeState(achievements: [done("2026-10-09", at: t(2026, 10, 9, 9, 0))])
        XCTAssertEqual(ShieldCopy.make(state: s, now: t(2026, 10, 9, 10, 0), timeZone: tokyo).title, "ロックは外れています")
    }
}

final class ReminderPlannerTests: XCTestCase {
    let settings = ReminderSettings(minutesOfDay: [12 * 60, 20 * 60])
    let yesterdayDone = done("2026-10-08", at: t(2026, 10, 8, 9, 0))

    func plan(_ s: SharedState, _ settings: ReminderSettings? = nil, now: Date = t(2026, 10, 9, 10, 0)) -> [PlannedReminder] {
        ReminderPlanner.plan(state: s, settings: settings ?? self.settings, now: now, horizon: 7, timeZone: tokyo)
    }

    func testRegularPlan() {
        let p = plan(makeState(achievements: [yesterdayDone]))
        XCTAssertEqual(p.count, 14)
        XCTAssertEqual(p.first?.fireAt, t(2026, 10, 9, 12, 0))
        XCTAssertEqual(p.first?.id, "remind-2026-10-09-0")
        XCTAssertTrue(p.allSatisfy { $0.kind == .regular })
    }

    func testSkipsSatisfiedTodayAndRestDays() {
        let s = makeState(achievements: [yesterdayDone, done("2026-10-09", at: t(2026, 10, 9, 9, 0))],
                          restDays: [c("2026-10-10")])
        let p = plan(s)
        XCTAssertFalse(p.contains { $0.cycle == c("2026-10-09") })
        XCTAssertFalse(p.contains { $0.cycle == c("2026-10-10") })
        XCTAssertEqual(p.count, 10)
    }

    func testQuietHoursAndCap() {
        let noisy = ReminderSettings(minutesOfDay: [6 * 60, 9 * 60, 12 * 60, 15 * 60, 18 * 60, 21 * 60, 23 * 60 + 30],
                                     maxPerDay: 4)
        let p = plan(makeState(achievements: [yesterdayDone]), noisy, now: t(2026, 10, 9, 4, 30))
        let today = p.filter { $0.cycle == c("2026-10-09") }
        XCTAssertEqual(today.map(\.fireAt), [t(2026, 10, 9, 9, 0), t(2026, 10, 9, 12, 0), t(2026, 10, 9, 15, 0), t(2026, 10, 9, 18, 0)])
    }

    func testEscalationAfterOneMissButNotAfterThree() {
        // 10/8 未達成、10/7 達成 → 1回の未達成 → 今日だけ13:00を追加
        let oneMiss = makeState(achievements: [done("2026-10-07", at: t(2026, 10, 7, 9, 0))])
        XCTAssertEqual(ReminderPlanner.consecutiveMisses(state: oneMiss, now: t(2026, 10, 9, 10, 0), timeZone: tokyo), 1)
        let p = plan(oneMiss).filter { $0.cycle == c("2026-10-09") }
        XCTAssertEqual(p.map(\.fireAt), [t(2026, 10, 9, 12, 0), t(2026, 10, 9, 13, 0), t(2026, 10, 9, 20, 0)])
        XCTAssertEqual(p[1].kind, .escalation)

        // 10/1〜10/8 すべて未達成 → 立て直し(強化しない)
        let manyMisses = makeState()
        XCTAssertGreaterThanOrEqual(ReminderPlanner.consecutiveMisses(state: manyMisses, now: t(2026, 10, 9, 10, 0), timeZone: tokyo), 3)
        XCTAssertFalse(plan(manyMisses).contains { $0.kind == .escalation })
    }

    func testPausedTimesAreSkipped() {
        let s = makeState(achievements: [yesterdayDone],
                          pauses: [PausePeriod(start: t(2026, 10, 9, 11, 0), end: t(2026, 10, 11, 4, 0))])
        let p = plan(s)
        XCTAssertFalse(p.contains { $0.cycle == c("2026-10-09") || $0.cycle == c("2026-10-10") })
        XCTAssertEqual(p.first?.fireAt, t(2026, 10, 11, 12, 0))
    }
}
