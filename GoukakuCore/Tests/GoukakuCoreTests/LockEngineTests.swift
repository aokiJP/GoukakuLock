import XCTest
@testable import GoukakuCore

final class LockEngineTests: XCTestCase {

    // MARK: 朝からロック

    func testMorningLockedUntilAchieved() {
        let d = evaluate(makeState(), t(2026, 10, 9, 10, 0))
        XCTAssertTrue(d.shouldLock)
        XCTAssertEqual(d.reason, .awaitingCommit)
        XCTAssertEqual(d.cycle, c("2026-10-09"))
        XCTAssertFalse(d.todaySatisfied)
        XCTAssertEqual(d.nextCheck, t(2026, 10, 10, 4, 0))
        XCTAssertFalse(d.canRelaxNow)
    }

    func testMorningUnlockedAfterAchievement() {
        let s = makeState(achievements: [done("2026-10-09", at: t(2026, 10, 9, 9, 0))])
        let d = evaluate(s, t(2026, 10, 9, 10, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .achieved)
        XCTAssertTrue(d.todaySatisfied)
        XCTAssertTrue(d.canRelaxNow)
    }

    func testCycleBoundaryRelocksAtDayStart() {
        let s = makeState(achievements: [done("2026-10-09", at: t(2026, 10, 9, 9, 0))])
        // 深夜 3:59 はまだ 10/9 のサイクル
        let before = evaluate(s, t(2026, 10, 10, 3, 59))
        XCTAssertEqual(before.cycle, c("2026-10-09"))
        XCTAssertFalse(before.shouldLock)
        // 4:00 で 10/10 のサイクルに切り替わり、ロック
        let after = evaluate(s, t(2026, 10, 10, 4, 0))
        XCTAssertEqual(after.cycle, c("2026-10-10"))
        XCTAssertTrue(after.shouldLock)
    }

    func testLateNightCheckInCountsForCurrentCycle() {
        // 10/10 1:30 のチェックインは 10/9 のサイクルの達成
        let s = makeState(achievements: [done("2026-10-09", at: t(2026, 10, 10, 1, 30))])
        XCTAssertFalse(evaluate(s, t(2026, 10, 10, 1, 31)).shouldLock)
    }

    // MARK: 夕方からロック

    func testEveningBeforeAndAfterLockStart() {
        let s = makeState(mode: .evening(lockStartMinute: 21 * 60),
                          achievements: [done("2026-10-08", at: t(2026, 10, 8, 20, 0))])
        let before = evaluate(s, t(2026, 10, 9, 20, 59))
        XCTAssertFalse(before.shouldLock)
        XCTAssertEqual(before.reason, .beforeLockStart(lockAt: t(2026, 10, 9, 21, 0)))
        XCTAssertEqual(before.nextCheck, t(2026, 10, 9, 21, 0))
        let after = evaluate(s, t(2026, 10, 9, 21, 0))
        XCTAssertTrue(after.shouldLock)
        XCTAssertEqual(after.reason, .awaitingCommit)
    }

    func testEveningCarryOverAfterMissedDay() {
        // 10/8 は未達成 → 10/9 は朝からロック
        let s = makeState(mode: .evening(lockStartMinute: 21 * 60))
        let d = evaluate(s, t(2026, 10, 9, 8, 0))
        XCTAssertTrue(d.shouldLock)
        XCTAssertEqual(d.reason, .carryOver)
    }

    func testEveningNoCarryOverAfterRestDay() {
        let s = makeState(mode: .evening(lockStartMinute: 21 * 60), restDays: [c("2026-10-08")])
        let d = evaluate(s, t(2026, 10, 9, 8, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .beforeLockStart(lockAt: t(2026, 10, 9, 21, 0)))
    }

    func testEveningNoCarryOverAfterPause() {
        let s = makeState(mode: .evening(lockStartMinute: 21 * 60),
                          pauses: [PausePeriod(start: t(2026, 10, 8, 10, 0), end: t(2026, 10, 8, 12, 0))])
        XCTAssertFalse(evaluate(s, t(2026, 10, 9, 8, 0)).shouldLock)
    }

    func testEveningNoCarryOverRightAfterSwitchingToLock() {
        // 見守り → ロックに切り替えたのが 10/8 の途中なら、10/8 の未達成は持ち越さない
        let s = makeState(mode: .evening(lockStartMinute: 21 * 60),
                          enforcementChangedAt: t(2026, 10, 8, 12, 0))
        XCTAssertFalse(evaluate(s, t(2026, 10, 9, 8, 0)).shouldLock)
    }

    func testEveningLockStartAfterMidnight() {
        // 日付切替 4:00、ロック開始 0:00 → 10/9 のサイクルのロック開始は 10/10 0:00
        let s = makeState(mode: .evening(lockStartMinute: 0),
                          achievements: [done("2026-10-08", at: t(2026, 10, 8, 20, 0))])
        let before = evaluate(s, t(2026, 10, 9, 23, 59))
        XCTAssertFalse(before.shouldLock)
        XCTAssertEqual(before.nextCheck, t(2026, 10, 10, 0, 0))
        let after = evaluate(s, t(2026, 10, 10, 0, 0))
        XCTAssertEqual(after.cycle, c("2026-10-09"))
        XCTAssertTrue(after.shouldLock)
    }

    // MARK: 緊急解除

    func testEmergencyWaitThenUnlockThenRelock() {
        let window = EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 10, 0, 30))
        XCTAssertEqual(window.startsAt, t(2026, 10, 9, 10, 16))
        XCTAssertEqual(window.endsAt, t(2026, 10, 9, 12, 16))
        let s = makeState(emergency: window)

        let waiting = evaluate(s, t(2026, 10, 9, 10, 10))
        XCTAssertTrue(waiting.shouldLock)
        XCTAssertEqual(waiting.emergencyStartsAt, t(2026, 10, 9, 10, 16))
        XCTAssertEqual(waiting.nextCheck, t(2026, 10, 9, 10, 16))

        let active = evaluate(s, t(2026, 10, 9, 10, 16))
        XCTAssertFalse(active.shouldLock)
        XCTAssertEqual(active.reason, .emergency(until: t(2026, 10, 9, 12, 16)))
        XCTAssertEqual(active.nextCheck, t(2026, 10, 9, 12, 16))
        XCTAssertFalse(active.canRelaxNow)   // 緊急解除中は緩める変更を受け付けない

        XCTAssertTrue(evaluate(s, t(2026, 10, 9, 12, 16)).shouldLock)
    }

