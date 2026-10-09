import Foundation
import SwiftData
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications
import GoukakuCore
import GoukakuKit

/// はじめの設定で集める内容
struct OnboardingDraft {
    var targets = LockTargets()
    var confirmedSafety = false
    var dayStartMinute = 240
    var modeKind: LockMode.Kind = .morning
    var lockStartMinute = 21 * 60
    var denyInAppPurchases = true
    var habit = HabitDraft()
    var startNow = false

    var schedule: ScheduleConfig {
        ScheduleConfig(dayStartMinute: dayStartMinute,
                       mode: modeKind == .evening ? .evening(lockStartMinute: lockStartMinute) : .morning)
    }
}

/// 本体の操作(チェックイン・取り消し・緊急解除・一時停止・休養日・はじめの設定・全削除)
extension AppModel {
    // MARK: チェックイン

    /// 自己申告で達成を記録する。成功したら記録した達成を返す
    @discardableResult
    func checkIn(habit: HabitSnapshot, minimum: Bool, note: String) -> Achievement? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else {
            show("一言が短すぎます", "「やったこと」を5文字以上で書いてください。")
            return nil
        }
        if minimum && !canUseMinimum() {
            show("最小版の上限です", "最小版は週\(settings.minimumWeeklyQuota)回までです。")
            return nil
        }
        do {
            let achievement = try actions.checkIn(habitID: habit.id, kind: minimum ? .minimum : .full)
            let title = minimum ? (habit.minimumTitle ?? habit.title) : habit.title
            context.insert(CheckIn(achievement: achievement, habitTitle: title, method: habit.method, note: trimmed))
            log("checkin", "「\(habit.title)」\(minimum ? "を最小版で" : "を")達成")
            syncEmergencyRecord()
            save()
            reload()
            if decision?.todaySatisfied == true {
                log("unlock", "今日の必須コミットをすべて達成")
                save()
            }
            rebuildReminders()
            Task { await updateBadge() }
            return achievement
        } catch {
            show(error: error)
            return nil
        }
    }

    /// 押し間違いの取り消し(5分以内)
    @discardableResult
    func undoCheckIn(_ achievementID: UUID) -> Bool {
        do {
            try actions.undoCheckIn(id: achievementID)
            if let record = fetchAll(CheckIn.self).first(where: { $0.achievementID == achievementID }) {
                record.undoneAt = Date()
                log("undo", "「\(record.habitTitle)」のチェックインを取り消した")
            }
            save()
            reload()
            rebuildReminders()
            Task { await updateBadge() }
            return true
        } catch ActionError.undoWindowPassed {
            show("取り消せません", "記録から5分を過ぎたので取り消せません。")
        } catch {
            show(error: error)
        }
        return false
    }

    // MARK: 緊急解除(安全の床:いつでも・ひとりで使える)

    func requestEmergency() {
        do {
            var maker: ((Date) -> EmergencyWindow)?
            #if DEBUG
            if settings.debugShortEmergency { maker = AppModel.debugEmergencyWindow }
            #endif
            let window = try actions.requestEmergency(makeWindow: maker)
            context.insert(EmergencyRecord(window: window))
            log("emergency", "申請:\(Fmt.clock(window.startsAt)) から \(Fmt.clock(window.endsAt)) まで")
            save()
            reload()
        } catch ActionError.emergencyAlreadyRequested {
            show("申請済みです", "待機中・解除中は重ねて申請できません。")
        } catch {
            show(error: error)
        }
    }

    func cancelEmergency() {
        do {
            try actions.cancelEmergency()
            syncEmergencyRecord()
            log("emergency", "緊急解除を取り消した")
            save()
            reload()
        } catch {
            show(error: error)
        }
    }

    /// デバッグ用の短い緊急解除(待機1分・解除15分)
    nonisolated static func debugEmergencyWindow(_ now: Date) -> EmergencyWindow {
        let raw = now.addingTimeInterval(60)
        let start = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        return EmergencyWindow(requestedAt: now, startsAt: start, endsAt: start.addingTimeInterval(15 * 60))
    }

    // MARK: 一時停止(全体の非常口)

    @discardableResult
    func pause(until end: Date?) -> Bool {
        do {
            try actions.pause(until: end)
            log("pause", end.map { "一時停止(\(Fmt.dateTime($0)) まで)" } ?? "一時停止(無期限)")
            save()
            reload()
            rebuildReminders()
            Task { await updateBadge() }
            return true
        } catch ActionError.notAllowedWhileLocked {
            show("ロック中は一時停止できません", "緊急解除(15分後から2時間)でロックを外してから、一時停止してください。")
        } catch {
            show(error: error)
        }
        return false
    }

    func resume() {
        do {
            try actions.resume()
            log("pause", "再開")
            save()
            reload()
            rebuildReminders()
            Task { await updateBadge() }
        } catch {
            show(error: error)
        }
    }

    var activePause: PausePeriod? {
        let now = Date()
        return state?.pauses.first { $0.contains(now) }
    }

    // MARK: 休養日

    @discardableResult
    func addRestDay(_ day: CycleID) -> Bool {
        do {
            try actions.addRestDay(day, weeklyQuota: settings.restWeeklyQuota)
            log("rest", "休養日を追加:\(Fmt.cycle(day, dayStartMinute: cycleCalendar.dayStartMinute))")
            save()
            reload()
            rebuildReminders()
            return true
        } catch ActionError.rejected(let acceptance) {
            if case .rejected(let reason) = acceptance {
                show("休養日を置けません", reason.message)
            } else {
                show("休養日を置けません", "今は受け付けられません。")
            }
        } catch {
            show(error: error)
        }
        return false
    }

    func removeRestDay(_ day: CycleID) {
        do {
            try actions.removeRestDay(day)
            log("rest", "休養日を外した:\(Fmt.cycle(day, dayStartMinute: cycleCalendar.dayStartMinute))")
            _ = actions.reconcile(source: "restRemoved")
            save()
            reload()
            rebuildReminders()
        } catch {
            show(error: error)
        }
    }

    // MARK: はじめの設定

    /// 保存して始める。問題があれば理由を返す
    func completeOnboarding(_ draft: OnboardingDraft) -> String? {
        let config = draft.schedule
        guard SchedulePlanner.isValid(config) else { return "ロック開始の時刻が、選べる範囲の外です。" }
        let problems = draft.targets.problems
        guard problems.isEmpty else { return problems.joined(separator: "\n") }
        guard draft.confirmedSafety else { return "安全の確認にチェックしてください。" }
        let title = draft.habit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "最初のコミット(目標)を入力してください。" }
        guard !draft.habit.weekdays.isEmpty else { return "曜日を1つ以上選んでください。" }

        let cal = CycleCalendar(dayStartMinute: config.dayStartMinute)
        let now = Date()
        let current = cal.cycle(containing: now)
        let start = draft.startNow ? current : cal.cycle(current, offsetBy: 1)
        do {
            try TargetsStore.save(draft.targets, to: store.directory)
            settings.targetsRevision += 1
            let habit = Habit(title: title,
                              criteriaNote: draft.habit.criteriaNote.trimmingCharacters(in: .whitespacesAndNewlines),
                              minimumTitle: draft.habit.minimumTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                              weekdays: draft.habit.weekdays.sorted(), isRequired: true,
                              method: .selfReport, activeFrom: start, sortOrder: 0,
                              goalNote: draft.habit.goalNote, goalDate: draft.habit.goalDate)
            context.insert(habit)
            let state = SharedState(schedule: config, enforcement: .lock, enforcementChangedAt: now,
                                    activeSince: start, habits: [habit.snapshot],
                                    options: LockOptions(denyInAppPurchases: draft.denyInAppPurchases),
                                    updatedAt: now)
            try actions.createInitialState(state)
            settings.onboardingCompletedAt = now
            settings.lastFinalizedCycle = nil
            log("setup", "はじめの設定を保存(\(describe(config))・\(draft.startNow ? "今すぐ" : "明日の日付切替から")開始)")
            save()
        } catch {
            return "保存できませんでした:\(error.localizedDescription)"
        }
        reload()
        ensureDailyRegistration(force: true)
        reconcile(source: "setup")
        rebuildReminders()
        save()
        Task { await updateBadge() }
        return nil
    }

    // MARK: データの書き出しと全削除

    /// 記録を JSON に書き出し、そのファイルの場所を返す
    func exportData() -> URL? {
        struct HabitRow: Encodable {
            var id: UUID, title: String, criteriaNote: String, minimumTitle: String, weekdays: [Int]
            var isRequired: Bool, method: String, activeFrom: String, activeUntil: String?, goalNote: String
        }
        struct CheckInRow: Encodable {
            var achievementID: UUID, cycle: String, habitTitle: String, kind: String, note: String, at: Date, undoneAt: Date?
        }
        struct CycleRow: Encodable { var cycle: String, outcome: String, emergencyCount: Int }
        struct EventRow: Encodable { var at: Date, kind: String, detail: String }
        struct EmergencyRow: Encodable { var requestedAt: Date, startsAt: Date, endsAt: Date, cancelledAt: Date? }
        struct ExportBundle: Encodable {
            var exportedAt: Date
            var state: SharedState?
            var habits: [HabitRow]
            var checkIns: [CheckInRow]
            var cycles: [CycleRow]
            var emergencies: [EmergencyRow]
            var events: [EventRow]
        }
        let bundle = ExportBundle(
            exportedAt: Date(),
            state: state,
            habits: fetchAll(Habit.self).map {
                HabitRow(id: $0.id, title: $0.title, criteriaNote: $0.criteriaNote, minimumTitle: $0.minimumTitle,
                         weekdays: $0.weekdays, isRequired: $0.isRequired, method: $0.methodRaw,
                         activeFrom: $0.activeFromRaw, activeUntil: $0.activeUntilRaw, goalNote: $0.goalNote)
            },
            checkIns: fetchAll(CheckIn.self).sorted { $0.at < $1.at }.map {
                CheckInRow(achievementID: $0.achievementID, cycle: $0.cycleRaw, habitTitle: $0.habitTitle,
                           kind: $0.kindRaw, note: $0.note, at: $0.at, undoneAt: $0.undoneAt)
            },
            cycles: fetchAll(CycleRecord.self).sorted { $0.cycleRaw < $1.cycleRaw }.map {
                CycleRow(cycle: $0.cycleRaw, outcome: $0.outcomeRaw, emergencyCount: $0.emergencyCount)
            },
            emergencies: fetchAll(EmergencyRecord.self).sorted { $0.requestedAt < $1.requestedAt }.map {
                EmergencyRow(requestedAt: $0.requestedAt, startsAt: $0.startsAt, endsAt: $0.endsAt, cancelledAt: $0.cancelledAt)
            },
            events: fetchAll(EventLog.self).sorted { $0.at < $1.at }.map {
                EventRow(at: $0.at, kind: $0.kind, detail: $0.detail)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bundle) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goukakulock-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// すべてのデータを消して、はじめの設定に戻る。ロック中はできない(抜け道にしないため)
    @discardableResult
    func deleteAllData() -> Bool {
        guard decision?.shouldLock != true else {
            show("ロック中は全削除できません", "今日のコミットを達成するか、緊急解除でロックを外してから行ってください。")
            return false
        }
        DeviceActivityCenter().stopMonitoring()
        ManagedSettingsStore(named: .moneyLock).clearAllSettings()
        let fm = FileManager.default
        for url in [store.stateURL, store.backupURL, store.inboxURL] {
            try? fm.removeItem(at: url)
        }
        TargetsStore.removeAll(in: store.directory)
        try? context.delete(model: Habit.self)
        try? context.delete(model: CheckIn.self)
        try? context.delete(model: CycleRecord.self)
        try? context.delete(model: EventLog.self)
        try? context.delete(model: PendingChange.self)
        try? context.delete(model: EmergencyRecord.self)
        try? context.delete(model: AppSettings.self)
        try? context.save()
        cachedSettings = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        InstallMarker.clear()
        lastMark = nil
        recoveredSharedFile = false
        tamperDetectedAt = nil
        reinstallDetectedAt = nil
        reload()
        Task { await updateBadge() }
        return true
    }
}
