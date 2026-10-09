import SwiftUI
import GoukakuCore

/// S-03 チェックイン(自己申告:一言メモは5文字以上)
struct CheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: HabitSnapshot
    @State private var note = ""
    @State private var useMinimum = false
    @State private var recorded: Achievement?
    @FocusState private var noteFocused: Bool

    private var trimmedCount: Int { note.trimmingCharacters(in: .whitespacesAndNewlines).count }

    /// 表示する側で NavigationStack に入れる(シートなら包む・一覧からなら push)
    var body: some View {
        Group {
            if let recorded {
                doneView(recorded)
            } else {
                form
            }
        }
        .navigationTitle("チェックイン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
    }

    private var form: some View {
        let remaining = max(0, model.settings.minimumWeeklyQuota - model.minimumUsesThisWeek())
        return Form {
            Section {
                Text(habit.title)
                    .font(Theme.heading(.title3))
                    .foregroundStyle(Theme.ink)
                if let criteria = model.habit(habit.id)?.criteriaNote, !criteria.isEmpty {
                    Text("合格ライン:\(criteria)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            Section {
                TextField("例:単語20個、自作テストで8割", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($noteFocused)
                HStack {
                    Spacer()
                    Text("\(trimmedCount) / 5文字以上")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(trimmedCount >= 5 ? Theme.muted : Theme.seal)
                }
            } header: {
                Text("やったこと")
            } footer: {
                Text("ワンタップでは記録できません。書いたことは履歴で見返せます。")
            }
            if let minimum = habit.minimumTitle {
                Section {
                    Toggle(isOn: $useMinimum) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最小版で記録する")
                            Text("最小版:\(minimum)").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .disabled(remaining == 0)
                } footer: {
                    Text("今週あと\(remaining)回使えます。ロックは外れ、ストリークも続きます。履歴には「最小」と残ります。")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(useMinimum ? "最小版で記録する" : "記録する") {
                record()
            }
            .buttonStyle(SealButtonStyle())
            .disabled(trimmedCount < 5)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .onAppear { noteFocused = true }
    }

    private func record() {
        guard let achievement = model.checkIn(habit: habit, minimum: useMinimum, note: note) else { return }
        noteFocused = false
        if reduceMotion {
            recorded = achievement
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                recorded = achievement
            }
        }
    }

    private func doneView(_ achievement: Achievement) -> some View {
        let pending = model.today?.pendingRequired.count ?? 0
        return VStack(spacing: 18) {
            Spacer()
            SealView(text: achievement.kind == .minimum ? "可" : "合格", color: Theme.seal, filled: true, size: 128)
                .transition(reduceMotion ? .opacity : .scale(scale: 1.7).combined(with: .opacity))
            Text(achievement.kind == .minimum ? "最小版で記録しました" : "記録しました")
                .font(Theme.heading())
                .foregroundStyle(Theme.ink)
            Group {
                if model.decision?.todaySatisfied == true {
                    Text("今日の必須コミットをすべて達成しました。お金を使うアプリのロックが外れています。")
                } else if pending > 0 {
                    Text("残りの必須コミット:\(pending)件")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = Int(300 - context.date.timeIntervalSince(achievement.at))
                if left > 0 {
                    Button("取り消す(あと \(left / 60):\(String(format: "%02d", left % 60)))") {
                        if model.undoCheckIn(achievement.id) {
                            recorded = nil
                        }
                    }
                    .font(.subheadline)
                    .tint(Theme.muted)
                }
            }
            Button("閉じる") { dismiss() }
                .buttonStyle(SealButtonStyle())
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
}

/// 通知から開いたとき:今日のコミットから選ぶ
struct CheckInPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let today = model.today {
                    let candidates = today.required + today.optional
                    if candidates.isEmpty {
                        Text("今日のサイクルに予定されたコミットはありません。")
                    } else {
                        ForEach(candidates) { habit in
                            if today.isDone(habit.id) {
                                Label(habit.title, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.muted)
                            } else {
                                NavigationLink {
                                    CheckInView(habit: habit)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(habit.title).foregroundStyle(Theme.ink)
                                        Text(habit.isRequired ? "必須" : "任意").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("チェックイン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
