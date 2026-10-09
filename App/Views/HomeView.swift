import SwiftUI
import GoukakuCore
import GoukakuKit

/// S-02 ホーム
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var checkInHabit: HabitSnapshot?
    @State private var showingEmergency = false
    @State private var showingPause = false
    @State private var showingRecovery = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WarningBanners()
                    StatusPanel()
                    if model.consecutiveMisses >= 3 {
                        RecoveryCard(showingPause: $showingPause)
                    }
                    todaySection
                    StreakRow()
                    exitRow
                }
                .padding()
            }
            .background(Theme.paper)
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CommitListView()
                    } label: {
                        Label("コミット", systemImage: "list.bullet.clipboard")
                    }
                }
            }
            .sheet(item: $checkInHabit) { habit in
                NavigationStack { CheckInView(habit: habit) }
            }
            .sheet(isPresented: $showingEmergency) {
                NavigationStack {
                    EmergencyView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { showingEmergency = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingPause) {
                NavigationStack {
                    PauseView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { showingPause = false }
                            }
                        }
                }
            }
            .refreshable {
                await model.onLaunchOrForeground()
            }
        }
    }

    // MARK: 今日のコミット

    @ViewBuilder private var todaySection: some View {
        if let today = model.today, !(today.required.isEmpty && today.optional.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                Text("今日のコミット")
                    .font(Theme.heading(.headline))
                    .foregroundStyle(Theme.ink)
                ForEach(today.required) { habit in
                    CommitRow(habit: habit, done: today.latestAchievement(for: habit.id), required: true) {
                        checkInHabit = habit
                    }
                }
                ForEach(today.optional) { habit in
                    CommitRow(habit: habit, done: today.latestAchievement(for: habit.id), required: false) {
                        checkInHabit = habit
                    }
                }
            }
        } else if model.decision != nil {
            RuledBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日のサイクルに予定されたコミットはありません。")
                        .foregroundStyle(Theme.ink)
                    NavigationLink("コミットを見る・追加する") { CommitListView() }
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: 非常口

    private var exitRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    showingEmergency = true
                } label: {
                    Label("緊急解除", systemImage: "clock.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.amber)
                Button {
                    showingPause = true
                } label: {
                    Label(model.activePause == nil ? "一時停止" : "再開", systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.muted)
            }
            Text("今週の緊急解除:\(model.emergencyCountThisWeek())回")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }
}

