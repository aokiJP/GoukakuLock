import SwiftUI
import FamilyControls
import GoukakuCore
import GoukakuKit
import GoukakuAI

/// S-01 はじめの設定
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AIRuntime.self) private var runtime
    @Environment(CompanionModel.self) private var companion
    @State private var step = Step.intro
    @State private var aboutMe = ""
    @State private var draft: OnboardingDraft = {
        var draft = OnboardingDraft()
        #if DEBUG
        // UI テスト(シミュレータでのスクリーンショット)用に、最初のコミットを埋めておく
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            draft.habit.title = "英単語20個を覚えて、自作テストで7割"
            draft.habit.criteriaNote = "自作テストで7割"
            draft.habit.minimumTitle = "単語5個"
        }
        #endif
        return draft
    }()
    @State private var authMessage: String?
    @State private var authorizing = false
    @State private var notificationAnswered = false
    @State private var confirmStartNow = false
    @State private var saving = false
    #if DEBUG
    @State private var skippedAuthorization = false
    #endif

    enum Step: Int, CaseIterable {
        case intro, companion, screenTime, notifications, targets, schedule, commit, start, placement

        var title: String {
            switch self {
            case .intro: return "合格ロック"
            case .companion: return "相棒AI"
            case .screenTime: return "Screen Time の許可"
            case .notifications: return "通知"
            case .targets: return "ロックするもの"
            case .schedule: return "時刻とモード"
            case .commit: return "最初のコミット"
            case .start: return "いつから始めるか"
            case .placement: return "置き場所"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .tint(Theme.seal)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .accessibilityLabel("手順 \(step.rawValue + 1) / \(Step.allCases.count)")
                stepContent
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .intro {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("戻る") { move(-1) }
                    }
                }
            }
            .alert("すぐにロックがかかります", isPresented: $confirmStartNow) {
                Button("今すぐ始める", role: .destructive) {
                    draft.startNow = true
                    move(1)
                }
                Button("明日から始める", role: .cancel) {
                    draft.startNow = false
                    move(1)
                }
            } message: {
                Text("今日のコミットを達成するまで、選んだアプリとアプリ内課金が使えなくなります。")
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .intro: introStep
        case .companion: companionStep
        case .screenTime: screenTimeStep
        case .notifications: notificationStep
        case .targets: targetsStep
        case .schedule: scheduleStep
        case .commit: commitStep
        case .start: startStep
        case .placement: placementStep
        }
    }

    private func move(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            step = Step(rawValue: step.rawValue + delta) ?? step
        }
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(SealButtonStyle())
            .disabled(!enabled)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
    }

    // MARK: 1. すること/しないこと・安全の床

    private var introStep: some View {
        Form {
            if model.reinstallDetectedAt != nil {
                Section {
                    Label("前回はロック中にアプリが削除されていました。回避ログに記録しました。", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
            }
            Section {
                HStack(alignment: .center, spacing: 16) {
                    SealView(text: "合格", color: Theme.seal, filled: true, size: 64)
                    Text("自分で決めた試験を、\n毎日の習慣にする。")
                        .font(Theme.heading(.title3))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 6)
            }
            Section("このアプリがすること") {
                Text("決めた時刻に、お金を使うアプリ(決済・買い物)とアプリ内課金を止めます。今日のコミットを達成したと記録すると外れます。")
                Text("お金は没収も送金もされません。使えなくなるだけです。")
                Text("相棒AIが、人生の中でどんな体験ができるかを一緒に見つけます。AIはこの iPhone の中だけで動きます。")
            }
            Section("しないこと") {
                Text("目標を勝手に決めたり、採点したりしません。相棒AIは体験を誘うだけで、やるかどうかも、確かめるのもあなたです。")
                Text("電話・メッセージ・緊急通報は止まりません。地図・乗換・銀行・連絡・医療は「常に許可」で守ります。")
                Text("監視・追跡・録音はしません。データはこの iPhone の中だけに置きます。")
            }
            Section("いつでも使える非常口") {
                Label("緊急解除:申請の15分後から2時間、ロックが外れます", systemImage: "clock.badge.exclamationmark")
                Label("一時停止:ロックをすべて止めます(ロック中は緊急解除を経てから)", systemImage: "pause.circle")
            }
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("わかった") { move(1) }
        }
    }

    // MARK: 2. 相棒AI(この iPhone で使うAIと、あなたのこと)

    private var companionStep: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    CategoryStamp(category: .first, filled: true, size: 56)
                    Text("人生の中で、\nどんな体験ができるだろう。")
                        .font(Theme.heading(.title3))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 6)
            }
            Section("相棒AIがすること") {
                Text("今のあなたに合いそうな体験を誘い、やってみたあとに短く返事をします。「〜しなければ」ではなく「〜してみると、〜かも」と誘います。")
                Text("決めるのはあなたです。点数はつけず、ほかの人と比べません。")
                Text("この iPhone の中だけで動きます。書いたことはどこにも送りません。")
            }
            Section {
                Label(runtime.statusLine, systemImage: runtime.usesAI ? "cpu" : "book.closed")
                    .foregroundStyle(Theme.pencil)
                if let reason = runtime.decision.reasons.first {
                    Text(reason).font(.footnote).foregroundStyle(Theme.muted)
                }
                if !runtime.usesAI, let spec = recommendedDownload {
                    if let job = runtime.downloader.jobs[spec.id] {
                        if case .failed(let why) = job.phase {
                            Text(why).font(.footnote).foregroundStyle(Theme.seal)
                        } else {
                            ProgressView(value: job.fraction) {
                                Text("「\(spec.name)」をダウンロード中(ほかの手順を進めて大丈夫です)").font(.footnote)
                            }
                            .tint(Theme.pencil)
                        }
                    } else {
                        Button {
                            runtime.download(spec)
                        } label: {
                            Label("「\(spec.name)」をダウンロード(\(DeviceProbe.gb(spec.downloadBytes)))", systemImage: "arrow.down.circle")
                        }
                        Text(spec.summary).font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
            } header: {
                Text("この iPhone で使うAI")
            } footer: {
                Text("メモリ・iOS・熱・電池の様子から、自動で選びます。あとから 設定 › AI で変えられます。")
            }
            Section {
                TextField("例:英語を勉強している・散歩が好き・いつか一人旅をしたい", text: $aboutMe, axis: .vertical)
            } header: {
                Text("あなたのこと(任意)")
            } footer: {
                Text("書いたことを相棒が覚えて、提案があなたに合っていきます。体験タブの「育ち」からいつでも消せます。")
            }
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("次へ") {
                if !aboutMe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    companion.rememberIntroduction(aboutMe)
                }
                move(1)
            }
        }
    }

    /// AIのモデルが入っていない端末に、まずおすすめするモデル(メモリに収まる中で日本語が一番自然なもの)
    private var recommendedDownload: ModelSpec? {
        let ram = Double(runtime.profile.physicalMemory) / 1_073_741_824 + 0.5
        return runtime.downloadable.filter { $0.recommendedRAMGB <= ram }.max { $0.japanese < $1.japanese }
    }

    // MARK: 3. Screen Time の許可

    private var screenTimeStep: some View {
        Form {
            Section {
                Text("この iPhone のアプリを、本人の許可(individual)で制限します。Face ID などで承認します。許可はいつでも「設定」から取り消せます。")
            }
            Section {
                if model.screenTimeApproved {
                    Label("許可されています", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.seal)
                } else {
                    Button {
                        Task {
                            authorizing = true
                            authMessage = await model.requestScreenTimeAuthorization()
                            authorizing = false
                        }
                    } label: {
                        HStack {
                            Text("許可する")
                            if authorizing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(authorizing)
                }
                if let authMessage {
                    Text(authMessage).font(.footnote).foregroundStyle(Theme.seal)
                    Text("許可しなかったときは、もう一度「許可する」を押すか、設定アプリの「スクリーンタイム」でこのアプリへのアクセスを許可してください。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            #if DEBUG
            Section {
                Button("許可なしで進む(デバッグ)") {
                    skippedAuthorization = true
                    move(1)
                }
            } footer: {
                Text("署名に Family Controls が入っていないと許可できません。画面の確認だけをするときに使います(ロックはかかりません)。")
            }
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("次へ", enabled: model.screenTimeApproved) { move(1) }
        }
        .task { await model.refreshPermissions() }
    }

    // MARK: 3. 通知

    private var notificationStep: some View {
        Form {
            Section {
                Text("シールドの「チェックインする」を押したときの案内と、リマインド(既定は12:00と20:00)に使います。")
            }
            Section {
                if notificationAnswered {
                    if model.notificationsAllowed {
                        Label("通知が許可されています", systemImage: "bell.badge")
                    } else {
                        Text("通知が許可されていません。シールドからの誘導とリマインドが使えません。あとから設定アプリで許可できます。")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Button("通知を許可する") {
                        Task {
                            _ = await AppModel.requestNotificationPermission()
                            await model.refreshPermissions()
                            notificationAnswered = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("次へ") { move(1) }
        }
    }

    // MARK: 4. ロック対象 → 常に許可 → 確認

    private var targetsStep: some View {
        Form {
            TargetsEditor(targets: $draft.targets, confirmed: $draft.confirmedSafety)
            #if DEBUG
            if skippedAuthorization {
                Section {
                    Button("対象を選ばずに進む(デバッグ)") {
                        draft.debugUIOnly = true
                        move(1)
                    }
                } footer: {
                    Text("Screen Time の許可がないと対象を選べません。画面の確認だけをするときに使います。")
                }
            }
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("次へ", enabled: draft.targets.problems.isEmpty && draft.confirmedSafety) { move(1) }
        }
    }

    // MARK: 5. 日付切替とロックモード

    private var scheduleStep: some View {
        Form {
            Section {
                MinuteChoicePicker(title: "日付切替", choices: MinuteChoicePicker.dayStartChoices,
                                   minute: $draft.dayStartMinute)
            } footer: {
                Text("アプリにとっての1日の境目。夜ふかしして日付をまたいでも、この時刻まではその日の達成に入ります。あとから変えられるのは一時停止中だけです。")
            }
            Section {
                Picker("ロックモード", selection: $draft.modeKind) {
                    Text("朝からロック").tag(LockMode.Kind.morning)
                    Text("夕方からロック").tag(LockMode.Kind.evening)
                }
                .pickerStyle(.segmented)
                if draft.modeKind == .evening {
                    MinuteChoicePicker(title: "ロック開始",
                                       choices: MinuteChoicePicker.lockStartChoices(dayStart: draft.dayStartMinute),
                                       minute: $draft.lockStartMinute)
                }
            } footer: {
                if draft.modeKind == .morning {
                    Text("日付切替と同時にロックし、達成したら次の日付切替まで外れます。「今日最初の支出の前にやる」が合図になります。")
                } else {
                    Text("ロック開始までに達成していなければ、その時刻からロックします。前の日が未達成なら、猶予なしで朝からロックします。")
                }
            }
            Section {
                Toggle("アプリ内課金も止める", isOn: $draft.denyInAppPurchases)
            } footer: {
                Text("ロック中は、すべてのアプリのアプリ内課金ができなくなります(おすすめ)。")
            }
        }
        .onChange(of: draft.dayStartMinute) { _, newValue in
            if !SchedulePlanner.isValidLockStart(draft.lockStartMinute, dayStartMinute: newValue) {
                draft.lockStartMinute = MinuteChoicePicker.lockStartChoices(dayStart: newValue).last ?? 21 * 60
            }
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("次へ", enabled: SchedulePlanner.isValid(draft.schedule)) { move(1) }
        }
    }

    // MARK: 6. 最初のコミット

    private var commitStep: some View {
        Form {
            Section {
                GoalTemplatePicker { template in
                    draft.habit.title = template.title
                    draft.habit.minimumTitle = template.minimum
                }
            } header: {
                Text("例から選ぶ(あとで書き換えられます)")
            }
            Section {
                TextField("例:英単語20個を覚えて、自作テストで7割", text: $draft.habit.title, axis: .vertical)
            } header: {
                Text("目標")
            } footer: {
                Text("中身はあなたが決めます。アプリは判定しません。")
            }
            Section("自分用の合格ライン(任意)") {
                TextField("例:7割で合格", text: $draft.habit.criteriaNote, axis: .vertical)
            }
            Section {
                TextField("例:単語5個", text: $draft.habit.minimumTitle)
            } header: {
                Text("最小版(任意)")
            } footer: {
                Text("調子が悪い日のための、小さい目標。使えるのは週2回まで(既定)。")
            }
            Section("曜日") {
                WeekdayPicker(selection: $draft.habit.weekdays)
            }
            Section {
                InfoRow(title: "確認方法", value: "自己申告(一言メモ)")
            } footer: {
                Text("最初の2週間は、軽い目標と自己申告で「できた」を積むのがおすすめです。集中タイマー・写真・学習アプリの使用時間で確かめる方法は、あとからコミットの編集で選べます。")
            }
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton("次へ", enabled: !draft.habit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && !draft.habit.weekdays.isEmpty) { move(1) }
        }
    }

    // MARK: 7. いつから始めるか

    private var startStep: some View {
        let cal = CycleCalendar(dayStartMinute: draft.dayStartMinute)
        let tomorrow = cal.start(of: cal.cycle(cal.cycle(containing: Date()), offsetBy: 1))
        return Form {
            Section {
                Button {
                    draft.startNow = false
                    move(1)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("明日の日付切替から(おすすめ)").font(.headline).foregroundStyle(Theme.ink)
                        Text("\(Fmt.clock(tomorrow)) から始まります。設定した直後に突然ロックされません。")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("start.tomorrow")
                Button {
                    confirmStartNow = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今すぐ").font(.headline).foregroundStyle(Theme.ink)
                        Text("すぐにロックがかかります。").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("start.now")
            }
        }
    }

    // MARK: 8. 置き場所の案内 → 保存

    private var placementStep: some View {
        Form {
            Section {
                Label("このアプリを、ホーム画面の1ページ目かドックに置いてください。", systemImage: "apps.iphone")
                Text("ロック中のアプリから本体を直接開くことはできません。シールドの「チェックインする」は通知で案内しますが、集中モードで通知が隠れることがあるため、すぐ開ける場所に置いておくと確実です。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Section("内容") {
                InfoRow(title: "開始", value: draft.startNow ? "今すぐ" : "明日の日付切替から")
                InfoRow(title: "ロック", value: model.describe(draft.schedule))
                InfoRow(title: "最初のコミット", value: draft.habit.title)
                InfoRow(title: "アプリ内課金", value: draft.denyInAppPurchases ? "ロック中は止める" : "止めない")
            }
            #if DEBUG
            if skippedAuthorization {
                Section {
                    Text("Screen Time の許可がないので、記録と画面だけが動き、ロックはかかりません(デバッグ)。")
                        .font(.footnote)
                }
            }
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            primaryButton(saving ? "保存しています…" : "はじめる", enabled: !saving) {
                saving = true
                if let problem = model.completeOnboarding(draft) {
                    model.show("始められません", problem)
                }
                saving = false
            }
        }
    }
}
