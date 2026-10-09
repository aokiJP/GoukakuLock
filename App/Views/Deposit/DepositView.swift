import SwiftUI
import GoukakuCore
import StripePaymentSheet

/// 設定 › 預け金(クレカ)。先に7日分を預け、達成した日の分が返ってくる
struct DepositView: View {
    @Environment(DepositModel.self) private var deposit
    @Environment(AppModel.self) private var model
    @State private var confirmDisconnect = false
    @State private var cancelTarget: DepositWeek?

    var body: some View {
        @Bindable var deposit = deposit
        Form {
            introSection
            if let problem = deposit.renewalProblem {
                Section {
                    Label(problem.reason, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.amber)
                }
            }
            if let week = deposit.current {
                weekSection(week, title: week.status == .upcoming ? "これからの週" : "今週")
            }
            ForEach(deposit.upcoming) { week in
                weekSection(week, title: "その次の週(自動で預けた分)")
            }
            if deposit.connected {
                newDepositSection
            }
            if !deposit.past.isEmpty {
                pastSection
            }
            serverSection
            notesSection
        }
        .navigationTitle("預け金")
        .navigationBarTitleDisplayMode(.inline)
        .task { await deposit.sync(force: true) }
        .refreshable { await deposit.sync(force: true) }
        .background {
            if let sheet = deposit.paymentSheet {
                Color.clear.paymentSheet(isPresented: $deposit.presentingPayment, paymentSheet: sheet) { result in
                    MainActor.assumeIsolated { self.deposit.paymentFinished(result) }
                }
            }
        }
        .alert(deposit.message ?? "", isPresented: Binding(get: { deposit.message != nil }, set: { if !$0 { deposit.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("預け金をやめますか?", isPresented: Binding(get: { cancelTarget != nil }, set: { if !$0 { cancelTarget = nil } }),
                            titleVisibility: .visible, presenting: cancelTarget) { week in
            Button("やめる(明日からの\(Fmt.yen(deposit.cancelableAmount(week)))を返してもらう)", role: .destructive) {
                Task { await deposit.cancel(week) }
            }
        } message: { _ in
            Text("今日までの分は、これまでどおり結果しだいです(今日達成すれば返ってきます)。明日からの分を返金し、次の週も預けません。\n\(AppConstants.quitSignal)")
        }
        .confirmationDialog("このサーバーとのつながりを外しますか?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("外す", role: .destructive) { deposit.disconnect() }
        } message: {
            Text("預けたお金と返金の約束は、サーバーと Stripe に残ります。外したあとにつなぎ直すと、別の登録になり、いまの預け金はこの iPhone から見えなくなります。")
        }
    }

    // MARK: はじめに

    private var introSection: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                SealView(text: "預", color: Theme.seal, filled: deposit.current != nil, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("先に預けて、達成した日の分が返ってくる")
                        .font(Theme.heading(.headline))
                        .foregroundStyle(Theme.ink)
                    Text("カードで7日分を先に預けます。達成した日の分は返金し、達成できなかった日の分は戻りません。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 週

    @ViewBuilder
    private func weekSection(_ week: DepositWeek, title: String) -> some View {
        let marks = deposit.marks(for: week)
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Fmt.monthDay(week.startsAt))〜\(Fmt.monthDay(week.endsAt.addingTimeInterval(-1)))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("1日 \(Fmt.yen(week.daily))・合計 \(Fmt.yen(week.total))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            DepositStrip(week: week, marks: marks)
                .padding(.vertical, 4)
            DepositBreakdownText(breakdown: deposit.breakdown(for: week))
            if let hint = DepositHomeCard.todayHint(marks: marks, daily: week.daily) {
                Text(hint).font(.footnote).foregroundStyle(Theme.pencil)
            }
            if week.next == nil {
                Toggle("次の週も自動で預ける", isOn: Binding(
                    get: { week.renew },
                    set: { on in Task { await deposit.setRenew(on, for: week) } }
                ))
                .disabled(deposit.isSample)
                if deposit.cancelableAmount(week) > 0 {
                    Button("やめる(明日からの分を返してもらう)", role: .destructive) { cancelTarget = week }
                        .font(.footnote)
                        .disabled(deposit.isSample)
                }
            } else {
                Label("次の週も預けています", systemImage: "arrow.turn.down.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            HStack {
                Text(title)
                if !week.livemode {
                    Text("テストモード").foregroundStyle(Theme.amber)
                }
            }
        } footer: {
            if week.renew && week.next == nil {
                Text("この週が終わると、同じカードで次の7日分(\(Fmt.yen(week.total)))を自動で預けます。止めるのはいつでもでき、止めてもこの週はそのままです。")
            }
        }
    }

    // MARK: 新しく預ける

    private var newDepositSection: some View {
        @Bindable var deposit = deposit
        let plan = deposit.nextPlan
        let total = deposit.daily * plan.count
        return Section {
            if deposit.canStartNew {
                Picker("1日の額", selection: $deposit.daily) {
                    ForEach(DepositModel.amounts.filter { amount in
                        guard let config = deposit.config else { return true }
                        return amount >= config.minDaily && amount <= config.maxDaily
                    }, id: \.self) { amount in
                        Text(Fmt.yen(amount)).tag(amount)
                    }
                }
                Toggle("次の週も自動で預ける", isOn: $deposit.renewForNew)
                if let first = plan.first, let last = plan.last {
                    InfoRow(title: "期間", value: "\(Fmt.monthDay(first.startsAt))〜\(Fmt.monthDay(last.startsAt))(明日から7日)")
                }
                Button {
                    Task { await deposit.startDeposit() }
                } label: {
                    HStack {
                        if deposit.phase == .preparing { ProgressView().tint(.white) }
                        Text("カードで\(Fmt.yen(total))を預ける")
                    }
                }
                .buttonStyle(SealButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .disabled(deposit.phase != .idle)
                .accessibilityIdentifier("deposit.start")
            } else if model.needsOnboarding {
                Text("はじめの設定が済んでから預けられます").font(.footnote).foregroundStyle(Theme.muted)
            } else {
                Text("いまの週が終わるまで、新しくは預けられません(自動で続けるときは、続けて預けます)")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text("預ける")
        } footer: {
            Text("達成・最小版・休養日・予定のない日の分は返金します。未達成と一時停止の日の分は戻りません。返金は、チェックインの取り消しの時間(5分)が過ぎるか日付が変わったら、アプリが頼みます(週が終わってから\(deposit.config?.graceDays ?? 7)日まで受け付け)。")
        }
    }

    // MARK: 終わった週

    private var pastSection: some View {
        Section("これまで") {
            ForEach(deposit.past) { week in
                let b = deposit.breakdown(for: week)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Fmt.monthDay(week.startsAt))〜\(Fmt.monthDay(week.endsAt.addingTimeInterval(-1)))")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Fmt.yen(week.total)).font(.subheadline.monospacedDigit())
                    }
                    DepositStrip(week: week, marks: deposit.marks(for: week))
                    Text(week.status == .closed
                         ? "返金 \(Fmt.yen(week.refunded))・戻らなかった \(Fmt.yen(week.forfeited ?? b.kept))"
                         : "返金 \(Fmt.yen(b.returned + b.returning))・戻らない見込み \(Fmt.yen(b.kept))(\(Fmt.monthDay(week.closesAt))まで受付)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: サーバー

    private var serverSection: some View {
        @Bindable var deposit = deposit
        return Section {
            if deposit.connected {
                InfoRow(title: "サーバー", value: deposit.serverURL?.host ?? deposit.serverText)
                if let config = deposit.config {
                    InfoRow(title: "モード", value: config.testMode ? "テスト(本物のお金は動かない)" : "本番")
                    InfoRow(title: "額の範囲", value: "1日 \(Fmt.yen(config.minDaily))〜\(Fmt.yen(config.maxDaily))")
                }
                if let last = deposit.lastSync {
                    InfoRow(title: "最後に合わせた時刻", value: Fmt.clock(last))
                }
                Button("つながりを外す", role: .destructive) { confirmDisconnect = true }
                    .disabled(deposit.isSample)
            } else {
                TextField("https://goukaku-deposit.〇〇.workers.dev", text: $deposit.serverText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("deposit.server")
                TextField("招待コード(求められたときだけ)", text: $deposit.inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await deposit.connect() }
                } label: {
                    HStack {
                        Text("つなぐ")
                        if deposit.phase == .connecting { Spacer(); ProgressView() }
                    }
                }
                .disabled(deposit.serverURL == nil || deposit.phase != .idle)
            }
        } header: {
            Text("預け金のサーバー")
        } footer: {
            Text("預け金には、自分で立てる小さなサーバー(Cloudflare Workers)と Stripe のアカウントが要ります。立て方は README の「預け金」にあります。")
        }
    }

    private var notesSection: some View {
        Section {
            Label("カード番号は Stripe の画面から Stripe に直接渡り、このアプリにも預け金のサーバーにも残りません。", systemImage: "lock.shield")
            Label("預けたお金は、サーバーをつないだ Stripe のアカウント(このアプリを動かしている人)の口座に入ります。返金はそこからカードに戻ります(カードに反映されるまで数日〜2週間ほど)。", systemImage: "arrow.left.arrow.right")
            Label("ロックそのものは、預け金がなくてもいままでどおりです。緊急解除・一時停止もそのまま使えます(一時停止の日の分は戻りません)。", systemImage: "lifepreserver")
        }
        .font(.footnote)
        .foregroundStyle(Theme.muted)
    }
}
