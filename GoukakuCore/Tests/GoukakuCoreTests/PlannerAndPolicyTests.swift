import XCTest
@testable import GoukakuCore

final class SchedulePlannerTests: XCTestCase {

    func testEveryValidConfigProducesSafeIntervals() {
        var checked = 0
        for dayStart in stride(from: 0, through: 360, by: 30) {
            XCTAssertTrue(SchedulePlanner.isValidDayStart(dayStart))
            var modes: [LockMode] = [.morning, .earn(windowMinutes: 180)]
            for lockStart in stride(from: 0, to: 1440, by: 30)
            where SchedulePlanner.isValidLockStart(lockStart, dayStartMinute: dayStart) {
                modes.append(.evening(lockStartMinute: lockStart))
            }
            for mode in modes {
                let config = ScheduleConfig(dayStartMinute: dayStart, mode: mode)
                XCTAssertTrue(SchedulePlanner.isValid(config))
                let plans = SchedulePlanner.plans(for: config)
                XCTAssertLessThanOrEqual(plans.count, 2)
                for plan in plans {
                    XCTAssertLessThan(plan.startMinute, plan.endMinute, "\(config)")           // 0:00 をまたがない
                    XCTAssertGreaterThanOrEqual(plan.lengthMinutes, SchedulePlanner.minimumIntervalMinutes, "\(config)")
                    XCTAssertLessThanOrEqual(plan.endMinute, SchedulePlanner.lastMinuteOfDay)
                    checked += 1
                }
                // 夕方型のロック区間は、そのサイクルの終わりを越えない
                if case .evening(let ls) = mode, let p = plans.first(where: { $0.name == .lockStart }) {
                    XCTAssertEqual(p.startMinute, ls)
                    if ls < dayStart { XCTAssertEqual(p.endMinute, dayStart - 1) }
                }
            }
        }
        XCTAssertGreaterThan(checked, 500)
    }

    func testInvalidValuesAreRejected() {
        XCTAssertFalse(SchedulePlanner.isValidDayStart(390))      // 6:30
        XCTAssertFalse(SchedulePlanner.isValidDayStart(245))      // 30分刻みでない
        XCTAssertFalse(SchedulePlanner.isValidLockStart(240, dayStartMinute: 240))   // 日付切替と同じ=朝型を使う
        XCTAssertFalse(SchedulePlanner.isValidLockStart(30, dayStartMinute: 240))    // 20時間30分後
        XCTAssertTrue(SchedulePlanner.isValidLockStart(0, dayStartMinute: 240))      // ちょうど20時間後
        XCTAssertTrue(SchedulePlanner.isValidLockStart(1200, dayStartMinute: 0))     // 0:00切替なら20:00まで
        XCTAssertFalse(SchedulePlanner.isValidLockStart(1230, dayStartMinute: 0))
        XCTAssertFalse(SchedulePlanner.isValidEarnWindow(20))
        XCTAssertFalse(SchedulePlanner.isValidEarnWindow(390))
    }
}

final class PolicyTests: XCTestCase {

