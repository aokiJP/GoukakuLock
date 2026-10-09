#if DEBUG
import SwiftUI
import SwiftData
import DeviceActivity
import ManagedSettings
import GoukakuCore
import GoukakuKit
import GoukakuShared

/// デバッグメニュー(DEBUG ビルドだけ。第14章・第19.3節の実機テスト用)
struct DebugMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(AIRuntime.self) private var runtime
    @AppStorage("debug.sampleAI") private var sampleAI = false
    @State private var dayStartMinute = 240
    @State private var output = ""
    @State private var logURL: URL?

    private var minuteNow: Int {
        let c = Fmt.calendar.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        Form {
            Section {
                Stepper("日付切替:\(Fmt.hm(minuteOfDay: dayStartMinute))", value: $dayStartMinute, in: 0...1439, step: 5)
                Button("「今から20分後」に合わせる") { dayStartMinute = (minuteNow + 20) % 1440 }
                Button("この時刻を日付切替にする") { model.debugSetDayStart(dayStartMinute) }
            } header: {
                Text("日付切替を任意の時刻にする")
            } footer: {
                Text("T-01・T-02 用。区切りが動くので、記録の意味は変わります。")
            }
            Section {
                Toggle("緊急解除を短くする(待機1分・解除15分)", isOn: Binding(
                    get: { model.settings.debugShortEmergency },
                    set: {
                        model.settings.debugShortEmergency = $0
                        model.save()
                    }
                ))
            } footer: {
                Text("T-03 用。次の申請から効きます。")
            }
            Section("判定とロック") {
                Button("今すぐ判定") {
                    model.reconcile(source: "debug")
                    output = "判定:\(describe(model.decision))"
                }
                Button("ロックを外す(判定はそのまま)") {
                    ManagedSettingsStore(named: .moneyLock).clearAllSettings()
                    output = "ManagedSettings を消しました。対象アプリを1分以上使うと、トリップワイヤーで戻るはずです(T-05)。"
                }
                Button("起動時の処理を実行") {
                    Task {
                        await model.onLaunchOrForeground()
                        output = "起動時の処理を実行しました。判定:\(describe(model.decision))"
                    }
                }
                Button("毎日の区間を登録し直す") {
                    model.ensureDailyRegistration(force: true)
                    output = model.registrationError.map { "失敗:\($0)" } ?? "登録しました。"
                }
            }
            Section("見本") {
                NavigationLink("ウィジェット・Live Activity・お祝い") { DebugGalleryView() }
            }
            Section {
                Toggle("見本のAIを使う(画面の確認用)", isOn: $sampleAI)
                    .onChange(of: sampleAI) { _, _ in runtime.refresh() }
                Button("休ませているモデルを、すべて戻す") {
                    for m in runtime.installed { runtime.retry(m) }
                    output = "戻しました:\(runtime.statusLine)"
                }
                Button("いまのAIの様子") {
                    let p = runtime.profile
                    output = """
                    AI: \(runtime.statusLine) / \(runtime.phase)
                    理由: \(runtime.decision.reasons.joined(separator: " / "))
                    メモリ: \(DeviceProbe.gb(p.physicalMemory)) 使える見込み: \(p.availableMemory.map(DeviceProbe.gb) ?? "-")
                    熱: \(p.thermal.label) 低電力: \(p.lowPowerMode) Apple Intelligence: \(p.appleIntelligence.label)
                    入っているモデル: \(runtime.installed.map { "\($0.name)(\($0.manifest.source.rawValue))" }.joined(separator: ", "))
                    速さ: \(runtime.lastTokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "-")
                    """
                }
            } header: {
                Text("相棒AI")
            } footer: {
                Text("シミュレータでは MLX が動かないので、見本のAI(Gemma 4 E2B の出力をもとにした決まった文)で画面の流れを確かめられます。")
            }
            Section("中身を見る") {
                Button("state.json") { output = stateJSON() }
                Button("受信箱") { output = inboxText() }
                Button("登録中の区間") { output = activitiesText() }
                Button("App Group") {
                    output = "identifier: \(AppGroup.identifier)\ncontainer: \(AppGroup.containerURL?.path ?? "nil")\n使用中: \(model.store.directory.path)"
                }
            }
            if !output.isEmpty {
                Section("結果") {
                    Text(output)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section("ログ") {
                Button("ログを書き出す") { logURL = writeLog() }
                if let logURL {
                    ShareLink(item: logURL) { Label("共有", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("デバッグ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { dayStartMinute = model.state?.schedule.dayStartMinute ?? 240 }
    }

    private func describe(_ decision: LockDecision?) -> String {
        guard let d = decision else { return "なし(state.json がない)" }
        return "\(d.shouldLock ? "ロック" : "解除") \(d.reason) cycle=\(d.cycle) next=\(d.nextCheck.map { Fmt.dateTime($0) } ?? "-")"
    }

    private func stateJSON() -> String {
        guard let state = try? model.store.load() else { return "state.json を読めません" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? "書き出せません"
    }

    private func inboxText() -> String {
        let entries = model.store.readInbox()
        if entries.isEmpty { return "受信箱は空です" }
        return entries.map { entry in
            switch entry.item {
            case .achievement(let a): return "達成 \(a.cycle) \(a.habitID.uuidString.prefix(8)) \(a.kind.rawValue) \(Fmt.dateTime(a.at))"
            case .log(let l): return "ログ \(Fmt.dateTime(l.at)) \(l.kind) \(l.detail)"
            }
        }.joined(separator: "\n")
    }

    private func activitiesText() -> String {
        let center = DeviceActivityCenter()
        let names = center.activities
        if names.isEmpty { return "登録中の区間はありません" }
        return names.map { name in
            guard let schedule = center.schedule(for: name) else { return name.rawValue }
            let s = schedule.intervalStart, e = schedule.intervalEnd
            return "\(name.rawValue): \(s.hour ?? 0):\(String(format: "%02d", s.minute ?? 0)) 〜 \(e.hour ?? 0):\(String(format: "%02d", e.minute ?? 0))\(schedule.repeats ? " 毎日" : "")"
        }.joined(separator: "\n")
    }

    private func writeLog() -> URL? {
        let events = model.fetchAll(EventLog.self).sorted { $0.at < $1.at }
        let text = events.map { "\(Fmt.dateTime($0.at))\t\($0.kind)\t\($0.detail)" }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("goukakulock-log.txt")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)).map { url }
    }
}

/// ウィジェット・Live Activity・お祝いの見本(シミュレータの画面確認用)
struct DebugGalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    var body: some View {
        let now = Date()
        let current = model.widgetPreviewEntry(now: now)
        let sample = StatusEntry.sample(date: now)
        List {
            Section("ウィジェット(いまの状態)") {
                WidgetPreviewFrame(entry: current, family: .systemSmall)
                WidgetPreviewFrame(entry: current, family: .systemMedium)
                HStack(spacing: 12) {
                    WidgetPreviewFrame(entry: current, family: .accessoryCircular)
                    WidgetPreviewFrame(entry: current, family: .accessoryRectangular)
                }
                WidgetPreviewFrame(entry: current, family: .accessoryInline)
            }
            Section("ウィジェット(見本:ロック中)") {
                WidgetPreviewFrame(entry: sample, family: .systemSmall)
                WidgetPreviewFrame(entry: sample, family: .systemMedium)
                HStack(spacing: 12) {
                    WidgetPreviewFrame(entry: sample, family: .accessoryCircular)
                    WidgetPreviewFrame(entry: sample, family: .accessoryRectangular)
                }
            }
            Section("Live Activity") {
                ForEach(Self.activityStates(now: now), id: \.self) { state in
                    LiveActivityContentView(state: state)
                        .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 18))
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }
            }
            Section("記録の画面(見本)") {
                NavigationLink("集中タイマー(見本)") {
                    FocusTimerView(habit: Self.sampleHabit(.timer), fullMinutes: 25, minimumMinutes: 5, strict: false)
                }
                NavigationLink("写真で記録(見本)") {
                    PhotoCheckInView(habit: Self.sampleHabit(.photo))
                }
                NavigationLink("使用時間(見本)") {
                    UsageInfoView(habit: Self.sampleHabit(.appUsage))
                }
            }
            Section("お祝い・合格証・ふり返り") {
                Button("はなまるを出す(7日連続)") {
                    model.celebration = Celebration(streak: 7, total: 12, first: false)
                }
                Button("はじめての合格を出す") {
                    model.celebration = Celebration(streak: 1, total: 1, first: true)
                }
                Button("週のふり返りを開く") { showReview = true }
                CertificateCard(streak: 30, total: 41, goal: "英単語20個を覚えて、自作テストで7割", date: now)
                    .scaleEffect(0.8)
                    .frame(width: 288, height: 360)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("見本")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReview) {
            NavigationStack {
                WeeklyReviewView(week: model.cycleCalendar.cycle(model.cycleCalendar.weekStart(of: model.currentCycle), offsetBy: -7))
            }
        }
    }

    static func sampleHabit(_ method: VerificationMethod) -> HabitSnapshot {
        let title: String
        switch method {
        case .timer: title = "テキストを25分集中して進める"
        case .photo: title = "自主メニューをこなす"
        default: title = "語学アプリで15分学ぶ"
        }
        return HabitSnapshot(title: title, minimumTitle: method == .appUsage ? nil : "5分だけ",
                             method: method, targetMinutes: method == .photo ? nil : (method == .timer ? 25 : 15),
                             activeFrom: CycleID(year: 2026, month: 1, day: 1))
    }

    static func activityStates(now: Date) -> [GoukakuActivityAttributes.ContentState] {
        [
            .init(kind: .emergency, title: "緊急解除", startsAt: now.addingTimeInterval(600), endsAt: now.addingTimeInterval(600 + 7200)),
            .init(kind: .emergency, title: "緊急解除", startsAt: now.addingTimeInterval(-1800), endsAt: now.addingTimeInterval(5400)),
            .init(kind: .focus, title: "テキストを25分集中して進める", startsAt: now.addingTimeInterval(-420), endsAt: now.addingTimeInterval(1080)),
            .init(kind: .focus, title: "テキストを25分集中して進める", startsAt: now.addingTimeInterval(-420), endsAt: now.addingTimeInterval(1080), pausedRemaining: 1080),
            .init(kind: .earn, title: "解除中", startsAt: now.addingTimeInterval(-600), endsAt: now.addingTimeInterval(10200)),
        ]
    }
}

extension AppModel {
    /// デバッグ:日付切替を任意の時刻(分)にする
    func debugSetDayStart(_ minute: Int) {
        do {
            try actions.debugSetDayStart(minute: minute)
        } catch {
            show(error: error)
            return
        }
        log("debug", "日付切替を \(Fmt.hm(minuteOfDay: minute)) に変更(デバッグ)")
        save()
        reload()
        ensureDailyRegistration(force: true)
        reconcile(source: "debugDayStart")
        rebuildReminders()
    }
}
#endif