/// 状態の欄:印・見出し・次に変わる時刻までの残り
struct StatusPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = Date()
        let presentation = StatusPresentation.make(model: model, now: now)
        RuledBox {
            HStack(alignment: .top, spacing: 16) {
                SealView(text: presentation.seal, color: presentation.color, filled: presentation.filled)
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.headline)
                        .font(Theme.heading(.title3))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let until = presentation.countdownTo, until > now {
                        HStack(spacing: 4) {
                            Text(presentation.countdownLabel)
                            Text(timerInterval: now...until, countsDown: true)
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(presentation.color)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 判定の理由ごとの見出し(仕様書 第5.2節の表)
struct StatusPresentation {
    var seal: String
    var color: Color
    var filled: Bool
    var headline: String
    var detail: String?
    var countdownTo: Date?
    var countdownLabel = "あと"

    @MainActor
    static func make(model: AppModel, now: Date) -> StatusPresentation {
        guard let decision = model.decision, let state = model.state else {
            return StatusPresentation(seal: "待", color: Theme.muted, filled: false, headline: "読み込み中…")
        }
        let cal = model.cycleCalendar
        let today = model.today
        let pending = today?.pendingRequired ?? []
        let name = pending.first.map { "「\($0.title)」" } ?? "今日のコミット"
        let more = pending.count > 1 ? "ほか\(pending.count - 1)件" : ""
        let boundary = cal.end(of: decision.cycle)
        var p: StatusPresentation
        switch decision.reason {
        case .awaitingCommit:
            p = StatusPresentation(seal: "未", color: Theme.ink, filled: false,
                                   headline: "今日の\(name)\(more)がまだです",
                                   detail: "ロック中。達成すると、お金を使うアプリのロックが外れます。")
        case .carryOver:
            p = StatusPresentation(seal: "未", color: Theme.ink, filled: false,
                                   headline: "昨日は未達成。今日の分を終えるまでロック中",
                                   detail: "今日の\(name)\(more)を終えると外れます。")
        case .earnWindowExpired:
            var window = ""
            if case .earn(let minutes) = state.schedule.mode { window = Fmt.duration(minutes: minutes) }
            p = StatusPresentation(seal: "未", color: Theme.ink, filled: false,
                                   headline: "解除枠が終わりました。もう1回で\(window)")
        case .achieved:
            p = StatusPresentation(seal: "合格", color: Theme.seal, filled: true,
                                   headline: "今日は達成。\(Fmt.clock(boundary, now: now)) まで使えます",
                                   detail: nil, countdownTo: boundary, countdownLabel: "次の切り替えまで")
        case .earnWindowActive(let until):
            p = StatusPresentation(seal: "解", color: Theme.seal, filled: false,
                                   headline: "解除中", detail: nil, countdownTo: until)
        case .emergency(let until):
            p = StatusPresentation(seal: "急", color: Theme.amber, filled: false,
                                   headline: "緊急解除中", detail: "\(Fmt.clock(until, now: now)) に判定し直します。",
                                   countdownTo: until)
        case .beforeLockStart(let lockAt):
            p = StatusPresentation(seal: "猶", color: Theme.ink, filled: false,
                                   headline: "\(Fmt.hm(lockAt)) からロック。それまでにやろう",
                                   detail: "今日の\(name)\(more)を終えれば、ロックはかかりません。",
                                   countdownTo: lockAt, countdownLabel: "ロックまで")
        case .restDay:
            p = StatusPresentation(seal: "休", color: Theme.rest, filled: false, headline: "今日は休養日",
                                   detail: "ロックはかかりません。ストリークも途切れません。")
        case .noCommitToday:
            p = StatusPresentation(seal: "空", color: Theme.muted, filled: false, headline: "今日は予定なし",
                                   detail: "予定された必須コミットがない日はロックしません。")
        case .paused:
            let end = model.activePause?.end
            p = StatusPresentation(seal: "停", color: Theme.muted, filled: false, headline: "一時停止中",
                                   detail: end.map { "\(Fmt.clock($0, now: now)) に再開します。" } ?? "無期限。再開するまでロックしません。")
        case .monitorOnly:
            p = StatusPresentation(seal: "見", color: Theme.rest, filled: false, headline: "見守りモード(記録だけ)",
                                   detail: "ロックはせず、記録とストリークだけを続けます。")
        case .notStarted:
            let start = cal.start(of: state.activeSince)
            p = StatusPresentation(seal: "待", color: Theme.muted, filled: false,
                                   headline: "\(Fmt.clock(start, now: now)) から始まります",
                                   detail: "それまではロックしません。", countdownTo: start, countdownLabel: "開始まで")
        }
        if decision.shouldLock {
            p.detail = [p.detail, "切り替え:\(Fmt.clock(boundary, now: now))"].compactMap { $0 }.joined(separator: "\n")
        }
        if let startsAt = decision.emergencyStartsAt {
            p.detail = [p.detail, "緊急解除は \(Fmt.clock(startsAt, now: now)) から"].compactMap { $0 }.joined(separator: "\n")
            if p.countdownTo == nil {
                p.countdownTo = startsAt
                p.countdownLabel = "緊急解除まで"
            }
        }
        return p
    }
}

/// 今日のコミット1行
struct CommitRow: View {
    var habit: HabitSnapshot
    var done: Achievement?
    var required: Bool
    var onCheckIn: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MarkView(outcome: done == nil ? .pending : (done?.kind == .minimum ? .sankaku : .maru), size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(required ? "必須" : "任意(記録だけ)")
                    if let minimum = habit.minimumTitle {
                        Text("最小版:\(minimum)")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                if let done {
                    Text("\(Fmt.hm(done.at)) に\(done.kind == .minimum ? "最小版で" : "")達成")
                        .font(.caption)
                        .foregroundStyle(Theme.seal)
                }
            }
            Spacer(minLength: 8)
            if done == nil {
                Button("チェックイン", action: onCheckIn)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.seal)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.horizontal, 12)
        }
    }
}

/// ストリークと通算
struct StreakRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.stats()
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            stat(value: stats.streak, label: "連続", note: "日")
            Rectangle().fill(Theme.rule).frame(width: 1, height: 44)
            stat(value: stats.total, label: "通算", note: "日")
            Rectangle().fill(Theme.rule).frame(width: 1, height: 44)
            stat(value: stats.longest, label: "最長", note: "日")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func stat(value: Int, label: String, note: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(Theme.numeral(size: 40))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(note).font(.footnote).foregroundStyle(Theme.muted)
            }
            Text(label).font(.footnote).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 3日続けて未達成のときの「立て直し」(追い込まず、下げる・休む・止める道を並べる)
struct RecoveryCard: View {
    @Environment(AppModel.self) private var model
    @Binding var showingPause: Bool

    var body: some View {
        RuledBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(model.consecutiveMisses)日続けて未達成です")
                    .font(Theme.heading(.headline))
                    .foregroundStyle(Theme.ink)
                Text("追い込むほど続かなくなります。今の自分に合う形に直しましょう。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 6) {
                    Label("最小版で記録する(チェックイン画面で選べます)", systemImage: "triangle")
                    NavigationLink { CommitListView() } label: {
                        Label("目標を下げる(達成後に受け付け、翌日から)", systemImage: "arrow.down.circle")
                    }
                    NavigationLink { RestDaysView() } label: {
                        Label("休養日を置く", systemImage: "bed.double")
                    }
                    Button { showingPause = true } label: {
                        Label("一時停止する", systemImage: "pause.circle")
                    }
                }
                .font(.subheadline)
            }
        }
    }
}

