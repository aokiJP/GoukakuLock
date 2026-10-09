import Foundation
import SwiftData
import FamilyControls
import GoukakuCore
import GoukakuKit

/// コミットの編集内容
struct HabitDraft: Codable, Equatable {
    var id: UUID?
    var title = ""
    var criteriaNote = ""
    var minimumTitle = ""
    var weekdays: Set<Int> = Set(1...7)
    var isRequired = true
    var method: VerificationMethod = .selfReport
    var targetMinutes: Int?
    var goalNote = ""
    var goalDate: Date?

    init() {}

    init(habit: Habit) {
        id = habit.id
        title = habit.title
        criteriaNote = habit.criteriaNote
        minimumTitle = habit.minimumTitle
        weekdays = Set(habit.weekdays)
        isRequired = habit.isRequired
        method = habit.method
        targetMinutes = habit.targetMinutes
        goalNote = habit.goalNote
        goalDate = habit.goalDate
    }
}

/// 翌サイクルから効く変更の中身(PendingChange.payload に JSON で入れる)
enum PendingPayload: Codable {
    case habit(HabitDraft)
    case schedule(ScheduleConfig)
    case targets(Data)
    case denyInAppPurchases(Bool)
    case minimumQuota(Int)
    case restQuota(Int)
    case enforcement(Enforcement)
}

/// 設定変更を受け付けた結果
enum ChangeResult: Equatable {
    case applied
    case scheduled(CycleID)
    case rejected(String)
}

/// 設定を緩められない仕組み(仕様書 第7.5節)。分類と受け付けは GoukakuCore の ChangePolicy に任せる。
extension AppModel {
    var changeContext: ChangeContext {
        let reason = decision?.reason
        // 開始前はまだ何もロックしていないので、緩める変更も受け付ける
        let canRelax = (decision?.canRelaxNow ?? true) || reason == .notStarted
        return ChangeContext(canRelaxNow: canRelax, hasReferee: false, isPaused: reason == .paused)
    }

    /// ロック中で、緩める変更を今は受け付けられないか(画面で灰色にして理由を出すため)
    var relaxBlocked: Bool { !changeContext.canRelaxNow && !changeContext.isPaused }

    /// 複数の変更をまとめて受け付けるか決める(いちばん厳しい扱いに合わせる)
    func combinedAcceptance(_ changes: [SettingsChange]) -> Acceptance {
        var result: Acceptance = .applyNow
        for change in changes {
            let a = ChangePolicy.acceptance(for: change, context: changeContext)
            switch a {
            case .rejected, .requiresRefereeApproval:
                return a
            case .applyFromNextCycle:
                result = .applyFromNextCycle
            case .applyNow:
                break
            }
        }
        return result
    }

    private func rejection(_ acceptance: Acceptance) -> ChangeResult {
        switch acceptance {
        case .rejected(let reason): return .rejected(reason.message)
        case .requiresRefereeApproval: return .rejected("執行役の承認が必要です。")
        default: return .rejected("今は受け付けられません。")
        }
    }

    private func enqueue(_ payload: PendingPayload, summary: String) -> ChangeResult {
        guard let data = try? JSONEncoder().encode(payload) else { return .rejected("変更を保存できませんでした。") }
        let effective = nextCycle
        context.insert(PendingChange(createdAt: Date(), effectiveCycle: effective, summary: summary, payload: data))
        log("settings", "予約:\(summary)(\(Fmt.cycle(effective, dayStartMinute: cycleCalendar.dayStartMinute))から)")
        save()
        return .scheduled(effective)
    }

    var pendingChanges: [PendingChange] {
        _ = revision
        return fetchAll(PendingChange.self).filter(\.isWaiting).sorted { $0.createdAt < $1.createdAt }
    }

    /// 予約した変更の取り消し(緩める変更を取り消す=厳しい側に戻すので、いつでもよい)
    func cancelPendingChange(_ change: PendingChange) {
        change.statusRaw = "cancelled"
        change.resolvedAt = Date()
        log("settings", "予約を取り消した:\(change.summary)")
        save()
    }