    func testEmergencyRounding() {
        let exact = EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 10, 0, 0))
        XCTAssertEqual(exact.startsAt, t(2026, 10, 9, 10, 15))
        XCTAssertEqual(exact.endsAt, t(2026, 10, 9, 12, 15))
        let late = EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 10, 0, 1))
        XCTAssertEqual(late.startsAt, t(2026, 10, 9, 10, 16))
    }

    func testEmergencyCanRequest() {
        let w = EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 10, 0))
        XCTAssertTrue(EmergencyPolicy.canRequest(existing: nil, now: t(2026, 10, 9, 10, 0)))
        XCTAssertFalse(EmergencyPolicy.canRequest(existing: w, now: t(2026, 10, 9, 10, 5)))    // 待機中
        XCTAssertFalse(EmergencyPolicy.canRequest(existing: w, now: t(2026, 10, 9, 11, 0)))    // 解除中
        XCTAssertTrue(EmergencyPolicy.canRequest(existing: w, now: t(2026, 10, 9, 12, 15)))    // 終了後
        var cancelled = w
        cancelled.cancelledAt = t(2026, 10, 9, 10, 3)
        XCTAssertTrue(EmergencyPolicy.canRequest(existing: cancelled, now: t(2026, 10, 9, 10, 5)))
    }

    let locked = ChangeContext(canRelaxNow: false, hasReferee: false, isPaused: false)
    let achieved = ChangeContext(canRelaxNow: true, hasReferee: false, isPaused: false)
    let withReferee = ChangeContext(canRelaxNow: true, hasReferee: true, isPaused: false)
    let paused = ChangeContext(canRelaxNow: true, hasReferee: true, isPaused: true)

    func testRelaxingChanges() {
        XCTAssertEqual(ChangePolicy.acceptance(for: .lockTargetsRemoved, context: locked), .rejected(.lockedNow))
        XCTAssertEqual(ChangePolicy.acceptance(for: .lockTargetsRemoved, context: achieved), .applyFromNextCycle)
        XCTAssertEqual(ChangePolicy.acceptance(for: .lockTargetsRemoved, context: withReferee), .requiresRefereeApproval)
        XCTAssertEqual(ChangePolicy.acceptance(for: .lockTargetsRemoved, context: paused), .applyNow)
        XCTAssertEqual(ChangePolicy.acceptance(for: .allowTargetsAdded, context: locked), .rejected(.lockedNow))
        XCTAssertEqual(ChangePolicy.acceptance(for: .habitTextEdited, context: locked), .rejected(.lockedNow))
    }

    func testTighteningChanges() {
        XCTAssertEqual(ChangePolicy.acceptance(for: .lockTargetsAdded, context: locked), .applyNow)
        XCTAssertEqual(ChangePolicy.acceptance(for: .habitAdded, context: locked), .applyFromNextCycle)
        XCTAssertEqual(ChangePolicy.acceptance(for: .inAppPurchaseBlockChanged(to: true), context: locked), .applyNow)
        XCTAssertEqual(ChangePolicy.acceptance(for: .enforcementChanged(to: .lock), context: locked), .applyNow)
        XCTAssertEqual(ChangePolicy.acceptance(for: .notificationSettings, context: locked), .applyNow)
    }

    func testDayStartOnlyWhilePaused() {
        XCTAssertEqual(ChangePolicy.acceptance(for: .dayStartChanged, context: achieved), .rejected(.requiresPause))
        XCTAssertEqual(ChangePolicy.acceptance(for: .dayStartChanged, context: paused), .applyNow)
    }

    func testDirections() {
        XCTAssertEqual(ChangePolicy.direction(of: .methodChanged(from: .selfReport, to: .photo)), .tighten)
        XCTAssertEqual(ChangePolicy.direction(of: .methodChanged(from: .timer, to: .photo)), .relax)   // 同じ段階は緩める扱い
        XCTAssertEqual(ChangePolicy.direction(of: .methodChanged(from: .referee, to: .timer)), .relax)
        // 日付切替 4:00:23:00 → 0:30 は「遅らせる」(0:00 をまたいでも正しく比べる)
        XCTAssertEqual(ChangePolicy.direction(of: .lockStartMoved(fromMinute: 23 * 60, toMinute: 30, dayStartMinute: 240)), .relax)
        XCTAssertEqual(ChangePolicy.direction(of: .lockStartMoved(fromMinute: 30, toMinute: 23 * 60, dayStartMinute: 240)), .tighten)
        XCTAssertEqual(ChangePolicy.direction(of: .modeChanged(from: .morning, to: .evening(lockStartMinute: 1260), dayStartMinute: 240)), .relax)
        XCTAssertEqual(ChangePolicy.direction(of: .modeChanged(from: .evening(lockStartMinute: 1260), to: .morning, dayStartMinute: 240)), .tighten)
        XCTAssertEqual(ChangePolicy.direction(of: .modeChanged(from: .morning, to: .earn(windowMinutes: 180), dayStartMinute: 240)), .tighten)
        XCTAssertEqual(ChangePolicy.direction(of: .modeChanged(from: .earn(windowMinutes: 180), to: .earn(windowMinutes: 120), dayStartMinute: 240)), .tighten)
        XCTAssertEqual(ChangePolicy.direction(of: .habitWeekdaysChanged(added: 1, removed: 1)), .relax)
        XCTAssertEqual(ChangePolicy.direction(of: .minimumQuotaChanged(from: 2, to: 1)), .tighten)
        XCTAssertEqual(ChangePolicy.direction(of: .restQuotaChanged(from: 1, to: 2)), .relax)
    }

    func testRestDayRules() {
        let today = c("2026-10-09")
        XCTAssertEqual(ChangePolicy.restDayAcceptance(day: today, current: today, canRelaxNow: true,
                                                      usedInThatWeek: 0, weeklyQuota: 1, isPaused: false), .rejected(.notInFuture))
        XCTAssertEqual(ChangePolicy.restDayAcceptance(day: c("2026-10-10"), current: today, canRelaxNow: true,
                                                      usedInThatWeek: 1, weeklyQuota: 1, isPaused: false), .rejected(.quotaExceeded))
        XCTAssertEqual(ChangePolicy.restDayAcceptance(day: c("2026-10-10"), current: today, canRelaxNow: false,
                                                      usedInThatWeek: 0, weeklyQuota: 1, isPaused: false), .rejected(.lockedNow))
        XCTAssertEqual(ChangePolicy.restDayAcceptance(day: c("2026-10-10"), current: today, canRelaxNow: true,
                                                      usedInThatWeek: 0, weeklyQuota: 1, isPaused: false), .applyNow)
        XCTAssertTrue(ChangePolicy.canUseMinimum(usedThisWeek: 1, weeklyQuota: 2))
        XCTAssertFalse(ChangePolicy.canUseMinimum(usedThisWeek: 2, weeklyQuota: 2))
    }

    func testTamperDetector() {
        let a = ClockAnchor(wall: t(2026, 10, 9, 10, 0), monotonicNanos: 1_000_000_000_000, bootSessionID: "boot-1")
        let honest = ClockAnchor(wall: t(2026, 10, 9, 11, 0), monotonicNanos: 1_000_000_000_000 + 3_600_000_000_000, bootSessionID: "boot-1")
        XCTAssertNil(TamperDetector.clockSkew(from: a, to: honest))
        let back = ClockAnchor(wall: t(2026, 10, 9, 9, 0), monotonicNanos: 1_000_000_000_000 + 3_600_000_000_000, bootSessionID: "boot-1")
        XCTAssertEqual(TamperDetector.clockSkew(from: a, to: back)!, -7200, accuracy: 1)
        let rebooted = ClockAnchor(wall: t(2026, 10, 9, 9, 0), monotonicNanos: 5, bootSessionID: "boot-2")
        XCTAssertNil(TamperDetector.clockSkew(from: a, to: rebooted))
    }
}

