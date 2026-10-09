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
    /// デバッグ:Screen Time の許可もロック対象もなしで、画面の確認だけをする(DEBUG ビルドの画面からだけ立つ)
    var debugUIOnly = false

    var schedule: ScheduleConfig {
        ScheduleConfig(dayStartMinute: dayStartMinute,
                       mode: modeKind == .evening ? .evening(lockStartMinute: lockStartMinute) : .morning)
    }
}

/// 本体の操作(チェックイン・取り消し・緊急解除・一時停止・休養日・はじめの設定・全削除)
extension AppModel {
    // MARK: チェックイン

    /// 確かめ方ごとの記録の中身
    enum Evidence {
        /// 自己申告の一言(5文字以上)
        case note(String)
        /// 集中タイマーで数えた秒
        case timer(seconds: Int)
        /// アプリ内のカメラで撮った証拠写真
        case photo(fileName: String, note: String)

        var method: VerificationMethod {
            switch self {
            case .note: return .selfReport
            case .timer: return .timer
            case .photo: return .photo
            }
        }
    }

    /// 自己申告で達成を記録する(画面・通知・Siri から)
    @discardableResult
    func checkIn(habit: HabitSnapshot, minimum: Bool, note: String) -> Achievement? {
        checkIn(habit: habit, minimum: minimum, evidence: .note(note))
    }

    /// 達成を記録する。成功したら記録した達成を返す
    @discardableResult
    func checkIn(habit: HabitSnapshot, minimum: Bool, evidence: Evidence) -> Achievement? {
        var noteText = ""
        switch evidence {
        case .note(let text):
            noteText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard noteText.count >= 5 else {
                show("一言が短すぎます", "「やったこと」を5文字以上で書いてください。")
                return nil
            }
            guard !isEarnMode else {
                show("稼働型では使えません", "稼働型のチェックインは、タイマー・写真・使用時間など計れる方法だけです(何度でも押せてしまうため)。")
                return nil
            }
        case .timer(let seconds):
            noteText = "集中タイマー \(max(1, seconds / 60))分"
        case .photo(_, let note):
            noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if noteText.isEmpty { noteText = "写真で記録" }
        }
        if minimum && !canUseMinimum() {
            show("最小版の上限です", "最小版は週\(settings.minimumWeeklyQuota)回までです。")
            return nil
        }
        do {
            let wasSatisfied = decision?.todaySatisfied == true
            let achievement = try actions.checkIn(habitID: habit.id, kind: minimum ? .minimum : .full)
            let title = minimum ? (habit.minimumTitle ?? habit.title) : habit.title
            let record = CheckIn(achievement: achievement, habitTitle: title, method: evidence.method, note: noteText)
            switch evidence {
            case .timer(let seconds): record.timerSeconds = seconds
            case .photo(let fileName, _): record.evidenceFileName = fileName
            case .note: break
            }
            context.insert(record)
            log("checkin", "「\(habit.title)」\(minimum ? "を最小版で" : "を")達成(\(Self.methodName(evidence.method)))")
            syncEmergencyRecord()
            save()
            reload()
            if let minutes = achievement.grantsMinutes {
                // 稼働型:解除枠の残りを Live Activity に出す
                LiveActivities.show(.init(kind: .earn, title: "解除中", startsAt: achievement.at,
                                          endsAt: achievement.at.addingTimeInterval(TimeInterval(minutes * 60))))
            }
            if let e = state?.emergency, e.cancelledAt != nil {
                LiveActivities.end(.emergency)   // 待機中に達成したので取り消された
            }
            if decision?.todaySatisfied == true && !wasSatisfied {
                log("unlock", "今日の必須コミットをすべて達成")
                celebrateIfMilestone()
                save()
            }
            rebuildReminders()
            Task { await updateBadge() }
            NotificationCenter.default.post(name: .goukakuDayChanged, object: nil)   // 預け金の返金のきっかけ
            return achievement
        } catch {
            show(error: error)
            return nil
        }
    }

    static func methodName(_ method: VerificationMethod) -> String {
        switch method {
        case .selfReport: return "自己申告"
        case .photo: return "写真"
        case .timer: return "集中タイマー"
        case .appUsage: return "使用時間"
        case .health: return "ヘルスケア"
        case .placeTimer: return "場所つきタイマー"
        case .referee: return "執行役の承認"
        }
    }

