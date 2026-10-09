import SwiftUI
import WidgetKit
import GoukakuCore
import GoukakuKit

/// ホームから開く画面
enum HomeSheet: Identifiable {
    case checkIn(HabitSnapshot)
    case emergency
    case pause
    case review(CycleID)
    case share

    var id: String {
        switch self {
        case .checkIn(let habit): return "checkin-\(habit.id)"
        case .emergency: return "emergency"
        case .pause: return "pause"
        case .review(let week): return "review-\(week)"
        case .share: return "share"
        }
    }
}

/// S-02 ホーム
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(NotificationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: HomeSheet?
    /// ホーム画面・ロック画面にウィジェットが置いてあるか(わかるまでは nil)
    @State private var widgetInstalled: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WarningBanners()
                    StatusPanel()
                    if model.consecutiveMisses >= 3 {
                        RecoveryCard(showPause: { sheet = .pause })
                    }
                    if let week = model.weeklyReviewDue {
                        WeeklyReviewCard(week: week) { sheet = .review(week) }
                    }
                    todaySection
                    DepositHomeCard()
                    if model.decision != nil {
                        CompanionHomeCard()
                    }
                    RecentStrip()
                    StreakRow(onShare: { sheet = .share })
                    WidgetNudgeCard(installed: widgetInstalled)
                    if model.rampSuggestionDue {
                        RampCard()
                    }
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
            .sheet(item: $sheet) { sheet in
                NavigationStack {
                    sheetContent(sheet)
                }
            }
            .refreshable {
                await model.onLaunchOrForeground()
            }
            .task(id: scenePhase) {
                // ウィジェットを置いて戻ってきたら案内が消えるよう、前面に戻るたびに確かめる
                guard scenePhase == .active else { return }
                widgetInstalled = await WidgetNudgeCard.hasInstalledWidget()
            }
            .onChange(of: router.openTimer, initial: true) { _, open in
                guard open else { return }
                router.openTimer = false
                let today = model.today
                if let habit = today?.required.first(where: { $0.method == .timer && !(today?.isDone($0.id) ?? false) })
                    ?? today?.required.first(where: { $0.method == .timer }) {
                    sheet = .checkIn(habit)
                } else {
                    router.openCheckIn = true
                }
            }
            .onChange(of: router.openEmergency, initial: true) { _, open in
                guard open else { return }
                router.openEmergency = false
                sheet = .emergency
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .checkIn(let habit):
            CheckInDestination(habit: habit)
        case .emergency:
            EmergencyView().closeButton { self.sheet = nil }
        case .pause:
            PauseView().closeButton { self.sheet = nil }
        case .review(let week):
            WeeklyReviewView(week: week)
        case .share:
            ShareSheetView()
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
                    CommitRow(habit: habit, done: today.latestAchievement(for: habit.id), required: true,
                              earnMode: model.isEarnMode, earnMinutes: model.earnWindowMinutes) {
                        sheet = .checkIn(habit)
                    }
                }
                ForEach(today.optional) { habit in
                    CommitRow(habit: habit, done: today.latestAchievement(for: habit.id), required: false,
                              earnMode: model.isEarnMode, earnMinutes: model.earnWindowMinutes) {
                        sheet = .checkIn(habit)
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
                    sheet = .emergency
                } label: {
                    Label("緊急解除", systemImage: "clock.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.amber)
                Button {
                    sheet = .pause
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

extension View {
    /// シートの左上に「閉じる」を付ける
    func closeButton(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる", action: action)
            }
        }
    }
}

/// コミットの確かめ方に合わせて、記録の画面を出し分ける
struct CheckInDestination: View {
    @Environment(AppModel.self) private var model
    let habit: HabitSnapshot

    var body: some View {
        switch habit.method {
        case .timer:
            let detail = model.habit(habit.id)
            FocusTimerView(habit: habit, fullMinutes: habit.targetMinutes ?? 25,
                           minimumMinutes: detail?.minimumMinutes ?? 5, strict: detail?.strictTimer ?? false)
        case .photo:
            PhotoCheckInView(habit: habit)
        case .appUsage:
            UsageInfoView(habit: habit)
        default:
            CheckInView(habit: habit)
        }
    }
}

/// 使用時間で自動達成するコミットの説明
struct UsageInfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let habit: HabitSnapshot

    var body: some View {
        let done = model.today?.isDone(habit.id) ?? false
        Form {
            Section {
                Text(habit.title).font(Theme.heading(.title3)).foregroundStyle(Theme.ink)
                Label(done ? "今日は自動で達成しました" : "選んだ学習アプリを合計\(habit.targetMinutes ?? 0)分使うと、自動で達成します",
                      systemImage: done ? "checkmark.seal.fill" : "hourglass")
                    .foregroundStyle(done ? Theme.seal : Theme.ink)
            } footer: {
                Text("Screen Time の計測を使うので参考精度です。その日の 23:59 までの利用だけを数えます。アプリを開かなくても、達成した時点でロックが外れます。")
            }
            Section {
                Button("今すぐ確かめる") {
                    model.reconcile(source: "usageCheck")
                    model.scheduleWidgetRefresh()
                }
            }
        }
        .navigationTitle("使用時間")
        .navigationBarTitleDisplayMode(.inline)
        .closeButton { dismiss() }
    }
}

/// 状態の欄:印・見出し・次に変わる時刻までの残り
struct StatusPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = Date()
        RuledBox {
            if let summary = model.statusSummary(now: now) {
                HStack(alignment: .top, spacing: 16) {
                    SealView(text: summary.seal, color: summary.tone.color, filled: summary.tone.filled)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary.headline)
                            .font(Theme.heading(.title3))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = summary.detail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let until = summary.countdownTo, until > now {
                            HStack(spacing: 4) {
                                Text(summary.countdownLabel)
                                Text(timerInterval: now...until, countsDown: true)
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(summary.tone.color)
                        }
                    }
                }
            } else {
                Text("読み込み中…").foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 今日のコミット1行
struct CommitRow: View {
    var habit: HabitSnapshot
    var done: Achievement?
    var required: Bool
    var earnMode = false
    var earnMinutes: Int?
    var onCheckIn: () -> Void

    private var methodLabel: String {
        switch habit.method {
        case .timer: return "集中タイマー \(habit.targetMinutes ?? 25)分"
        case .photo: return "写真"
        case .appUsage: return "使用時間 \(habit.targetMinutes ?? 0)分(自動)"
        default: return "自己申告"
        }
    }

    private var actionLabel: String? {
        if habit.method == .appUsage { return nil }
        if earnMode {
            guard habit.method != .selfReport else { return nil }
            let gain = earnMinutes.map { "+\(Fmt.duration(minutes: $0))" } ?? ""
            return done == nil ? "\(habit.method == .photo ? "撮る" : "はじめる") \(gain)" : "もう1回 \(gain)"
        }
        guard done == nil else { return nil }
        switch habit.method {
        case .timer: return "はじめる"
        case .photo: return "撮る"
        default: return "チェックイン"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MarkView(outcome: done == nil ? .pending : (done?.kind == .minimum ? .sankaku : .maru), size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(required ? "必須" : "任意")
                    Text(methodLabel)
                    if let minimum = habit.minimumTitle, !minimum.isEmpty {
                        Text("最小版:\(minimum)")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                if let done {
                    Text("\(Fmt.hm(done.at)) に\(done.kind == .minimum ? "最小版で" : "")\(done.source == .monitor ? "自動で" : "")達成")
                        .font(.caption)
                        .foregroundStyle(Theme.seal)
                }
            }
            Spacer(minLength: 8)
            if let actionLabel {
                Button(actionLabel, action: onCheckIn)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.seal)
                    .font(.subheadline.weight(.semibold))
            } else if habit.method == .appUsage && done == nil {
                Button(action: onCheckIn) {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("使用時間の説明")
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

/// この2週間の記録(◯△✕)
struct RecentStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.recentOutcomes(days: 14)
        let cal = model.cycleCalendar
        let current = model.currentCycle
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("この2週間")
                    .font(Theme.heading(.headline))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        VStack(spacing: 4) {
                            SlotMarkView(outcome: item.cycle > current ? .blank : item.outcome.mark, size: 16)
                            Text(Fmt.weekdaySymbols[cal.weekday(of: item.cycle) - 1])
                                .font(.system(size: 9))
                                .foregroundStyle(item.cycle == current ? Theme.seal : Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("この2週間の達成 \(items.filter { $0.outcome == .achieved || $0.outcome == .minimum }.count)日")
        }
    }
}

/// ストリークと通算
struct StreakRow: View {
    @Environment(AppModel.self) private var model
    var onShare: () -> Void = {}

    var body: some View {
        let stats = model.stats()
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                stat(value: stats.streak, label: "連続", note: "日")
                Rectangle().fill(Theme.rule).frame(width: 1, height: 44)
                stat(value: stats.total, label: "通算", note: "日")
                Rectangle().fill(Theme.rule).frame(width: 1, height: 44)
                stat(value: stats.longest, label: "最長", note: "日")
            }
            .accessibilityElement(children: .combine)
            if stats.total > 0 {
                Button(action: onShare) {
                    Label("合格証をつくる", systemImage: "rosette")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.seal)
            }
        }
        .padding(.vertical, 6)
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

/// 合格証のシート
struct ShareSheetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = model.stats()
        ScrollView {
            VStack(spacing: 18) {
                CertificateCard(streak: stats.streak, total: stats.total, goal: nil, date: Date())
                    .scaleEffect(0.85)
                    .frame(width: 306, height: 383)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                ShareCertificateButton(streak: stats.streak, total: stats.total)
                    .padding(.horizontal)
                Text("送るかどうか、何を載せるかはあなたが決めます。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical)
        }
        .background(Theme.paper)
        .navigationTitle("合格証")
        .navigationBarTitleDisplayMode(.inline)
        .closeButton { dismiss() }
    }
}

/// 3日続けて未達成のときの「立て直し」(追い込まず、下げる・休む・止める道を並べる)
struct RecoveryCard: View {
    @Environment(AppModel.self) private var model
    var showPause: () -> Void

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
                    Button(action: showPause) {
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

/// はじめて合格したあと、まだウィジェットを置いていない人に一度だけ出す案内。
/// 置いてあれば出さない。閉じたら二度と出さない。
struct WidgetNudgeCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage("nudge.widget.dismissed") private var dismissed = false
    var installed: Bool?

    var body: some View {
        Group {
            if !dismissed, installed == false, model.stats().total > 0 {
                RuledBox {
                    HStack(alignment: .top, spacing: 14) {
                        WidgetPreviewFrame(entry: model.widgetPreviewEntry(), family: .systemSmall)
                            .scaleEffect(0.56)
                            .frame(width: 88, height: 88)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ホーム画面に置こう")
                                .font(Theme.heading(.headline))
                                .foregroundStyle(Theme.ink)
                            Text("アプリを開かなくても今日の状態と残り時間が見え、タップするとすぐ記録の画面が開きます。")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            NavigationLink("置き方を見る") { TipsView() }
                                .font(.subheadline.weight(.semibold))
                                .tint(Theme.seal)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation { dismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.muted)
                            .padding(10)
                    }
                    .accessibilityLabel("この案内を閉じる")
                }
                .transition(.opacity)
            }
        }
    }

    /// ホーム画面・ロック画面に、このアプリのウィジェットが1つでも置いてあるか(問い合わせはメインスレッドの外で)
    nonisolated static func hasInstalledWidget() async -> Bool {
        let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        return !configurations.isEmpty
    }
}
