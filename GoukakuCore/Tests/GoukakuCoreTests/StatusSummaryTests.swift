import XCTest
@testable import GoukakuCore

final class StatusSummaryTests: XCTestCase {
    let tz = TimeZone(identifier: "Asia/Tokyo")!
    func date(_ s: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    func makeState(mode: LockMode = .morning, achievements: [Achievement] = []) -> (SharedState, HabitSnapshot) {
        let habit = HabitSnapshot(title: "英単語20個を覚えて、自作テストで7割", minimumTitle: "単語5個", activeFrom: CycleID("2026-10-01")!)
        let state = SharedState(schedule: ScheduleConfig(dayStartMinute: 240, mode: mode), enforcementChangedAt: date("2026-10-01 00:00"),
                                activeSince: CycleID("2026-10-01")!, habits: [habit], achievements: achievements, updatedAt: date("2026-10-01 00:00"))
        return (state, habit)
    }
    func testAwaitingCommit() {
        let (state, _) = makeState()
        let s = StatusSummary.make(state: state, now: date("2026-10-09 13:00"), timeZone: tz)
        XCTAssertEqual(s.seal, "未"); XCTAssertTrue(s.shouldLock); XCTAssertEqual(s.tone, .locked)
        XCTAssertEqual(s.headline, "今日の「英単語20個を覚えて、自作テストで7割」がまだです")
        XCTAssertEqual(s.shortHeadline, "「英単語20個を覚え…」がまだ")
        XCTAssertEqual(s.countdownTo, date("2026-10-10 04:00")); XCTAssertEqual(s.countdownLabel, "切り替えまで")
        XCTAssertTrue(s.detail!.contains("切り替え:明日 4:00"), s.detail!)
        XCTAssertEqual(s.required.count, 1); XCTAssertEqual(s.doneCount, 0)
    }
    func testAchieved() {
        var (state, habit) = makeState()
        state.achievements = [Achievement(cycle: CycleID("2026-10-09")!, habitID: habit.id, at: date("2026-10-09 12:00"))]
        let s = StatusSummary.make(state: state, now: date("2026-10-09 13:00"), timeZone: tz)
        XCTAssertEqual(s.seal, "合格"); XCTAssertFalse(s.shouldLock)
        XCTAssertEqual(s.headline, "今日は達成。明日 4:00 まで使えます")
        XCTAssertEqual(s.doneCount, 1); XCTAssertFalse(s.required[0].minimum)
    }
    func testEveningGraceAndEmergency() {
        var (state, habit) = makeState(mode: .evening(lockStartMinute: 21 * 60))
        state.achievements = [Achievement(cycle: CycleID("2026-10-08")!, habitID: habit.id, at: date("2026-10-08 20:00"))]
        var s = StatusSummary.make(state: state, now: date("2026-10-09 13:00"), timeZone: tz)
        XCTAssertEqual(s.seal, "猶"); XCTAssertEqual(s.shortHeadline, "21:00 からロック")
        XCTAssertEqual(s.countdownTo, date("2026-10-09 21:00"))
        state.emergency = EmergencyPolicy.makeWindow(requestedAt: date("2026-10-09 22:00"))
        s = StatusSummary.make(state: state, now: date("2026-10-09 22:01"), timeZone: tz)
        XCTAssertTrue(s.shouldLock); XCTAssertEqual(s.countdownLabel, "緊急解除まで")
        XCTAssertEqual(s.countdownTo, date("2026-10-09 22:15"))
        s = StatusSummary.make(state: state, now: date("2026-10-09 23:00"), timeZone: tz)
        XCTAssertEqual(s.seal, "急"); XCTAssertFalse(s.shouldLock)
    }

    func testClockText() {
        let cal = ClockText.calendar(timeZone: tz)
        let now = date("2026-10-09 13:00")
        XCTAssertEqual(ClockText.relative(date("2026-10-09 21:00"), now: now, calendar: cal), "今日 21:00")
        XCTAssertEqual(ClockText.relative(date("2026-10-10 04:00"), now: now, calendar: cal), "明日 4:00")
        XCTAssertEqual(ClockText.relative(date("2026-10-08 09:05"), now: now, calendar: cal), "昨日 9:05")
        XCTAssertEqual(ClockText.relative(date("2026-10-12 04:00"), now: now, calendar: cal), "10/12 4:00")
        XCTAssertEqual(ClockText.duration(minutes: 90), "1時間30分")
        XCTAssertEqual(ClockText.hm(minuteOfDay: 1500), "1:00")
        XCTAssertEqual(ClockText.short("あいうえお", limit: 5), "あいうえお")
        XCTAssertEqual(ClockText.short("あいうえおか", limit: 5), "あいうえ…")
    }
}