    /// 効き始めるサイクルになった変更を反映する(起動・前面復帰のたびに呼ぶ)
    func applyDuePendingChanges() {
        let current = currentCycle
        let due = pendingChanges.filter { ($0.effectiveCycle ?? current) <= current }
        guard !due.isEmpty else { return }
        for change in due {
            if let payload = try? JSONDecoder().decode(PendingPayload.self, from: change.payload) {
                apply(payload)
                change.statusRaw = "applied"
                log("settings", "反映:\(change.summary)")
            } else {
                change.statusRaw = "cancelled"
                log("error", "予約を読めなかったので取り消した:\(change.summary)")
            }
            change.resolvedAt = Date()
        }
        save()
        reload()
        ensureDailyRegistration(force: false)
        reconcile(source: "pendingApplied")
    }

    private func apply(_ payload: PendingPayload) {
        switch payload {
        case .habit(let draft):
            if let id = draft.id, let existing = self.habit(id) { writeHabit(draft, to: existing) }
        case .schedule(let config):
            try? actions.setSchedule(config)
            reload()
        case .targets(let data):
            if let targets = try? JSONDecoder().decode(LockTargets.self, from: data) { writeTargets(targets) }
        case .denyInAppPurchases(let deny):
            try? actions.setOptions(LockOptions(denyInAppPurchases: deny))
        case .minimumQuota(let n):
            settings.minimumWeeklyQuota = n
        case .restQuota(let n):
            settings.restWeeklyQuota = n
        case .enforcement(let enforcement):
            try? actions.setEnforcement(enforcement)
        }
    }

    // MARK: コミット(S-04)

    private func requiredCount(excluding id: UUID?) -> Int {
        let next = nextCycle
        return fetchAll(Habit.self).filter { $0.isRequired && $0.id != id && !$0.hasEnded(asOf: next) }.count
    }

    func saveHabit(_ draft: HabitDraft) -> ChangeResult {
        var draft = draft
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.criteriaNote = draft.criteriaNote.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.minimumTitle = draft.minimumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { return .rejected("目標を入力してください。") }
        guard !draft.weekdays.isEmpty else { return .rejected("曜日を1つ以上選んでください。") }
        guard let state else { return .rejected("はじめの設定が済んでいません。") }

        if let id = draft.id, let existing = self.habit(id) {
            if draft.isRequired && !existing.isRequired && requiredCount(excluding: id) >= 3 {
                return .rejected("必須のコミットは3つまでです。")
            }
            var changes: [SettingsChange] = []
            if existing.title != draft.title || existing.criteriaNote != draft.criteriaNote
                || existing.minimumTitle != draft.minimumTitle {
                changes.append(.habitTextEdited)
            }
            let old = Set(existing.weekdays)
            let added = draft.weekdays.subtracting(old).count
            let removed = old.subtracting(draft.weekdays).count
            if added + removed > 0 { changes.append(.habitWeekdaysChanged(added: added, removed: removed)) }
            if existing.isRequired != draft.isRequired { changes.append(draft.isRequired ? .habitAdded : .habitRemoved) }
            if existing.method != draft.method { changes.append(.methodChanged(from: existing.method, to: draft.method)) }
            // 目標のメモはロックに関係しないので、すぐ反映する
            existing.goalNote = draft.goalNote
            existing.goalDate = draft.goalDate
            guard !changes.isEmpty else {
                save()
                return .applied
            }
            let acceptance = combinedAcceptance(changes)
            switch acceptance {
            case .applyNow:
                writeHabit(draft, to: existing)
                log("settings", "コミット「\(draft.title)」を変更")
                save()
                return .applied
            case .applyFromNextCycle:
                return enqueue(.habit(draft), summary: "コミット「\(draft.title)」の変更")
            default:
                save()
                return rejection(acceptance)
            }
        }

        // 新しいコミット(追加は厳しくする変更。翌サイクルから有効)
        if draft.isRequired && requiredCount(excluding: nil) >= 3 {
            return .rejected("必須のコミットは3つまでです。")
        }
        let acceptance = combinedAcceptance([.habitAdded])
        let from: CycleID
        switch acceptance {
        case .applyNow: from = max(currentCycle, state.activeSince)
        case .applyFromNextCycle: from = max(nextCycle, state.activeSince)
        default: return rejection(acceptance)
        }
        let order = (fetchAll(Habit.self).map(\.sortOrder).max() ?? -1) + 1
        let habit = Habit(title: draft.title, criteriaNote: draft.criteriaNote, minimumTitle: draft.minimumTitle,
                          weekdays: draft.weekdays.sorted(), isRequired: draft.isRequired, method: draft.method,
                          targetMinutes: draft.targetMinutes, activeFrom: from, sortOrder: order,
                          goalNote: draft.goalNote, goalDate: draft.goalDate)
        context.insert(habit)
        do {
            try actions.upsertHabit(habit.snapshot)
        } catch {
            context.delete(habit)
            return .rejected("保存できませんでした:\(error.localizedDescription)")
        }
        log("settings", "コミット「\(draft.title)」を追加(\(Fmt.cycle(from, dayStartMinute: cycleCalendar.dayStartMinute))から)")
        save()
        reconcile(source: "habitAdded")
        rebuildReminders()
        return from > currentCycle ? .scheduled(from) : .applied
    }

