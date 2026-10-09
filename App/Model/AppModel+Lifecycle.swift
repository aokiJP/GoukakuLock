import Foundation
import SwiftData
import FamilyControls
import UserNotifications
import GoukakuCore
import GoukakuKit

/// 起動・前面復帰・バックグラウンド更新で行うこと(仕様書 第16.4節)。何度呼んでも同じ結果になる。
extension AppModel {
    func onLaunchOrForeground() async {
        guard !isRunningLifecycle else { return }
        isRunningLifecycle = true
        defer { isRunningLifecycle = false }

        detectReinstallIfNeeded()
        reload()
        guard state != nil else {
            // はじめの設定がまだ(または state.json が壊れていて復旧できない)
            await refreshPermissions()
            return
        }

        // 1. 受信箱の取り込み・結果の確定・古いものの削除・判定とロックの適用
        do {
            let report = try LaunchTasks(actions: actions).run(lastFinalized: settings.lastFinalizedCycle, now: Date())
            if report.recovered {
                recoveredSharedFile = true
                log("recover", "state.json が壊れていたので、1つ前の保存から戻した")
            }
            for entry in report.logs {
                context.insert(EventLog(at: entry.at, kind: entry.kind, detail: "拡張: \(entry.detail)"))
            }
            // 2. 確定した結果を保存する
            for item in report.finalized {
                upsertCycleRecord(item.cycle, outcome: item.outcome)
            }
            if let last = report.finalized.last?.cycle {
                settings.lastFinalizedCycle = last
            }
        } catch {
            log("error", "起動時の処理に失敗: \(error)")
        }
        save()
        reload()

        // 3. 効き始めるサイクルになった設定変更を反映する
        applyDuePendingChanges()
        // 4. 区間の登録を確かめる(変わっていなければ登録し直さない)
        await refreshPermissions()
        ensureDailyRegistration(force: false)
        // 6. 改ざんを確かめる
        checkClockTamper()
        // 7. リマインドを作り直す
        rebuildReminders()
        save()
        reload()
        await updateBadge()
        // 9. 次のバックグラウンド更新を予約する
        scheduleNextRefresh()
    }

    private func upsertCycleRecord(_ cycle: CycleID, outcome: CycleOutcome) {
        let raw = cycle.description
        let cal = cycleCalendar
        let emergencies = fetchAll(EmergencyRecord.self).filter {
            $0.didStart(asOf: Date()) && cal.cycle(containing: $0.startsAt) == cycle
        }.count
        if let existing = fetchAll(CycleRecord.self).first(where: { $0.cycleRaw == raw }) {
            existing.outcomeRaw = outcome.rawValue
            existing.emergencyCount = emergencies
        } else {
            context.insert(CycleRecord(cycle: cycle, outcome: outcome, finalizedAt: Date(), emergencyCount: emergencies))
        }
    }

    /// 新しく入れた(state.json がない)のに、キーチェーンの印が「ロック中」なら記録する(SP-09)
    func detectReinstallIfNeeded() {
        guard !checkedReinstall else { return }
        checkedReinstall = true
        guard !FileManager.default.fileExists(atPath: store.stateURL.path),
              settings.onboardingCompletedAt == nil,
              let mark = InstallMarker.read(), mark.locked else { return }
        reinstallDetectedAt = Date()
        log("reinstall", "ロック中に削除して入れ直した(前回の判定 \(Fmt.dateTime(mark.at)))")
        InstallMarker.write(InstallMarker.Mark(locked: false, at: Date()))
        save()
    }

    /// Screen Time の許可と通知の許可を確かめる(外れていたら回避ログに残す)
    func refreshPermissions() async {
        let approved = AuthorizationCenter.shared.authorizationStatus == .approved
        screenTimeApproved = approved
        if state != nil {
            if !approved && settings.lastAuthApproved {
                log("auth", "Screen Time の許可が外れていた")
            } else if approved && !settings.lastAuthApproved {
                log("auth", "Screen Time の許可が戻った")
            }
            settings.lastAuthApproved = approved
        }
        notificationsAllowed = await Self.notificationAuthorized()
    }

