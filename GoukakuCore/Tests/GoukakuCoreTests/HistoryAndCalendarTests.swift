import XCTest
@testable import GoukakuCore

final class CycleCalendarTests: XCTestCase {
    let cal = CycleCalendar(dayStartMinute: 240, timeZone: tokyo)

    func testBoundary() {
        XCTAssertEqual(cal.cycle(containing: t(2026, 10, 10, 3, 59, 59)), c("2026-10-09"))
        XCTAssertEqual(cal.cycle(containing: t(2026, 10, 10, 4, 0)), c("2026-10-10"))
        XCTAssertEqual(cal.start(of: c("2026-10-09")), t(2026, 10, 9, 4, 0))
        XCTAssertEqual(cal.end(of: c("2026-10-09")), t(2026, 10, 10, 4, 0))
    }

    func testMidnightDayStart() {
        let midnight = CycleCalendar(dayStartMinute: 0, timeZone: tokyo)
        XCTAssertEqual(midnight.cycle(containing: t(2026, 10, 9, 23, 59)), c("2026-10-09"))
        XCTAssertEqual(midnight.cycle(containing: t(2026, 10, 10, 0, 0)), c("2026-10-10"))
    }

    func testWeekdayAndWeekStart() {
        XCTAssertEqual(cal.weekday(of: c("2026-10-09")), 6)            // 金曜
        XCTAssertEqual(cal.weekStart(of: c("2026-10-09")), c("2026-10-05"))  // 月曜
        XCTAssertEqual(cal.weekStart(of: c("2026-10-11")), c("2026-10-05"))  // 日曜は同じ週の終わり
        XCTAssertEqual(cal.weekStart(of: c("2026-10-12")), c("2026-10-12"))
    }

    func testOffsetsAcrossMonthAndYear() {
        XCTAssertEqual(cal.cycle(c("2026-12-31"), offsetBy: 1), c("2027-01-01"))
        XCTAssertEqual(cal.cycle(c("2027-03-01"), offsetBy: -1), c("2027-02-28"))
    }

    func testMinuteOfDayInsideCycle() {
        XCTAssertEqual(cal.date(minuteOfDay: 21 * 60, in: c("2026-10-09")), t(2026, 10, 9, 21, 0))
        XCTAssertEqual(cal.date(minuteOfDay: 0, in: c("2026-10-09")), t(2026, 10, 10, 0, 0))
        XCTAssertEqual(cal.date(minuteOfDay: 3 * 60 + 30, in: c("2026-10-09")), t(2026, 10, 10, 3, 30))
    }

    func testCycleIDCoding() throws {
        let id = c("2026-10-09")
        let data = try JSONEncoder().encode([id])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-10-09\"]")
        XCTAssertEqual(try JSONDecoder().decode([CycleID].self, from: data), [id])
        XCTAssertNil(CycleID("2026-13-01"))
        XCTAssertNil(CycleID("20261009"))
    }

    func testEveryInstantBelongsToExactlyOneCycleEvenAcrossDST() {
        // 夏時間のある地域・すべての日付切替で「start ≦ t < end」が成り立つこと
        let zones = [tokyo, TimeZone(identifier: "America/New_York")!, TimeZone(identifier: "Europe/London")!]
        for zone in zones {
            for dayStart in stride(from: 0, through: 360, by: 30) {
                let cc = CycleCalendar(dayStartMinute: dayStart, timeZone: zone)
                var instant = t(2026, 3, 6, 0, 0, tz: zone)
                let stop = t(2026, 3, 31, 0, 0, tz: zone)
                while instant < stop {
                    let cycle = cc.cycle(containing: instant)
                    XCTAssertLessThanOrEqual(cc.start(of: cycle), instant, "\(zone.identifier) \(dayStart) \(instant)")
                    XCTAssertLessThan(instant, cc.end(of: cycle), "\(zone.identifier) \(dayStart) \(instant)")
                    instant = instant.addingTimeInterval(23 * 60)
                }
            }
        }
    }
}

final class HistoryTests: XCTestCase {
    let now = t(2026, 10, 9, 10, 0)

    func outcome(_ s: SharedState, _ cycle: String) -> CycleOutcome {
        History.outcome(of: c(cycle), state: s, now: now, timeZone: tokyo)
    }

    func testOutcomes() {
        let s = makeState(
            achievements: [
                done("2026-10-03", at: t(2026, 10, 3, 9, 0)),
                done("2026-10-04", at: t(2026, 10, 4, 9, 0), kind: .minimum),
                done("2026-10-05", at: t(2026, 10, 5, 9, 0), status: .pendingReview),
                done("2026-10-06", at: t(2026, 10, 6, 9, 0), status: .rejected),
            ],
            restDays: [c("2026-10-07")],
            pauses: [PausePeriod(start: t(2026, 10, 8, 10, 0), end: t(2026, 10, 8, 11, 0))])
        XCTAssertEqual(outcome(s, "2026-09-30"), .notStarted)
        XCTAssertEqual(outcome(s, "2026-10-02"), .missed)
        XCTAssertEqual(outcome(s, "2026-10-03"), .achieved)
        XCTAssertEqual(outcome(s, "2026-10-04"), .minimum)
        XCTAssertEqual(outcome(s, "2026-10-05"), .pendingReview)
        XCTAssertEqual(outcome(s, "2026-10-06"), .missed)      // 却下は未達成
        XCTAssertEqual(outcome(s, "2026-10-07"), .rest)
        XCTAssertEqual(outcome(s, "2026-10-08"), .paused)
        XCTAssertEqual(outcome(s, "2026-10-09"), .inProgress)
    }

    func testNoCommitOutcome() {
        let s = makeState(habits: [study(weekdays: [2])])   // 月曜だけ
        XCTAssertEqual(outcome(s, "2026-10-09"), .noCommit)  // 金曜
    }

    func testStreak() {
        XCTAssertEqual(History.currentStreak(newestFirst: [.inProgress, .achieved, .rest, .minimum, .missed, .achieved]), 2)
        XCTAssertEqual(History.currentStreak(newestFirst: [.achieved, .noCommit, .pendingReview, .achieved, .paused, .achieved]), 3)
        XCTAssertEqual(History.currentStreak(newestFirst: [.missed, .achieved]), 0)
        XCTAssertEqual(History.currentStreak(newestFirst: [.achieved, .achieved, .notStarted, .achieved]), 2)
        XCTAssertEqual(History.totalAchieved([.achieved, .missed, .minimum, .rest, .pendingReview]), 3)
    }
}
