import XCTest
@testable import GoukakuCore

final class DepositTests: XCTestCase {
    let cal = CycleCalendar(dayStartMinute: 240, timeZone: tokyo)

    func testPlanIsSevenCyclesFromTheGivenDay() {
        let days = DepositRules.plan(startingAt: c("2026-10-12"), calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.key), ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15",
                                         "2026-10-16", "2026-10-17", "2026-10-18"])
        XCTAssertEqual(days[0].startsAt, t(2026, 10, 12, 4, 0))
        XCTAssertEqual(days[0].endsAt, t(2026, 10, 13, 4, 0))
        XCTAssertEqual(days[6].endsAt, t(2026, 10, 19, 4, 0))
        for (a, b) in zip(days, days.dropFirst()) { XCTAssertEqual(a.endsAt, b.startsAt) }
        XCTAssertEqual(days[3].cycle, c("2026-10-15"))
        // 月をまたぐ
        XCTAssertEqual(DepositRules.plan(startingAt: c("2026-10-29"), calendar: cal).last?.key, "2026-11-04")
    }

    func testRefundableOutcomesFollowTheAppJudgement() {
        for o: CycleOutcome in [.achieved, .minimum, .pendingReview, .rest, .noCommit, .notStarted] {
            XCTAssertTrue(DepositRules.isRefundable(o), o.rawValue)
        }
        for o: CycleOutcome in [.paused, .missed, .inProgress] {
            XCTAssertFalse(DepositRules.isRefundable(o), o.rawValue)
        }
    }

    func testAchievementIsFinalAfterTheUndoWindowOrTheDayEnd() {
        let end = t(2026, 10, 13, 4, 0)
        let checkIn = t(2026, 10, 12, 20, 0)
        // 取り消せるあいだは、まだ知らせない
        XCTAssertFalse(DepositRules.isFinal(outcome: .achieved, cycleEnd: end, lastCheckIn: checkIn,
                                            now: checkIn.addingTimeInterval(60)))
        XCTAssertTrue(DepositRules.isFinal(outcome: .achieved, cycleEnd: end, lastCheckIn: checkIn,
                                           now: checkIn.addingTimeInterval(5 * 60)))
        XCTAssertTrue(DepositRules.isFinal(outcome: .minimum, cycleEnd: end, lastCheckIn: checkIn,
                                           now: checkIn.addingTimeInterval(10 * 60)))
        // 休養日・予定のない日は、日付が変わってから
        XCTAssertFalse(DepositRules.isFinal(outcome: .rest, cycleEnd: end, lastCheckIn: nil, now: t(2026, 10, 12, 23, 0)))
        XCTAssertTrue(DepositRules.isFinal(outcome: .rest, cycleEnd: end, lastCheckIn: nil, now: end))
        XCTAssertFalse(DepositRules.isFinal(outcome: .achieved, cycleEnd: end, lastCheckIn: nil, now: t(2026, 10, 12, 23, 0)))
        XCTAssertFalse(DepositRules.isFinal(outcome: .inProgress, cycleEnd: end, lastCheckIn: nil, now: end))

        XCTAssertTrue(DepositRules.shouldReport(outcome: .achieved, cycleEnd: end, lastCheckIn: checkIn,
                                                alreadyRefunded: false, now: end))
        XCTAssertFalse(DepositRules.shouldReport(outcome: .achieved, cycleEnd: end, lastCheckIn: checkIn,
                                                 alreadyRefunded: true, now: end), "二度は頼まない")
        XCTAssertFalse(DepositRules.shouldReport(outcome: .missed, cycleEnd: end, lastCheckIn: nil,
                                                 alreadyRefunded: false, now: end))
        XCTAssertFalse(DepositRules.shouldReport(outcome: .paused, cycleEnd: end, lastCheckIn: nil,
                                                 alreadyRefunded: false, now: end))
    }

    func testMarksAndBreakdown() {
        let days = DepositRules.plan(startingAt: c("2026-10-12"), calendar: cal)
        let now = t(2026, 10, 15, 12, 0)   // 4日目の昼
        let outcomes: [CycleOutcome?] = [.achieved, .missed, .rest, .inProgress, nil, nil, nil]
        let refunded = [true, false, false, false, false, false, false]
        let marks = days.indices.map { i in
            DepositRules.mark(startsAt: days[i].startsAt, endsAt: days[i].endsAt, refunded: refunded[i],
                              outcome: outcomes[i], now: now)
        }
        XCTAssertEqual(marks, [.returned, .kept, .returning, .today, .upcoming, .upcoming, .upcoming])
        let b = DepositBreakdown.make(marks: marks, daily: 300)
        XCTAssertEqual(b, DepositBreakdown(returned: 300, returning: 300, kept: 300, open: 1200))
        XCTAssertEqual(b.returned + b.returning + b.kept + b.open, 2100)
        // 今日でも達成していれば「返ってくる」。一時停止の今日は、まだ決まっていない
        XCTAssertEqual(DepositRules.mark(startsAt: days[3].startsAt, endsAt: days[3].endsAt, refunded: false,
                                         outcome: .achieved, now: now), .returning)
        XCTAssertEqual(DepositRules.mark(startsAt: days[3].startsAt, endsAt: days[3].endsAt, refunded: false,
                                         outcome: .paused, now: now), .today)
        XCTAssertEqual(DepositRules.mark(startsAt: days[1].startsAt, endsAt: days[1].endsAt, refunded: false,
                                         outcome: .paused, now: now), .kept)
        // 返金の額はサーバーの記録を優先(最後の日だけ端数のとき)
        XCTAssertEqual(DepositBreakdown.make(marks: [.returned, .returned], daily: 300, refundedAmounts: [300, 100]).returned, 400)
    }
}
