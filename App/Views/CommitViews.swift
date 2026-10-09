import SwiftUI
import FamilyControls
import GoukakuCore
import GoukakuKit

/// コミットの一覧
struct CommitListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.currentCycle
        let all = model.habits
        let active = all.filter { !$0.hasEnded(asOf: current) && ($0.activeFrom ?? current) <= current }
        let upcoming = all.filter { !$0.hasEnded(asOf: current) && ($0.activeFrom ?? current) > current }
        let ended = all.filter { $0.hasEnded(asOf: current) }
        List {
            if active.isEmpty && upcoming.isEmpty {
                Text("コミットがありません。右上の+から追加します。")
                    .foregroundStyle(Theme.muted)
            }
            if !active.isEmpty {
                Section("有効") {
                    ForEach(active) { habit in row(habit) }
                }
            }
            if !upcoming.isEmpty {
                Section("これから有効") {
                    ForEach(upcoming) { habit in row(habit) }
                }
            }
            if !model.pendingChanges.isEmpty {
                Section {
                    NavigationLink("予約中の変更(\(model.pendingChanges.count)件)") { PendingChangesView() }
                }
            }
            if !ended.isEmpty {
                Section("終了") {
                    ForEach(ended) { habit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.title).foregroundStyle(Theme.muted)
                            if let until = habit.activeUntil {
                                Text("\(Fmt.cycle(until, dayStartMinute: model.cycleCalendar.dayStartMinute))から無効")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("コミット")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CommitEditView(draft: HabitDraft())
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
        }
    }

    private func row(_ habit: Habit) -> some View {
        NavigationLink {
            CommitEditView(draft: HabitDraft(habit: habit, usageSelection:
                TargetsStore.loadUsageSelection(habitID: habit.id, from: model.store.directory)))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title).foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Text(habit.isRequired ? "必須" : "任意")
                    Text(Fmt.weekdays(Set(habit.weekdays)))
                    if !habit.minimumTitle.isEmpty { Text("最小版あり") }
                    if let until = habit.activeUntil {
                        Text("\(Fmt.cycle(until, dayStartMinute: model.cycleCalendar.dayStartMinute))で終了")
                    } else if let from = habit.activeFrom, from > model.currentCycle {
                        Text("\(Fmt.cycle(from, dayStartMinute: model.cycleCalendar.dayStartMinute))から")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// S-04 コミットの編集
struct CommitEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: HabitDraft
    @State private var confirmDelete = false
    @State private var hasGoalDate = false

    private var isNew: Bool { draft.id == nil }

    var body: some View {
        Form {
            if isNew {
                Section {
                    GoalTemplatePicker { template in template.apply(to: &draft) }
                } header: {
                    Text("例から選ぶ")
                }
            }
            Section {
                TextField("例:英単語20個を覚えて、自作テストで7割", text: $draft.title, axis: .vertical)
            } header: {
                Text("目標")
            } footer: {
                Text("中身はあなたが決めます。アプリは判定しません。")
            }
            Section("自分用の合格ライン(任意)") {
                TextField("例:7割で合格", text: $draft.criteriaNote, axis: .vertical)
            }
            Section {
                TextField("例:単語5個", text: $draft.minimumTitle)
            } header: {
                Text("最小版(任意)")
            } footer: {
                Text("調子が悪い日のための小さい目標。週\(model.settings.minimumWeeklyQuota)回まで使えます。")
            }
            Section("曜日") {
                WeekdayPicker(selection: $draft.weekdays)
            }
            Section {
                Toggle("必須", isOn: $draft.isRequired)
            } footer: {
                Text("必須をすべて達成するとロックが外れます(必須は3つまで)。任意は記録だけです。")
            }
            MethodEditor(draft: $draft)
            Section {
                TextField("例:TOEIC 700点・12月の試験", text: $draft.goalNote, axis: .vertical)
                Toggle("目標日を決める", isOn: $hasGoalDate)
                if hasGoalDate {
                    DatePicker("目標日", selection: Binding(
                        get: { draft.goalDate ?? Date() },
                        set: { draft.goalDate = $0 }
                    ), displayedComponents: .date)
                }
            } header: {
                Text("本当の目標(任意)")
            } footer: {
                Text("ロックには関係しないので、いつでも変えられます。")
            }
            Section {
                ruleNote
            }
            if !isNew {
                Section {
                    Button("このコミットを削除", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("削除は「緩める変更」です。受け付けたら翌日の日付切替から無効になります。")
                }
            }
        }
        .navigationTitle(isNew ? "コミットを追加" : "コミットを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.weekdays.isEmpty)
            }
        }
        .onAppear { hasGoalDate = draft.goalDate != nil }
        .onChange(of: hasGoalDate) { _, on in
            if !on { draft.goalDate = nil } else if draft.goalDate == nil { draft.goalDate = Date() }
        }
        .confirmationDialog("このコミットを削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                let result = model.deleteHabit(draft.id!)
                model.report(result)
                if case .rejected = result { return }
                dismiss()
            }
        }
    }

    @ViewBuilder private var ruleNote: some View {
        if isNew {
            Text("追加したコミットは、翌日の日付切替から有効です(今日の条件は途中で変えません)。")
                .font(.footnote).foregroundStyle(Theme.muted)
        } else if model.relaxBlocked {
            Label("ロック中です。文章の編集・曜日を減らす・任意にする・削除は「緩める変更」なので、今日のコミットを達成したあとに受け付け、翌日から反映します。", systemImage: "lock")
                .font(.footnote).foregroundStyle(Theme.muted)
        } else {
            Text("ロックに関わる変更は、翌日の日付切替から反映されます。")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private func save() {
        let result = model.saveHabit(draft)
        switch result {
        case .applied:
            dismiss()
        case .scheduled:
            model.report(result)
            dismiss()
        case .rejected:
            model.report(result)
        }
    }
}

/// 予約中の(翌サイクルから効く)変更
struct PendingChangesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            let pending = model.pendingChanges
            if pending.isEmpty {
                Text("予約中の変更はありません。").foregroundStyle(Theme.muted)
            }
            ForEach(pending) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.summary).foregroundStyle(Theme.ink)
                    if let cycle = change.effectiveCycle {
                        Text("\(Fmt.cycle(cycle, dayStartMinute: model.cycleCalendar.dayStartMinute))の日付切替のあと、アプリを開いたときに反映")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .swipeActions {
                    Button("取り消す", role: .destructive) { model.cancelPendingChange(change) }
                }
            }
        }
        .navigationTitle("予約中の変更")
    }
}