    /// 通知の返信・Siri から、アプリを開かずに自己申告で記録する
    func quickCheckIn(habitID: UUID?, minimum: Bool, note: String) -> QuickCheckInResult {
        reload()
        guard state != nil, let today else {
            return QuickCheckInResult(ok: false, title: "記録できませんでした", message: "はじめの設定が済んでいません。アプリを開いてください。")
        }
        let candidates = (today.required + today.optional).filter { !today.isDone($0.id) }
        let chosen = habitID.flatMap { id in candidates.first { $0.id == id } }
            ?? today.pendingRequired.first ?? candidates.first
        guard let habit = chosen else {
            return QuickCheckInResult(ok: false, title: "記録することはありません", message: "今日のコミットはすべて記録済みです。")
        }
        guard habit.method == .selfReport else {
            return QuickCheckInResult(ok: false, title: "アプリで記録してください",
                                      message: "「\(habit.title)」は\(Self.methodName(habit.method))で確かめるコミットです。")
        }
        guard !isEarnMode else {
            return QuickCheckInResult(ok: false, title: "アプリで記録してください",
                                      message: "稼働型では、タイマー・写真など計れる方法で記録します。")
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else {
            return QuickCheckInResult(ok: false, title: "一言が短すぎます",
                                      message: "「やったこと」を5文字以上で。通知を長押しして、もう一度どうぞ。")
        }
        if minimum {
            guard habit.minimumTitle != nil else {
                return QuickCheckInResult(ok: false, title: "最小版がありません", message: "「\(habit.title)」には最小版が決めてありません。")
            }
            guard canUseMinimum() else {
                return QuickCheckInResult(ok: false, title: "最小版の上限です", message: "最小版は週\(settings.minimumWeeklyQuota)回までです。")
            }
        }
        guard checkIn(habit: habit, minimum: minimum, note: trimmed) != nil else {
            return QuickCheckInResult(ok: false, title: "記録できませんでした", message: message?.body ?? "アプリを開いて、もう一度試してください。")
        }
        message = nil
        let left = self.today?.pendingRequired.count ?? 0
        let unlocked = decision?.todaySatisfied == true
        return QuickCheckInResult(ok: true, title: minimum ? "最小版で記録しました" : "記録しました",
                                  message: unlocked ? "今日の必須コミットをすべて達成。ロックが外れました。"
                                                    : "「\(habit.title)」を記録。残りの必須コミット:\(left)件")
    }

    /// 押し間違いの取り消し(5分以内)
    @discardableResult
    func undoCheckIn(_ achievementID: UUID) -> Bool {
        do {
            try actions.undoCheckIn(id: achievementID)
            if state?.achievements.first(where: { $0.id == achievementID })?.grantsMinutes != nil {
                LiveActivities.end(.earn)
            }
            if let record = fetchAll(CheckIn.self).first(where: { $0.achievementID == achievementID }) {
                record.undoneAt = Date()
                log("undo", "「\(record.habitTitle)」のチェックインを取り消した")
            }
            save()
            reload()
            rebuildReminders()
            Task { await updateBadge() }
            NotificationCenter.default.post(name: .goukakuDayChanged, object: nil)
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
            LiveActivities.show(.init(kind: .emergency, title: "緊急解除", startsAt: window.startsAt, endsAt: window.endsAt))
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
            LiveActivities.end(.emergency)
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
        if !draft.debugUIOnly {
            let problems = draft.targets.problems
            guard problems.isEmpty else { return problems.joined(separator: "\n") }
            guard draft.confirmedSafety else { return "安全の確認にチェックしてください。" }
        }
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
        struct ExperienceRow: Encodable {
            var title: String, note: String, feeling: String?, category: String, at: Date, reply: String?, question: String?, source: String
        }
        struct IdeaRow: Encodable { var title: String, line: String, firstStep: String, category: String, status: String, kind: String, origin: String, engine: String, createdAt: Date }
        struct NoteRow: Encodable { var text: String, source: String, createdAt: Date }
        struct MessageRow: Encodable { var role: String, text: String, at: Date }
        struct ExportBundle: Encodable {
            var exportedAt: Date
            var state: SharedState?
            var habits: [HabitRow]
            var checkIns: [CheckInRow]
            var cycles: [CycleRow]
            var emergencies: [EmergencyRow]
            var events: [EventRow]
            var experiences: [ExperienceRow]
            var experienceIdeas: [IdeaRow]
            var companionNotes: [NoteRow]
            var companionMessages: [MessageRow]
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
            },
            experiences: fetchAll(ExperienceLog.self).sorted { $0.at < $1.at }.map {
                ExperienceRow(title: $0.title, note: $0.note, feeling: $0.feelingRaw, category: $0.categoryRaw,
                              at: $0.at, reply: $0.reply, question: $0.question, source: $0.sourceRaw)
            },
            experienceIdeas: fetchAll(ExperienceIdea.self).filter { $0.statusRaw != "dismissed" }.sorted { $0.createdAt < $1.createdAt }.map {
                IdeaRow(title: $0.title, line: $0.line, firstStep: $0.firstStep, category: $0.categoryRaw,
                        status: $0.statusRaw, kind: $0.kindRaw, origin: $0.originRaw, engine: $0.engineName,
                        createdAt: $0.createdAt)
            },
            companionNotes: fetchAll(CompanionNote.self).sorted { $0.createdAt < $1.createdAt }.map {
                NoteRow(text: $0.text, source: $0.sourceRaw, createdAt: $0.createdAt)
            },
            companionMessages: fetchAll(CompanionMessage.self).sorted { $0.at < $1.at }.map {
                MessageRow(role: $0.roleRaw, text: $0.text, at: $0.at)
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
        try? context.delete(model: WeeklyReview.self)
        // 相棒AIの記録(体験・覚えていること・会話)も消す。入れたモデルは消さない(設定 › AI から消せる)
        CompanionModel.shared.resetInMemoryState()
        try? context.delete(model: ExperienceIdea.self)
        try? context.delete(model: ExperienceLog.self)
        try? context.delete(model: CompanionNote.self)
        try? context.delete(model: CompanionMessage.self)
        EvidenceStore.removeAll()
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
