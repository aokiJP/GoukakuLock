import SwiftUI
import GoukakuCore

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
            CommitEditView(draft: HabitDraft(habit: habit))
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
                InfoRow(title: "確認方法", value: "自己申告(一言メモ)")
            } footer: {
                Text("必須をすべて達成するとロックが外れます(必須は3つまで)。任意は記録だけです。写真・タイマーなどの確認方法はフェーズ2で追加予定です。")
            }
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