/// 確かめ方(自己申告・集中タイマー・写真・使用時間)
struct MethodEditor: View {
    @Binding var draft: HabitDraft
    @State private var pickingApps = false

    private func name(_ method: VerificationMethod) -> String {
        switch method {
        case .selfReport: return "自己申告(一言)"
        case .timer: return "集中タイマー"
        case .photo: return "写真"
        case .appUsage: return "使用時間(自動)"
        default: return AppModel.methodName(method)
        }
    }

    var body: some View {
        Section {
            Picker("確認方法", selection: $draft.method) {
                ForEach(HabitDraft.selectableMethods, id: \.self) { method in
                    Text(name(method)).tag(method)
                }
            }
            switch draft.method {
            case .timer:
                Stepper(value: Binding(get: { draft.targetMinutes ?? 25 }, set: { draft.targetMinutes = $0 }),
                        in: 5...180, step: 5) {
                    InfoRow(title: "目標", value: "\(draft.targetMinutes ?? 25)分")
                }
                if !draft.minimumTitle.isEmpty {
                    Stepper(value: $draft.minimumMinutes, in: 1...60) {
                        InfoRow(title: "最小版", value: "\(draft.minimumMinutes)分")
                    }
                }
                Toggle("厳格モード(離れたら0から)", isOn: $draft.strictTimer)
            case .appUsage:
                Button {
                    pickingApps = true
                } label: {
                    Label("学習アプリを選ぶ", systemImage: "square.grid.2x2")
                }
                .familyActivityPicker(isPresented: $pickingApps, selection: Binding(
                    get: { draft.usageSelection ?? FamilyActivitySelection() },
                    set: { draft.usageSelection = $0 }
                ))
                if let selection = draft.usageSelection {
                    TokenSummary(selection: selection)
                }
                Stepper(value: Binding(get: { draft.targetMinutes ?? 15 }, set: { draft.targetMinutes = $0 }),
                        in: 5...240, step: 5) {
                    InfoRow(title: "1日の合計", value: "\(draft.targetMinutes ?? 15)分")
                }
            default:
                EmptyView()
            }
        } header: {
            Text("確かめ方")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch draft.method {
        case .timer:
            return "このアプリを前に出している時間だけを数え、目標の分数で達成です。離れると止まります。実行中は画面を点けたままにします。"
        case .photo:
            return "アプリ内のカメラで撮った写真で記録します(ライブラリからは選べません・位置情報は保存しません・90日で消えます)。"
        case .appUsage:
            return "選んだアプリをその日の 23:59 までに合計で決めた分数使うと、アプリを開かなくても自動で達成になります(Screen Time の計測なので参考精度)。"
        default:
            return "「やったこと」を一言(5文字以上)書いて記録します。最初の2週間はこれがおすすめです。"
        }
    }
}

/// よくある目標の例(中身はあとで自由に書き換えられる)
struct GoalTemplate: Identifiable {
    let id: String
    let icon: String
    let title: String
    let minimum: String
    let method: VerificationMethod
    let minutes: Int?