final class SharedStateStoreTests: XCTestCase {

    func testRoundTripAndInbox() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SharedStateStore(directory: dir)

        XCTAssertNil(try store.load())
        let state = makeState(mode: .evening(lockStartMinute: 1260),
                              achievements: [done("2026-10-09", at: t(2026, 10, 9, 9, 0))],
                              restDays: [c("2026-10-12")],
                              emergency: EmergencyPolicy.makeWindow(requestedAt: t(2026, 10, 9, 10, 0)),
                              pauses: [PausePeriod(start: t(2026, 10, 1, 0, 0))])
        try store.save(state)
        XCTAssertEqual(try store.load(), state)

        let fromMonitor = done("2026-10-10", at: t(2026, 10, 10, 9, 0))
        try store.appendInbox(.achievement(fromMonitor), now: t(2026, 10, 10, 9, 0))
        try store.appendInbox(.log(LogEntry(at: t(2026, 10, 10, 9, 1), kind: "lockApplied", detail: "cycleMain")),
                              now: t(2026, 10, 10, 9, 1))
        try Data("broken".utf8).write(to: store.inboxURL.appendingPathComponent("achievements/0-broken.json"))

        let inbox = store.readInbox()
        XCTAssertEqual(inbox.count, 2)                       // 壊れたファイルは飛ばす
        XCTAssertEqual(store.pendingAchievements(), [fromMonitor])
        store.removeInbox(inbox.map(\.url))
        XCTAssertTrue(store.pendingAchievements().isEmpty)
    }

    func testBackupRecoversCorruptedState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SharedStateStore(directory: dir)
        let first = makeState()
        let second = makeState(mode: .evening(lockStartMinute: 1260))
        try store.save(first)
        try store.save(second)
        XCTAssertEqual(try store.loadBackup(), first)
        try Data("{broken".utf8).write(to: store.stateURL)
        XCTAssertThrowsError(try store.load())              // 拡張はここで何もしない
        XCTAssertEqual(try store.loadBackup(), first)       // 本体はここから復旧する
        try store.save(second)                              // 壊れた state.json でバックアップを上書きしない
        XCTAssertEqual(try store.loadBackup(), first)
    }

    func testLogCapKeepsInboxSmall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SharedStateStore(directory: dir)
        for i in 0..<(SharedStateStore.logCap + 5) {
            try store.appendInbox(.log(LogEntry(at: t(2026, 10, 9, 10, 0), kind: "x", detail: "\(i)")),
                                  now: t(2026, 10, 9, 10, 0).addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(store.readInbox().count, SharedStateStore.logCap)
        // 達成は上限に関係なく必ず書ける
        XCTAssertNotNil(try store.appendInbox(.achievement(done("2026-10-09", at: t(2026, 10, 9, 11, 0)))))
    }
}