/// 警告の帯(許可が外れている・通知が許可されていない・改ざん・復旧・再インストール・App Group)
struct WarningBanners: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            if !model.usesAppGroup {
                banner("App Group が使えません。拡張と状態を共有できないので、ロックが正しく動きません(署名の App Group を確認してください)。",
                       icon: "externaldrive.badge.xmark")
            }
            if !model.screenTimeApproved {
                Button {
                    Task {
                        if let problem = await model.requestScreenTimeAuthorization() {
                            model.show("許可できませんでした", problem)
                        }
                    }
                } label: {
                    banner("Screen Time の許可が外れています。タップして許可し直す", icon: "hand.raised.slash")
                }
                .buttonStyle(.plain)
            }
            if !model.notificationsAllowed {
                banner("通知が許可されていません。シールドからの誘導とリマインドが届きません(設定アプリで許可できます)。",
                       icon: "bell.slash")
            }
            if let error = model.registrationError {
                banner("区間の登録に失敗しました:\(error)", icon: "calendar.badge.exclamationmark")
            }
            if let at = model.tamperDetectedAt {
                banner("端末の時刻の変更を検知しました(\(Fmt.clock(at)))。回避ログに記録しました。", icon: "clock.arrow.circlepath")
            }
            if model.recoveredSharedFile {
                banner("共有ファイルが壊れていたので、1つ前の保存から戻しました。", icon: "arrow.uturn.backward.circle")
            }
            if let at = model.reinstallDetectedAt {
                banner("ロック中にアプリが削除されていました(\(Fmt.clock(at)) に検知)。回避ログに記録しました。", icon: "exclamationmark.triangle")
            }
        }
    }

    private func banner(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.seal)
        .padding(12)
        .background(Theme.seal.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.seal.opacity(0.35)))
    }
}