    func apply(to draft: inout HabitDraft) {
        draft.title = title
        draft.minimumTitle = minimum
        draft.method = method
        draft.targetMinutes = minutes
    }

    static let all: [GoalTemplate] = [
        GoalTemplate(id: "英単語", icon: "character.book.closed", title: "英単語20個を覚えて、自作テストで7割", minimum: "5個だけ覚える", method: .selfReport, minutes: nil),
        GoalTemplate(id: "過去問", icon: "doc.text", title: "過去問を1回分解いて、答え合わせ", minimum: "1問だけ解く", method: .selfReport, minutes: nil),
        GoalTemplate(id: "集中勉強", icon: "timer", title: "テキストを25分集中して進める", minimum: "5分だけ開く", method: .timer, minutes: 25),
        GoalTemplate(id: "読書", icon: "book", title: "本を20ページ読む", minimum: "2ページ読む", method: .selfReport, minutes: nil),
        GoalTemplate(id: "語学アプリ", icon: "globe", title: "語学アプリで15分学ぶ", minimum: "", method: .appUsage, minutes: 15),
        GoalTemplate(id: "筋トレ", icon: "figure.strengthtraining.traditional", title: "自主メニューをこなす", minimum: "スクワット10回", method: .photo, minutes: nil),
        GoalTemplate(id: "楽器", icon: "music.note", title: "楽器を30分練習する", minimum: "5分だけ触る", method: .timer, minutes: 30),
        GoalTemplate(id: "プログラミング", icon: "chevron.left.forwardslash.chevron.right", title: "コードを1つ前に進める", minimum: "1行だけ書く", method: .selfReport, minutes: nil),
    ]
}

struct GoalTemplatePicker: View {
    var onPick: (GoalTemplate) -> Void
    @State private var picked: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GoalTemplate.all) { template in
                    Button {
                        picked = template.id
                        onPick(template)
                    } label: {
                        Label(template.id, systemImage: template.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(picked == template.id ? Color.white : Theme.ink)
                            .background(Capsule().fill(picked == template.id ? Theme.seal : Theme.paperSunken))
                            .overlay(Capsule().strokeBorder(picked == template.id ? Color.clear : Theme.rule))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .sensoryFeedback(.selection, trigger: picked)
    }
}