    /// コミットの削除(緩める変更。受け付けたら翌サイクルから無効)
    func deleteHabit(_ id: UUID) -> ChangeResult {
        guard let target = self.habit(id) else { return .rejected("見つかりません。") }
        let acceptance = combinedAcceptance([.habitRemoved])
        let until: CycleID
        switch acceptance {
        case .applyNow: until = currentCycle
        case .applyFromNextCycle: until = nextCycle
        default: return rejection(acceptance)
        }
        do {
            try actions.endHabit(id: id, until: until)
        } catch {
            return .rejected("保存できませんでした:\(error.localizedDescription)")
        }
        target.activeUntilRaw = until.description
        log("settings", "コミット「\(target.title)」を削除(\(Fmt.cycle(until, dayStartMinute: cycleCalendar.dayStartMinute))から無効)")
        save()
        reconcile(source: "habitRemoved")
        rebuildReminders()
        return until > currentCycle ? .scheduled(until) : .applied
    }

    /// 編集内容を SwiftData と state.json に書く(受け付けの判断は済んでいる前提)
    private func writeHabit(_ draft: HabitDraft, to habit: Habit) {
        habit.title = draft.title
        habit.criteriaNote = draft.criteriaNote
        habit.minimumTitle = draft.minimumTitle
        habit.weekdays = draft.weekdays.sorted()
        habit.isRequired = draft.isRequired
        habit.methodRaw = draft.method.rawValue
        habit.targetMinutes = draft.targetMinutes
        habit.goalNote = draft.goalNote
        habit.goalDate = draft.goalDate
        try? actions.upsertHabit(habit.snapshot)
        save()
        reconcile(source: "habitEdited")
        rebuildReminders()
    }

    // MARK: ロックモード・ロック開始・日付切替