    nonisolated static func notificationAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    nonisolated static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    nonisolated static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }

    /// Screen Time の許可を求める(本人が Face ID などで承認する)。失敗の理由を文字で返す
    func requestScreenTimeAuthorization() async -> String? {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            screenTimeApproved = AuthorizationCenter.shared.authorizationStatus == .approved
            return describeAuthorizationError(error)
        }
        screenTimeApproved = AuthorizationCenter.shared.authorizationStatus == .approved
        if screenTimeApproved, state != nil {
            settings.lastAuthApproved = true
            log("auth", "Screen Time の許可を得た")
            ensureDailyRegistration(force: true)
            reconcile(source: "authorized")
            save()
        }
        return screenTimeApproved ? nil : "許可されませんでした。"
    }

    private func describeAuthorizationError(_ error: Error) -> String {
        if let familyError = error as? FamilyControlsError {
            switch familyError {
            case .restricted:
                return "この端末では Screen Time の制限が使えません(機能制限や管理の設定を確認してください)。"
            case .unavailable:
                return "Screen Time の機能を使えません。署名に Family Controls のエンタイトルメントが入っているか確認してください。"
            case .invalidAccountType:
                return "この Apple アカウントでは使えません(子ども用アカウントなど)。"
            case .authorizationCanceled:
                return "許可がキャンセルされました。もう一度「許可する」を押してください。"
            case .authorizationConflict:
                return "別のアプリが同じ種類の許可を持っています。"
            case .networkError:
                return "ネットワークにつながってから、もう一度試してください。"
            case .authenticationMethodUnavailable:
                return "パスコードを設定してから、もう一度試してください。"
            default:
                return "許可できませんでした(\(familyError))。"
            }
        }
        return "許可できませんでした:\(error.localizedDescription)"
    }

    /// 毎日の区間が登録されているか確かめ、なければ(または設定・対象が変わっていれば)登録し直す
    func ensureDailyRegistration(force: Bool) {
        guard let state, AuthorizationCenter.shared.authorizationStatus == .approved else { return }
        let fingerprint = registrationFingerprint(state.schedule)
        if !force, settings.registrationFingerprint == fingerprint,
           ScheduleRegistrar.isDailyRegistered(config: state.schedule) {
            return
        }
        do {
            try ScheduleRegistrar.registerDaily(config: state.schedule, targets: targets, usage: [])
            settings.registrationFingerprint = fingerprint
            registrationError = nil
            log("schedule", "毎日の区間を登録した(\(describe(state.schedule)))")
        } catch {
            registrationError = error.localizedDescription
            log("error", "区間の登録に失敗: \(error)")
        }
    }

    private func registrationFingerprint(_ config: ScheduleConfig) -> String {
        "\(config.dayStartMinute)|\(describeMode(config.mode))|targets#\(settings.targetsRevision)"
    }

    private func describeMode(_ mode: LockMode) -> String {
        switch mode {
        case .morning: return "morning"
        case .evening(let m): return "evening-\(m)"
        case .earn(let w): return "earn-\(w)"
        }
    }

    func describe(_ config: ScheduleConfig) -> String {
        let start = Fmt.hm(minuteOfDay: config.dayStartMinute)
        switch config.mode {
        case .morning: return "日付切替 \(start)・朝からロック"
        case .evening(let m): return "日付切替 \(start)・夕方からロック \(Fmt.hm(minuteOfDay: m))"
        case .earn(let w): return "日付切替 \(start)・稼働型 \(Fmt.duration(minutes: w))"
        }
    }

    /// 時計の基準と比べて、端末の時刻が動かされていないか確かめる(第17.9節)
    func checkClockTamper() {
        let anchor = currentClockAnchor()
        if let data = settings.clockAnchorData,
           let previous = try? JSONDecoder().decode(ClockAnchor.self, from: data),
           let skew = TamperDetector.clockSkew(from: previous, to: anchor) {
            tamperDetectedAt = Date()
            log("tamper", "端末の時刻が \(Int(skew)) 秒ずれていた")
            let now = Date()
            if let e = state?.emergency, e.isPending(at: now) || e.isActive(at: now) {
                try? actions.cancelEmergency()
                syncEmergencyRecord()
                log("emergency", "時刻の改ざんを検知したため、緊急解除を終了した")
            }
        }
        settings.clockAnchorData = try? JSONEncoder().encode(anchor)
    }

    /// リマインドを作り直す(7サイクル先まで)
    func rebuildReminders() {
        guard let state, notificationsAllowed else { return }
        let plan = ReminderPlanner.plan(state: state, settings: settings.reminderSettings,
                                        extra: store.pendingAchievements(), now: Date())
        var titles: [CycleID: String] = [:]
        for reminder in plan where titles[reminder.cycle] == nil {
            if let title = summary(for: reminder.cycle)?.pendingRequired.first?.title {
                titles[reminder.cycle] = title
            }
        }
        ReminderScheduler.replace(with: plan, titles: titles)
    }

    /// アイコンのバッジを、まだ達成していない必須コミットの数に直す
    func updateBadge() async {
        var count = 0
        if let decision, let today {
            switch decision.reason {
            case .awaitingCommit, .carryOver, .beforeLockStart:
                count = today.pendingRequired.count
            default:
                count = 0
            }
        }
        await Self.setBadge(count)
    }

    /// state.json の緊急解除の取り消しを、SwiftData の記録にも写す
    func syncEmergencyRecord() {
        guard let e = (try? store.load())?.emergency else { return }
        if let record = fetchAll(EmergencyRecord.self).first(where: {
            abs($0.requestedAt.timeIntervalSince(e.requestedAt)) < 0.001
        }) {
            record.cancelledAt = e.cancelledAt
        }
    }
}