    func testEmergencyContinuesAcrossCycleBoundary() {
        let window = EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 10, 3, 0))
        let s = makeState(emergency: window)
        let d = evaluate(s, t(2026, 10, 10, 4, 30))
        XCTAssertEqual(d.cycle, c("2026-10-10"))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .emergency(until: t(2026, 10, 10, 5, 15)))
    }

    func testCancelledEmergencyHasNoEffect() {
        var window = EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 10, 0))
        window.cancelledAt = t(2026, 10, 9, 10, 5)
        let d = evaluate(makeState(emergency: window), t(2026, 10, 9, 10, 20))
        XCTAssertTrue(d.shouldLock)
        XCTAssertNil(d.emergencyStartsAt)
    }

    // MARK: 休み・予定なし・複数コミット

    func testRestDayIsUnlocked() {
        let d = evaluate(makeState(restDays: [c("2026-10-09")]), t(2026, 10, 9, 10, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .restDay)
        XCTAssertTrue(d.canRelaxNow)
    }

    func testUnscheduledWeekdayIsUnlocked() {
        // 2026-10-09 は金曜(6)。月曜(2)だけのコミットなら今日は予定なし
        let s = makeState(habits: [study(weekdays: [2])])
        let d = evaluate(s, t(2026, 10, 9, 10, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .noCommitToday)
    }

    func testAllRequiredHabitsMustBeDone() {
        let run = HabitSnapshot(id: runID, title: "ランニング30分", activeFrom: c("2026-10-01"))
        let optional = HabitSnapshot(id: optionalID, title: "日記", isRequired: false, activeFrom: c("2026-10-01"))
        var s = makeState(habits: [study(), run, optional],
                          achievements: [done("2026-10-09", at: t(2026, 10, 9, 9, 0))])
        XCTAssertTrue(evaluate(s, t(2026, 10, 9, 10, 0)).shouldLock)
        s.achievements.append(done("2026-10-09", runID, at: t(2026, 10, 9, 9, 30)))
        XCTAssertFalse(evaluate(s, t(2026, 10, 9, 10, 0)).shouldLock)   // 任意の「日記」は不要
    }

    func testHabitStartingInFutureIsNotRequiredYet() {
        let s = makeState(habits: [study(from: "2026-10-10")])
        XCTAssertEqual(evaluate(s, t(2026, 10, 9, 10, 0)).reason, .noCommitToday)
        XCTAssertTrue(evaluate(s, t(2026, 10, 10, 10, 0)).shouldLock)
    }

    // MARK: 達成の状態

    func testMinimumCounts() {
        let s = makeState(achievements: [done("2026-10-09", at: t(2026, 10, 9, 9, 0), kind: .minimum)])
        XCTAssertFalse(evaluate(s, t(2026, 10, 9, 10, 0)).shouldLock)
    }

    func testOnlyConfirmedAndPendingReviewCount() {
        let now = t(2026, 10, 9, 10, 0)
        let at = t(2026, 10, 9, 9, 0)
        XCTAssertFalse(evaluate(makeState(achievements: [done("2026-10-09", at: at, status: .pendingReview)]), now).shouldLock)
        XCTAssertTrue(evaluate(makeState(achievements: [done("2026-10-09", at: at, status: .awaitingApproval)]), now).shouldLock)
        XCTAssertTrue(evaluate(makeState(achievements: [done("2026-10-09", at: at, status: .rejected)]), now).shouldLock)
        XCTAssertTrue(evaluate(makeState(achievements: [done("2026-10-09", at: at, status: .undone)]), now).shouldLock)
    }

    func testInboxAchievementUnlocksBeforeAppIngestsIt() {
        let fromMonitor = done("2026-10-09", at: t(2026, 10, 9, 9, 0))
        XCTAssertFalse(evaluate(makeState(), t(2026, 10, 9, 10, 0), extra: [fromMonitor]).shouldLock)
    }

    func testStateWinsOverInboxForSameAchievement() {
        let id = UUID()
        let rejected = done("2026-10-09", at: t(2026, 10, 9, 9, 0), status: .rejected, id: id)
        let stale = done("2026-10-09", at: t(2026, 10, 9, 9, 0), status: .confirmed, id: id)
        XCTAssertTrue(evaluate(makeState(achievements: [rejected]), t(2026, 10, 9, 10, 0), extra: [stale]).shouldLock)
    }

    // MARK: 稼働型

    func testEarnModeWindows() {
        var s = makeState(mode: .earn(windowMinutes: 180))
        let first = evaluate(s, t(2026, 10, 9, 9, 0))
        XCTAssertTrue(first.shouldLock)
        XCTAssertEqual(first.reason, .awaitingCommit)

        s.achievements = [done("2026-10-09", at: t(2026, 10, 9, 10, 0), grants: 180)]
        let inside = evaluate(s, t(2026, 10, 9, 12, 59))
        XCTAssertFalse(inside.shouldLock)
        XCTAssertEqual(inside.reason, .earnWindowActive(until: t(2026, 10, 9, 13, 0)))
        XCTAssertEqual(inside.nextCheck, t(2026, 10, 9, 13, 0))
        XCTAssertTrue(inside.todaySatisfied)   // ストリーク上は今日は達成

        let expired = evaluate(s, t(2026, 10, 9, 13, 0))
        XCTAssertTrue(expired.shouldLock)
        XCTAssertEqual(expired.reason, .earnWindowExpired)
    }

    func testEarnWindowCarriesAcrossCycleBoundary() {
        let s = makeState(mode: .earn(windowMinutes: 180),
                          achievements: [done("2026-10-08", at: t(2026, 10, 9, 3, 30), grants: 180)])
        let d = evaluate(s, t(2026, 10, 9, 5, 0))
        XCTAssertEqual(d.cycle, c("2026-10-09"))
        XCTAssertFalse(d.shouldLock)
    }

    // MARK: 一時停止・見守り・開始前

    func testPauseWinsAndReportsItsEnd() {
        let s = makeState(pauses: [PausePeriod(start: t(2026, 10, 9, 9, 0), end: t(2026, 10, 9, 15, 0))])
        let d = evaluate(s, t(2026, 10, 9, 10, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .paused)
        XCTAssertEqual(d.nextCheck, t(2026, 10, 9, 15, 0))
        XCTAssertTrue(evaluate(s, t(2026, 10, 9, 15, 0)).shouldLock)
    }

    func testMonitorOnlyNeverLocks() {
        let d = evaluate(makeState(enforcement: .monitorOnly), t(2026, 10, 9, 10, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .monitorOnly)
    }

    func testNotStartedBeforeActiveSince() {
        let s = makeState(activeSince: c("2026-10-10"))
        let d = evaluate(s, t(2026, 10, 9, 10, 0))
        XCTAssertFalse(d.shouldLock)
        XCTAssertEqual(d.reason, .notStarted)
        XCTAssertEqual(d.nextCheck, t(2026, 10, 10, 4, 0))
        XCTAssertTrue(evaluate(s, t(2026, 10, 10, 4, 0)).shouldLock)
    }

    // MARK: 性質テスト:どの時刻でも判定は自己矛盾しない

    func testDecisionIsStableUntilNextCheck() {
        // nextCheck の手前までは同じ結論が続く(ウィジェットのタイムラインや本体のタイマーを正しく作れること)
        let emergencyRequest = t(2026, 10, 9, 13, 7, 12)
        let cases: [(SharedState, Date)] = [
            (makeState(), t(2026, 10, 9, 0, 0)),
            (makeState(mode: .evening(lockStartMinute: 21 * 60),
                       achievements: [done("2026-10-08", at: t(2026, 10, 8, 20, 0))]), t(2026, 10, 9, 0, 0)),
            (makeState(mode: .evening(lockStartMinute: 0)), t(2026, 10, 9, 0, 0)),
            (makeState(mode: .earn(windowMinutes: 120),
                       achievements: [done("2026-10-09", at: t(2026, 10, 9, 11, 0), grants: 120)]), t(2026, 10, 9, 11, 0)),
            (makeState(emergency: EmergencyPolicy.makeWindow(requestedAt: emergencyRequest)), emergencyRequest),
            (makeState(pauses: [PausePeriod(start: t(2026, 10, 9, 0, 0), end: t(2026, 10, 9, 18, 30))]), t(2026, 10, 9, 0, 0)),
        ]
        for (s, start) in cases {
            var now = start
            let end = start.addingTimeInterval(48 * 3600)
            while now < end {
                let d = evaluate(s, now)
                guard let next = d.nextCheck else { XCTFail("nextCheck missing"); break }
                XCTAssertGreaterThan(next, now)
                var probe = now.addingTimeInterval(7 * 60)
                while probe < next {
                    XCTAssertEqual(evaluate(s, probe).shouldLock, d.shouldLock,
                                   "decision changed at \(probe) before nextCheck \(next)")
                    probe = probe.addingTimeInterval(7 * 60)
                }
                now = now.addingTimeInterval(37 * 60)   // 半端な刻みで走査
            }
        }
    }
}