    func updateSchedule(_ new: ScheduleConfig) -> ChangeResult {
        guard let state else { return .rejected("はじめの設定が済んでいません。") }
        guard SchedulePlanner.isValid(new) else { return .rejected("その時刻は選べません(ロック開始は日付切替の30分後〜20時間後)。") }
        let old = state.schedule
        var changes: [SettingsChange] = []
        if old.dayStartMinute != new.dayStartMinute { changes.append(.dayStartChanged) }
        switch (old.mode, new.mode) {
        case let (.evening(a), .evening(b)) where a != b:
            changes.append(.lockStartMoved(fromMinute: a, toMinute: b, dayStartMinute: new.dayStartMinute))
        case let (.earn(a), .earn(b)) where a != b:
            changes.append(.modeChanged(from: old.mode, to: new.mode, dayStartMinute: new.dayStartMinute))
        default:
            if old.mode.kind != new.mode.kind {
                changes.append(.modeChanged(from: old.mode, to: new.mode, dayStartMinute: new.dayStartMinute))
            }
        }
        guard !changes.isEmpty else { return .applied }
        let acceptance = combinedAcceptance(changes)
        switch acceptance {
        case .applyNow:
            do { try actions.setSchedule(new) } catch { return .rejected(error.localizedDescription) }
            log("settings", "ロックの設定を変更:\(describe(new))")
            save()
            reload()
            ensureDailyRegistration(force: true)
            reconcile(source: "schedule")
            rebuildReminders()
            return .applied
        case .applyFromNextCycle:
            return enqueue(.schedule(new), summary: "ロックの設定を「\(describe(new))」に")
        default:
            return rejection(acceptance)
        }
    }

    // MARK: ロック対象と常に許可

    func updateTargets(_ new: LockTargets) -> ChangeResult {
        let problems = new.problems
        guard problems.isEmpty else { return .rejected(problems.joined(separator: "\n")) }
        let old = targets
        let lockAdded = !new.lock.applicationTokens.isSubset(of: old.lock.applicationTokens)
            || !new.lock.categoryTokens.isSubset(of: old.lock.categoryTokens)
            || !new.lock.webDomainTokens.isSubset(of: old.lock.webDomainTokens)
        let lockRemoved = !old.lock.applicationTokens.isSubset(of: new.lock.applicationTokens)
            || !old.lock.categoryTokens.isSubset(of: new.lock.categoryTokens)
            || !old.lock.webDomainTokens.isSubset(of: new.lock.webDomainTokens)
        let allowAdded = !new.allow.applicationTokens.isSubset(of: old.allow.applicationTokens)
            || !new.allow.categoryTokens.isSubset(of: old.allow.categoryTokens)
            || !new.allow.webDomainTokens.isSubset(of: old.allow.webDomainTokens)
        let allowRemoved = !old.allow.applicationTokens.isSubset(of: new.allow.applicationTokens)
            || !old.allow.categoryTokens.isSubset(of: new.allow.categoryTokens)
            || !old.allow.webDomainTokens.isSubset(of: new.allow.webDomainTokens)
        var changes: [SettingsChange] = []
        if lockAdded { changes.append(.lockTargetsAdded) }
        if lockRemoved { changes.append(.lockTargetsRemoved) }
        if allowAdded { changes.append(.allowTargetsAdded) }
        if allowRemoved { changes.append(.allowTargetsRemoved) }
        guard !changes.isEmpty else { return .applied }

        let acceptance = combinedAcceptance(changes)
        switch acceptance {
        case .applyNow:
            writeTargets(new)
            log("settings", "ロック対象・常に許可を変更")
            save()
            return .applied
        case .applyFromNextCycle:
            // 厳しくする側(対象の追加・常に許可の削除)だけは今すぐ効かせ、残りを翌サイクルに回す
            var stricter = old
            stricter.lock.applicationTokens.formUnion(new.lock.applicationTokens)
            stricter.lock.categoryTokens.formUnion(new.lock.categoryTokens)
            stricter.lock.webDomainTokens.formUnion(new.lock.webDomainTokens)
            stricter.allow.applicationTokens.formIntersection(new.allow.applicationTokens)
            stricter.allow.categoryTokens.formIntersection(new.allow.categoryTokens)
            stricter.allow.webDomainTokens.formIntersection(new.allow.webDomainTokens)
            if lockAdded || allowRemoved, stricter.problems.isEmpty {
                writeTargets(stricter)
            }
            guard let data = try? JSONEncoder().encode(new) else { return .rejected("変更を保存できませんでした。") }
            return enqueue(.targets(data), summary: "ロック対象・常に許可の変更")
        default:
            return rejection(acceptance)
        }
    }

