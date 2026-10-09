import SwiftUI
import SwiftData
import GoukakuCore

// 続ける工夫(仕様書 第8章):週次レビュー(3つだけ聞く)と、2週間続いたら一段上げる提案(提案だけ。強制しない)

extension AppModel {
    /// 先週のふり返りがまだなら、その週(月曜のサイクル)
    var weeklyReviewDue: CycleID? {
        _ = revision
        guard let state else { return nil }
        let cal = cycleCalendar
        let thisWeek = cal.weekStart(of: currentCycle)
        let lastWeek = cal.cycle(thisWeek, offsetBy: -7)
        // 先週の中に、使い始めてからの日が3日以上ある週だけ
        guard state.activeSince <= cal.cycle(lastWeek, offsetBy: 4) else { return nil }
        let done = fetchAll(WeeklyReview.self).contains { $0.weekStartRaw == lastWeek.description }
        return done ? nil : lastWeek
    }

    func saveWeeklyReview(week: CycleID, worked: String, difficulty: String, change: String) {
        context.insert(WeeklyReview(weekStart: week, worked: worked, difficulty: difficulty, change: change))
        log("review", "週のふり返り(\(Fmt.cycle(week, dayStartMinute: cycleCalendar.dayStartMinute))〜):難しさ \(difficulty)")
        save()
    }

    /// 2週間続いたら、一段上げる提案を出す(閉じたら2週間は出さない)
    var rampSuggestionDue: Bool {
        _ = revision
        guard state != nil else { return false }
        if let dismissed = settings.rampDismissedAt, Date().timeIntervalSince(dismissed) < 14 * 86_400 { return false }
        return stats().streak >= 14
    }

    func dismissRamp() {
        settings.rampDismissedAt = Date()
        save()
    }

    /// 週の結果(月〜日)
    func weekOutcomes(_ week: CycleID) -> [RecentDay] {
        let map = outcomeMap()
        let cal = cycleCalendar
        return (0..<7).map { i in
            let cycle = cal.cycle(week, offsetBy: i)
            return RecentDay(cycle: cycle, outcome: map[cycle] ?? .notStarted)
        }
    }
}

struct WeeklyReviewCard: View {
    let week: CycleID
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "text.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Theme.seal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("先週のふり返り(3つだけ)")
                        .font(Theme.heading(.headline))
                        .foregroundStyle(Theme.ink)
                    Text("何が効いたか・難しさ・来週変えること。1分で終わります。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.rule))
        }
        .buttonStyle(.plain)
    }
}

struct WeeklyReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionModel.self) private var companion
    @Environment(\.dismiss) private var dismiss
    let week: CycleID
    @State private var worked = ""
    @State private var difficulty = "right"
    @State private var change = ""
    @State private var letter = ""
    @State private var letterState = LetterState.none

    enum LetterState { case none, writing, done }

    var body: some View {
        let days = model.weekOutcomes(week)
        let achieved = days.filter { $0.outcome == .achieved || $0.outcome == .minimum }.count
        let judged = days.filter { [.achieved, .minimum, .missed].contains($0.outcome) }.count
        Form {
            Section {
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            MarkView(outcome: day.outcome.mark, size: 18)
                            Text(Fmt.weekdaySymbols[model.cycleCalendar.weekday(of: day.cycle) - 1])
                                .font(.caption2).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(judged == 0 ? "予定のあった日はありませんでした" : "予定 \(judged)日のうち \(achieved)日 達成")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
            } header: {
                Text("\(week.month)/\(week.day) からの1週間")
            }
            Section {
                switch letterState {
                case .none:
                    Button {
                        letterState = .writing
                        companion.weeklyLetter(week: week) { text, finished in
                            letter = text
                            if finished { letterState = .done }
                        }
                    } label: {
                        Label("相棒に手紙を書いてもらう", systemImage: "envelope")
                    }
                    .tint(Theme.pencil)
                case .writing:
                    PencilNote(text: letter, caption: "相棒からの手紙", writing: true)
                case .done:
                    PencilNote(text: letter, caption: "相棒からの手紙")
                }
            } footer: {
                Text("この週の体験から、相棒が手紙を書きます。")
            }
            Section("何が効いた?") {
                TextField("例:朝いちばんにやると決めたこと", text: $worked, axis: .vertical)
            }
            Section("難しさは?") {
                Picker("難しさ", selection: $difficulty) {
                    Text("易しすぎ").tag("easy")
                    Text("ちょうど").tag("right")
                    Text("きつい").tag("hard")
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: difficulty)
            }
            Section("来週変えることは?") {
                TextField("例:最小版を先に決めておく", text: $change, axis: .vertical)
            }
            if difficulty == "hard" {
                Section {
                    NavigationLink("目標を下げる(コミットを編集)") { CommitListView() }
                    NavigationLink("休養日を置く") { RestDaysView() }
                } header: {
                    Text("きついときは")
                } footer: {
                    Text("目標を下げるのは「ゆるめる変更」なので、今日の達成後に受け付けて翌日から反映します。最小版を使うのも手です。")
                }
            } else if difficulty == "easy" {
                Section {
                    NavigationLink("確認方法を上げる・曜日を増やす") { CommitListView() }
                } header: {
                    Text("易しすぎるなら")
                } footer: {
                    Text("一段だけ上げるのがおすすめです。上げる変更はすぐ効きます。")
                }
            }
        }
        .navigationTitle("週のふり返り")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("あとで") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("記録する") {
                    model.saveWeeklyReview(week: week, worked: worked, difficulty: difficulty, change: change)
                    dismiss()
                }
            }
        }
    }
}

/// 2週間続いたら「一段上げる」を提案する(提案だけ。強制しない)
struct RampCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        RuledBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("2週間続きました。一段上げてみる?")
                    .font(Theme.heading(.headline))
                    .foregroundStyle(Theme.ink)
                Text("どれか1つだけがおすすめです。今のままでも十分です。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { CommitListView() } label: {
                        Label("確認方法を上げる(タイマー・写真)", systemImage: "arrow.up.circle")
                    }
                    NavigationLink { CommitListView() } label: {
                        Label("曜日を増やす", systemImage: "calendar.badge.plus")
                    }
                    NavigationLink { ScheduleSettingsView() } label: {
                        Label("稼働型を試す(勉強でお金を使える時間を稼ぐ)", systemImage: "hourglass")
                    }
                }
                .font(.subheadline)
                Button("今はこのまま") { model.dismissRamp() }
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}
