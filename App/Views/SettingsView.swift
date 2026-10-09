import SwiftUI
import SwiftData
import GoukakuCore
import GoukakuKit

/// S-06 設定。ロック中に変えられない項目は隠さず、押すと理由を出す。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AIRuntime.self) private var runtime
    @Environment(DepositModel.self) private var deposit
    @State private var confirmDeleteAll = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                if model.relaxBlocked {
                    Section {
                        Label("ロック中です。ゆるめる変更は、今日のコミットを達成したあとに受け付け、翌日から反映します。厳しくする変更はいつでもできます。", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                lockSection
                Section("コミット") {
                    NavigationLink("コミットの一覧と編集") { CommitListView() }
                    if !model.pendingChanges.isEmpty {
                        NavigationLink("予約中の変更(\(model.pendingChanges.count)件)") { PendingChangesView() }
                    }
                }
                quotaSection
                Section("通知") {
                    NavigationLink("リマインド") { ReminderSettingsView() }
                }
                Section {
                    NavigationLink {
                        DepositView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("預け金(クレカ)", systemImage: "creditcard")
                            Text(depositStatus)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("settings.deposit")
                } footer: {
                    Text("先にカードで7日分を預け、達成した日の分が返ってきます。使うかどうかは自由です。")
                }
                Section {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("AI", systemImage: "cpu")
                            Text(runtime.statusLine)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    NavigationLink {
                        GrowthView()
                    } label: {
                        Label("体験の地図・相棒が覚えていること", systemImage: "leaf.arrow.triangle.circlepath")
                    }
                } header: {
                    Text("相棒AI")
                } footer: {
                    Text("AIはこの iPhone の中だけで動きます。")
                }
                Section {
                    NavigationLink {
                        TipsView()
                    } label: {
                        Label("ウィジェット・Siri・通知から記録する", systemImage: "sparkles")
                    }
                    NavigationLink {
                        AppIconView()
                    } label: {
                        Label("アイコン", systemImage: "app.badge")
                    }
                } header: {
                    Text("使いこなす")
                }
                Section("非常口") {
                    NavigationLink("緊急解除") { EmergencyView() }
                    NavigationLink("一時停止・見守りモード") { PauseView() }
                }
                Section {
                    NavigationLink("回避ログと出来事") { EventLogView() }
                    Button("データを書き出す") { exportURL = model.exportData() }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("書き出したファイルを共有", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("すべてのデータを削除", role: .destructive) { confirmDeleteAll = true }
                } header: {
                    Text("記録とデータ")
                } footer: {
                    Text("データはこの iPhone の中だけにあります。")
                }
                Section {
                    Text(AppConstants.quitSignal)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                statusSection
                #if DEBUG
                Section("開発") {
                    NavigationLink("デバッグメニュー") { DebugMenuView() }
                }
                #endif
            }
            .navigationTitle("設定")
            .confirmationDialog("すべてのデータを削除しますか?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("削除して最初からにする", role: .destructive) { model.deleteAllData() }
            } message: {
                Text("コミット・記録・ストリーク・設定が消え、ロックと区間の登録も外れます。元に戻せません。")
            }
        }
    }

    private var depositStatus: String {
        if let week = deposit.current {
            let b = deposit.breakdown(for: week)
            return "\(Fmt.yen(week.total))を預けています(返金 \(Fmt.yen(b.returned + b.returning)))"
        }
        if deposit.renewalProblem != nil { return "自動で預けられませんでした" }
        return deposit.connected ? "いまは預けていません" : "使っていません"
    }

    // MARK: ロック

    private var lockSection: some View {
        Section {
            NavigationLink("ロック対象と常に許可") { TargetsSettingsView() }
            NavigationLink {
                ScheduleSettingsView()
            } label: {
                HStack {
                    Text("ロックモード")
                    Spacer()
                    Text(modeLabel).foregroundStyle(Theme.muted)
                }
            }
            NavigationLink {
                DayStartSettingsView()
            } label: {
                HStack {
                    Text("日付切替")
                    Spacer()
                    Text(Fmt.hm(minuteOfDay: model.state?.schedule.dayStartMinute ?? 240)).foregroundStyle(Theme.muted)
                    if model.decision?.reason != .paused {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            Toggle("ロック中はアプリ内課金も止める", isOn: Binding(
                get: { model.state?.options.denyInAppPurchases ?? true },
                set: { model.report(model.setDenyInAppPurchases($0)) }
            ))
            NavigationLink("休養日") { RestDaysView() }
        } header: {
            Text("ロック")
        }
    }

    private var modeLabel: String {
        switch model.state?.schedule.mode {
        case .morning?: return "朝から"
        case .evening(let m)?: return "夕方から \(Fmt.hm(minuteOfDay: m))"
        case .earn(let w)?: return "稼働型 \(Fmt.duration(minutes: w))"
        case nil: return "—"
        }
    }

    // MARK: 最小版・休養日の上限

    private var quotaSection: some View {
        Section {
            Stepper(value: Binding(
                get: { model.settings.minimumWeeklyQuota },
                set: { model.report(model.setMinimumQuota($0)) }
            ), in: 0...7) {
                HStack {
                    Text("最小版")
                    Spacer()
                    Text("週\(model.settings.minimumWeeklyQuota)回まで").foregroundStyle(Theme.muted)
                }
            }
            Stepper(value: Binding(
                get: { model.settings.restWeeklyQuota },
                set: { model.report(model.setRestQuota($0)) }
            ), in: 0...3) {
                HStack {
                    Text("休養日")
                    Spacer()
                    Text("週\(model.settings.restWeeklyQuota)日まで").foregroundStyle(Theme.muted)
                }
            }
        } header: {
            Text("上限")
        } footer: {
            Text("増やすのは「ゆるめる変更」(達成後に受け付け、翌日から)。減らすのはすぐ効きます。")
        }
    }

    // MARK: 状態

    private var statusSection: some View {
        Section("このアプリについて") {
            InfoRow(title: "Screen Time の許可", value: model.screenTimeApproved ? "あり" : "なし")
            InfoRow(title: "通知", value: model.notificationsAllowed ? "許可" : "未許可")
            InfoRow(title: "App Group", value: model.usesAppGroup ? AppGroup.identifier : "使えていない")
            InfoRow(title: "バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
        }
    }
}

/// ロック対象と常に許可の変更
struct TargetsSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LockTargets()
    @State private var confirmed = false
    @State private var loaded = false

    var body: some View {
        Form {
            TargetsEditor(targets: $draft, confirmed: $confirmed)
            Section {
                Text("対象を増やす・常に許可を減らすのはすぐ効きます。対象を減らす・常に許可を増やすのは「ゆるめる変更」で、達成後に受け付けて翌日から反映します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle("ロック対象")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let result = model.updateTargets(draft)
                    model.report(result)
                    if case .rejected = result { return }
                    dismiss()
                }
                .disabled(!confirmed || !draft.problems.isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = model.targets
            loaded = true
        }
    }
}

/// ロックモードとロック開始の変更
struct ScheduleSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var modeKind: LockMode.Kind = .morning
    @State private var lockStart = 21 * 60
    @State private var earnWindow = 180
    @State private var loaded = false

    private var dayStart: Int { model.state?.schedule.dayStartMinute ?? 240 }

    private var mode: LockMode {
        switch modeKind {
        case .morning: return .morning
        case .evening: return .evening(lockStartMinute: lockStart)
        case .earn: return .earn(windowMinutes: earnWindow)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("ロックモード", selection: $modeKind) {
                    Text("朝からロック").tag(LockMode.Kind.morning)
                    Text("夕方からロック").tag(LockMode.Kind.evening)
                    Text("稼働型(勉強で時間を稼ぐ)").tag(LockMode.Kind.earn)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                switch modeKind {
                case .evening:
                    MinuteChoicePicker(title: "ロック開始", choices: MinuteChoicePicker.lockStartChoices(dayStart: dayStart),
                                       minute: $lockStart)
                case .earn:
                    Picker("1回で使える時間", selection: $earnWindow) {
                        ForEach(Array(stride(from: 30, through: 360, by: 30)), id: \.self) { m in
                            Text(Fmt.duration(minutes: m)).tag(m)
                        }
                    }
                case .morning:
                    EmptyView()
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("ロックモード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let result = model.updateSchedule(ScheduleConfig(dayStartMinute: dayStart, mode: mode))
                    model.report(result)
                    if case .rejected = result { return }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded, let schedule = model.state?.schedule else { return }
            loaded = true
            lockStart = MinuteChoicePicker.lockStartChoices(dayStart: schedule.dayStartMinute)
                .first { $0 == 21 * 60 } ?? MinuteChoicePicker.lockStartChoices(dayStart: schedule.dayStartMinute).last ?? 21 * 60
            switch schedule.mode {
            case .morning:
                modeKind = .morning
            case .evening(let m):
                modeKind = .evening
                lockStart = m
            case .earn(let w):
                modeKind = .earn
                earnWindow = w
            }
        }
    }

    private var footer: String {
        let rule = "モードの変更は翌日から。ロック開始を早めるのはすぐ効き、遅らせるのは「ゆるめる変更」です。"
        switch modeKind {
        case .morning:
            return "日付切替と同時にロックし、達成したら次の日付切替まで外れます。\n" + rule
        case .evening:
            return "ロック開始までに達成していなければ、その時刻からロック。前の日が未達成なら、朝からロックします。\n" + rule
        case .earn:
            return "いつもはロックしておき、チェックインするたびに決めた時間だけ外れます(バイト感覚)。チェックインはタイマー・写真・使用時間など計れる方法だけ。その日の最初の1回で、連続記録は達成になります。\n" + rule
        }
    }
}

/// 日付切替(一時停止中だけ変えられる)
struct DayStartSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minute = 240

    var body: some View {
        let paused = model.decision?.reason == .paused
        Form {
            Section {
                MinuteChoicePicker(title: "日付切替", choices: MinuteChoicePicker.dayStartChoices, minute: $minute)
                    .disabled(!paused)
            } footer: {
                Text(paused
                     ? "区切りが動くと記録の意味が変わるため、一時停止中だけ変えられます。"
                     : "日付切替は一時停止中だけ変えられます(区切りが動くと記録の意味が変わるため)。一時停止は「設定 › 一時停止・見守りモード」から。")
            }
        }
        .navigationTitle("日付切替")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard var schedule = model.state?.schedule else { return }
                    schedule.dayStartMinute = minute
                    if case .evening(let m) = schedule.mode, !SchedulePlanner.isValidLockStart(m, dayStartMinute: minute) {
                        let fallback = MinuteChoicePicker.lockStartChoices(dayStart: minute).last ?? 21 * 60
                        schedule.mode = .evening(lockStartMinute: fallback)
                    }
                    let result = model.updateSchedule(schedule)
                    model.report(result)
                    if case .rejected = result { return }
                    dismiss()
                }
                .disabled(!paused)
            }
        }
        .onAppear { minute = model.state?.schedule.dayStartMinute ?? 240 }
    }
}

/// リマインドの時刻と静かな時間帯
struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var minutes: [Int] = []
    @State private var quietStart = 23 * 60
    @State private var quietEnd = 7 * 60
    @State private var newMinute = 18 * 60
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                ForEach(minutes, id: \.self) { m in
                    Text(Fmt.hm(minuteOfDay: m))
                }
                .onDelete { offsets in
                    minutes.remove(atOffsets: offsets)
                    commit()
                }
                if minutes.count < 4 {
                    HStack {
                        MinuteChoicePicker(title: "追加", choices: MinuteChoicePicker.anyTimeChoices, minute: $newMinute)
                        Button("追加") {
                            if !minutes.contains(newMinute) { minutes = (minutes + [newMinute]).sorted() }
                            commit()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("時刻(1日4回まで)")
            } footer: {
                Text("達成した日は鳴りません。未達成が1〜2日続いた日だけ、最初のリマインドの1時間後に1回足します。3日続いたら逆に足しません。")
            }
            Section {
                MinuteChoicePicker(title: "開始", choices: MinuteChoicePicker.anyTimeChoices, minute: $quietStart)
                MinuteChoicePicker(title: "終了", choices: MinuteChoicePicker.anyTimeChoices, minute: $quietEnd)
            } header: {
                Text("静かな時間帯")
            } footer: {
                Text("この時間帯には通知しません(睡眠を守るため)。")
            }
        }
        .navigationTitle("リマインド")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            minutes = model.settings.reminderMinutes.sorted()
            quietStart = model.settings.quietStartMinute
            quietEnd = model.settings.quietEndMinute
        }
        .onChange(of: quietStart) { _, _ in if loaded { commit() } }
        .onChange(of: quietEnd) { _, _ in if loaded { commit() } }
    }

    private func commit() {
        model.updateReminders(minutes: minutes, quietStart: quietStart, quietEnd: quietEnd)
    }
}

/// 休養日のカレンダー(翌サイクル以降・週の上限まで・ロックが外れているときだけ置ける)
struct RestDaysView: View {
    @Environment(AppModel.self) private var model
    @State private var date = Date().addingTimeInterval(86_400)

    var body: some View {
        let cal = model.cycleCalendar
        let current = model.currentCycle
        let restDays = (model.state?.restDays ?? []).filter { $0 >= current }.sorted()
        Form {
            Section {
                DatePicker("日付", selection: $date, in: Date()..., displayedComponents: .date)
                Button("休養日にする") {
                    let c = Fmt.calendar.dateComponents([.year, .month, .day], from: date)
                    let day = CycleID(year: c.year ?? current.year, month: c.month ?? current.month, day: c.day ?? current.day)
                    model.addRestDay(day)
                }
            } header: {
                Text("休養日を置く")
            } footer: {
                Text("明日以降の日にだけ置けます。週\(model.settings.restWeeklyQuota)日まで(月曜はじまり)。ロックが外れているときに置けます。休養日はロックせず、ストリークも途切れません。")
            }
            Section("予定している休養日") {
                if restDays.isEmpty {
                    Text("ありません").foregroundStyle(Theme.muted)
                }
                ForEach(restDays, id: \.self) { day in
                    HStack {
                        Text(Fmt.cycle(day, dayStartMinute: cal.dayStartMinute))
                        Spacer()
                        if day > current {
                            Button("外す", role: .destructive) { model.removeRestDay(day) }
                                .buttonStyle(.borderless)
                        } else {
                            Text("今日").foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .navigationTitle("休養日")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 回避ログと出来事(事実だけを中立に並べる)
struct EventLogView: View {
    @Query(sort: \EventLog.at, order: .reverse) private var events: [EventLog]

    var body: some View {
        List {
            if events.isEmpty {
                Text("まだ記録はありません。").foregroundStyle(Theme.muted)
            }
            ForEach(events.prefix(500)) { event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Self.label(for: event.kind))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.isAvoidance(event.kind) ? Theme.seal : Theme.muted)
                        Spacer()
                        Text(Fmt.dateTime(event.at)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Text(event.detail).font(.subheadline)
                }
            }
        }
        .navigationTitle("回避ログと出来事")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func isAvoidance(_ kind: String) -> Bool {
        ["auth", "tamper", "reinstall", "recover"].contains(kind)
    }

    static func label(for kind: String) -> String {
        switch kind {
        case "lock": return "ロック"
        case "unlock": return "解除"
        case "checkin": return "チェックイン"
        case "undo": return "取り消し"
        case "emergency": return "緊急解除"
        case "pause": return "一時停止"
        case "rest": return "休養日"
        case "settings": return "設定"
        case "schedule": return "区間"
        case "auth": return "認可"
        case "tamper": return "時刻の改ざん"
        case "reinstall": return "再インストール"
        case "recover": return "復旧"
        case "setup": return "はじめの設定"
        case "usageIgnored": return "使用時間(無視)"
        case "error": return "エラー"
        default: return kind
        }
    }
}