    /// targets.json を書いて、区間(トリップワイヤーの対象)とロックを合わせ直す
    private func writeTargets(_ new: LockTargets) {
        do {
            try TargetsStore.save(new, to: store.directory)
        } catch {
            show("保存できませんでした", error.localizedDescription)
            return
        }
        settings.targetsRevision += 1
        reload()
        ensureDailyRegistration(force: true)
        reconcile(source: "targets")
    }

    // MARK: そのほかの設定

    func setDenyInAppPurchases(_ deny: Bool) -> ChangeResult {
        guard let state, state.options.denyInAppPurchases != deny else { return .applied }
        let acceptance = combinedAcceptance([.inAppPurchaseBlockChanged(to: deny)])
        switch acceptance {
        case .applyNow:
            try? actions.setOptions(LockOptions(denyInAppPurchases: deny))
            log("settings", "アプリ内課金の禁止を\(deny ? "オン" : "オフ")に")
            save()
            reconcile(source: "options")
            return .applied
        case .applyFromNextCycle:
            return enqueue(.denyInAppPurchases(deny), summary: "アプリ内課金の禁止を\(deny ? "オン" : "オフ")に")
        default:
            return rejection(acceptance)
        }
    }

    func setMinimumQuota(_ n: Int) -> ChangeResult {
        let old = settings.minimumWeeklyQuota
        guard old != n else { return .applied }
        let acceptance = combinedAcceptance([.minimumQuotaChanged(from: old, to: n)])
        switch acceptance {
        case .applyNow:
            settings.minimumWeeklyQuota = n
            log("settings", "最小版の上限を週\(n)回に")
            save()
            return .applied
        case .applyFromNextCycle:
            return enqueue(.minimumQuota(n), summary: "最小版の上限を週\(n)回に")
        default:
            return rejection(acceptance)
        }
    }

    func setRestQuota(_ n: Int) -> ChangeResult {
        let old = settings.restWeeklyQuota
        guard old != n else { return .applied }
        let acceptance = combinedAcceptance([.restQuotaChanged(from: old, to: n)])
        switch acceptance {
        case .applyNow:
            settings.restWeeklyQuota = n
            log("settings", "休養日の上限を週\(n)日に")
            save()
            return .applied
        case .applyFromNextCycle:
            return enqueue(.restQuota(n), summary: "休養日の上限を週\(n)日に")
        default:
            return rejection(acceptance)
        }
    }

    /// 見守りモード(ロックせず記録だけ)への切り替えは緩める変更、ロックへ戻すのは厳しくする変更
    func setEnforcement(_ enforcement: Enforcement) -> ChangeResult {
        guard let state, state.enforcement != enforcement else { return .applied }
        let label = enforcement == .monitorOnly ? "見守りモードに切り替え" : "ロックを再開"
        let acceptance = combinedAcceptance([.enforcementChanged(to: enforcement)])
        switch acceptance {
        case .applyNow:
            try? actions.setEnforcement(enforcement)
            log("settings", label)
            save()
            reconcile(source: "enforcement")
            rebuildReminders()
            return .applied
        case .applyFromNextCycle:
            return enqueue(.enforcement(enforcement), summary: label)
        default:
            return rejection(acceptance)
        }
    }

    /// 通知の設定(ロックに関係しないので、いつでもすぐ反映)
    func updateReminders(minutes: [Int], quietStart: Int, quietEnd: Int) {
        settings.reminderMinutes = Array(Set(minutes)).sorted()
        settings.quietStartMinute = quietStart
        settings.quietEndMinute = quietEnd
        log("settings", "リマインドを変更")
        save()
        rebuildReminders()
    }

    /// 結果を画面の知らせにする(反映・予約・却下)
    func report(_ result: ChangeResult, appliedTitle: String = "保存しました") {
        switch result {
        case .applied:
            break
        case .scheduled(let cycle):
            show("受け付けました", "\(Fmt.cycle(cycle, dayStartMinute: cycleCalendar.dayStartMinute))の日付切替から反映されます。それまでは今の(厳しい側の)設定のままです。")
        case .rejected(let reason):
            show("今は変更できません", reason)
        }
    }
}
