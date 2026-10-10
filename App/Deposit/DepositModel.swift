import Foundation
import Observation
import UIKit
import GoukakuCore
import StripePaymentSheet

extension Notification.Name {
    /// チェックイン・取り消しなどで、その日の結果が変わった(預け金の返金を知らせるきっかけ)
    static let goukakuDayChanged = Notification.Name("goukaku.dayChanged")
}

/// 預け金(先にカードで7日分を預け、達成した日の分が返ってくる)。
/// お金を動かすのはサーバー(Cloudflare Workers)と Stripe。カード番号は Stripe の画面から Stripe に直接渡り、
/// このアプリにもサーバーにも残らない。その日を返金してよいかは、アプリの判定(CycleOutcome)をそのまま使う
@MainActor @Observable
final class DepositModel {
    static let shared = DepositModel(app: .shared)

    enum Phase: Equatable {
        case idle
        case connecting
        case syncing
        case preparing
    }

    let app: AppModel

    /// サーバーの URL(Cloudflare Workers の URL)
    var serverText: String {
        didSet { UserDefaults.standard.set(serverText, forKey: Keys.server) }
    }
    /// 1日の額(円)
    var daily: Int {
        didSet { UserDefaults.standard.set(daily, forKey: Keys.daily) }
    }
    /// 新しく預けるとき、次の週も自動で預けるか
    var renewForNew: Bool {
        didSet { UserDefaults.standard.set(renewForNew, forKey: Keys.renew) }
    }
    /// 招待コード(サーバーが求めるときだけ)
    var inviteCode = ""

    private(set) var config: DepositConfig?
    private(set) var weeks: [DepositWeek] = []
    private(set) var phase: Phase = .idle
    private(set) var connected = false
    private(set) var lastSync: Date?
    /// 画面に出す知らせ
    var message: String?

    // Stripe の支払い画面
    var paymentSheet: PaymentSheet?
    var presentingPayment = false
    private(set) var pendingAmount: Int?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var delayedSync: Task<Void, Never>?
    /// 見本(DEBUG の画面確認用。サーバーにつながず、決まった週を見せる)
    @ObservationIgnored private(set) var isSample = false

    static let amounts = [100, 300, 500, 1000, 2000, 3000]
    static let returnURL = "goukakulock://stripe-redirect"

    private enum Keys {
        static let server = "deposit.server"
        static let daily = "deposit.daily"
        static let renew = "deposit.renew"
    }

    init(app: AppModel) {
        self.app = app
        let defaults = UserDefaults.standard
        let preset = (Bundle.main.object(forInfoDictionaryKey: "GoukakuDepositServerURL") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        serverText = defaults.string(forKey: Keys.server) ?? preset
        daily = defaults.object(forKey: Keys.daily) as? Int ?? 300
        renewForNew = defaults.object(forKey: Keys.renew) as? Bool ?? true
        connected = token != nil
        observe()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingSampleDeposit") || defaults.bool(forKey: "debug.sampleDeposit") {
            loadSample()
        }
        #endif
    }

    // MARK: 様子

    var serverURL: URL? { DepositAPI.normalize(serverText) }

    private var account: String? { serverURL?.absoluteString }

    private var token: String? { account.flatMap { Keychain.read(account: $0) } }

    private var api: DepositAPI? {
        guard let serverURL else { return nil }
        return DepositAPI(baseURL: serverURL, token: token)
    }

    /// いまの週(始まっているもの。なければ、これからのもの)
    var current: DepositWeek? {
        weeks.first { $0.status == .active } ?? weeks.first { $0.status == .upcoming }
    }

    /// これからの週(いまの週のあとに、自動で続けた分など)
    var upcoming: [DepositWeek] {
        weeks.filter { $0.status == .upcoming && $0.id != current?.id }.sorted { $0.startsAt < $1.startsAt }
    }

    /// 終わった週(新しい順)
    var past: [DepositWeek] {
        weeks.filter { $0.status == .ended || $0.status == .closed }
    }

    /// 新しく預けたときの7日(明日のサイクルから)
    var nextPlan: [DepositDay] {
        DepositRules.plan(startingAt: app.nextCycle, calendar: app.cycleCalendar)
    }

    /// 自動で続く予定の週(終わったら、同じカードで次の7日を預ける)
    private func willRenew(_ week: DepositWeek) -> Bool {
        week.renew && week.next == nil && week.renewError == nil && week.status != .closed
    }

    /// 新しく預けられるか(すでにある週と日が重ならず、前の週から自動で続く予定の日でもない)
    var canStartNew: Bool {
        guard connected, config?.ready == true, !app.needsOnboarding else { return false }
        let keys = Set(nextPlan.map(\.key))
        let overlaps = weeks.contains { week in
            week.status != .closed && week.status != .ended && week.days.contains { keys.contains($0.key) }
        }
        // 自動で続く週は、終わると次の7日(日付 +7)を預ける。その日にちとも重ならないこと(サーバーと同じ決まり)
        let cal = app.cycleCalendar
        let renewKeys = Set(weeks.filter(willRenew).flatMap { week in
            week.days.compactMap { $0.cycle.map { cal.cycle($0, offsetBy: DepositRules.days).description } }
        })
        return !overlaps && renewKeys.isDisjoint(with: keys)
    }

    /// 自動で続けられなかった週(カードの確認が要るなど)。そのあとに自分で預け直した週があれば出さない
    var renewalProblem: (week: DepositWeek, reason: String)? {
        guard let week = weeks.first(where: { $0.renewError != nil && $0.next == nil }) else { return nil }
        if weeks.contains(where: { $0.id != week.id && $0.startsAt >= week.endsAt.addingTimeInterval(-3600) }) { return nil }
        return (week, Self.renewErrorText(week.renewError ?? ""))
    }

    static func renewErrorText(_ code: String) -> String {
        switch code {
        case "authentication_required": return "カード会社の本人確認(3D セキュア)が要るため、自動では預けられませんでした"
        case "card_declined", "card_error", "insufficient_funds", "expired_card": return "カードが通らなかったため、自動では預けられませんでした"
        case "late": return "週が終わってから時間がたったため、自動では続けませんでした"
        case "inactive": return "この週に一度もアプリが開かれなかったので、自動では続けませんでした"
        case "no_payment_method": return "カードが保存されていないため、自動では預けられませんでした"
        default: return "自動では預けられませんでした(\(code))"
        }
    }

    /// 週の各日の見え方(アプリの判定を使う。見本は見本の結果を先に使い、ない日(今日)はアプリの判定)
    func marks(for week: DepositWeek, now: Date = Date()) -> [DepositDayMark] {
        let outcomes = app.outcomeMap()
        return week.days.map { day in
            let mine = day.cycle.flatMap { outcomes[$0] }
            let server = day.outcome.flatMap(CycleOutcome.init(rawValue:))
            let outcome = isSample ? (server ?? mine) : (mine ?? server)
            return DepositRules.mark(startsAt: day.startsAt, endsAt: day.endsAt, refunded: day.refunded,
                                     outcome: outcome, now: now)
        }
    }

    func breakdown(for week: DepositWeek, now: Date = Date()) -> DepositBreakdown {
        DepositBreakdown.make(marks: marks(for: week, now: now), daily: week.daily,
                              refundedAmounts: week.days.map(\.refundedAmount))
    }

    // MARK: つなぐ

    /// サーバーの設定を読み、まだならこの iPhone を登録する
    func connect() async {
        guard !isSample else { return }
        guard let url = serverURL, let account else {
            message = "サーバーの URL を入れてください(例:https://goukaku-deposit.〇〇.workers.dev)"
            return
        }
        phase = .connecting
        defer { phase = .idle }
        do {
            let open = DepositAPI(baseURL: url, token: nil)
            let config = try await open.config()
            guard config.ready else {
                throw DepositServerError(status: 503, code: "not_configured", message: "サーバーの設定がまだです(Stripe の鍵と TOKEN_SECRET)")
            }
            self.config = config
            if token == nil {
                let registration = try await open.register(code: inviteCode.trimmingCharacters(in: .whitespaces))
                guard Keychain.save(registration.token, account: account) else {
                    throw DepositServerError(status: 0, code: "keychain", message: "合い言葉をこの iPhone にしまえませんでした")
                }
                app.log("deposit", "預け金のサーバーにつないだ(\(url.host ?? ""))")
                app.save()
            }
            connected = true
            await sync(force: true)
        } catch {
            message = Self.describe(error)
        }
    }

    /// この iPhone の登録を忘れる。先に「次の週も自動で預ける」をすべて止める
    /// (外したあとは返金を知らせられないので、続けると預けたまま戻らなくなるため)。いまの週はそのまま
    func disconnect() async {
        guard !isSample else { return }
        var note = "自動で続けるのは止めた"
        if let api, token != nil {
            do {
                // 画面の様子が古くても止めもれがないよう、サーバーから読み直してから止める
                let state = try await api.state()
                for week in state.deposits where willRenew(week) {
                    _ = try await api.setRenew(depositID: week.id, on: false)
                }
            } catch let error as DepositServerError where error.status == 401 {
                // 合い言葉が通らないので止められない。外すのは止めない
                // (サーバーは、アプリがつながらない週のあとは自動で続けない)
                note = "合い言葉が通らず、自動で続けるのは止められなかった"
                message = "サーバーが合い言葉を受けつけないため、自動で続けるのは止められませんでした。アプリがつながらない週が終わると、サーバーは自動では続けません。"
            } catch {
                message = "自動で続けるのを止められなかったので、外していません(\(Self.describe(error)))"
                return
            }
        }
        if let account { Keychain.delete(account: account) }
        connected = false
        weeks = []
        config = nil
        app.log("deposit", "預け金のサーバーとのつながりを外した(\(note))")
        app.save()
    }

    // MARK: 様子を合わせる・返金を知らせる

    /// サーバーの様子を読み、結果が決まった日の返金を知らせる(前に出たとき・チェックインのあと・裏の更新)。
    /// heartbeat:この週にアプリがつながった印を送るか。裏の更新では送らない(自動で続けるのは、本人がアプリを開いた週だけ)
    func sync(force: Bool = false, heartbeat: Bool = true) async {
        guard connected, !isSample, let api, phase == .idle || force else { return }
        if !force, let lastSync, Date().timeIntervalSince(lastSync) < 20 { return }
        let previous = phase
        phase = .syncing
        defer { phase = previous == .connecting ? .connecting : .idle }
        do {
            let state = try await api.state()
            config = state.config
            weeks = state.deposits
            if heartbeat { try await sendHeartbeat(api) }
            try await reportFinishedDays(api)
            lastSync = Date()
        } catch let error as DepositServerError where error.status == 401 {
            // 合い言葉が通らない(サーバーの TOKEN_SECRET が変わったなど)。合い言葉は消さずに残す
            // (サーバーの鍵を元に戻せば、そのまま続けられる。消すと預け金を知らせる手立てがなくなる)
            message = "預け金のサーバーが、この iPhone の合い言葉を受けつけません。サーバーの TOKEN_SECRET を元に戻してください(\(error.message))"
        } catch {
            // 圏外などは静かに(次の機会にもう一度)
        }
    }

    /// 自動で続く予定の週に「この週もアプリがつながった」と、次の週の日の始まり(この iPhone の暦で計算)を知らせる。
    /// サーバーは、その週に一度もつながらなかった預け金を自動では続けない(合い言葉をなくしたまま預け続けないように)
    private func sendHeartbeat(_ api: DepositAPI) async throws {
        let cal = app.cycleCalendar
        // weeks の写しを回す(待っているあいだに、ほかの同期やつながりを外す操作で weeks が入れかわってもよいように)
        for week in weeks where willRenew(week) && week.status != .ended {
            guard let last = week.days.last?.cycle else { continue }
            let next = DepositRules.plan(startingAt: cal.cycle(last, offsetBy: 1), calendar: cal)
            do {
                replace(try await api.seen(depositID: week.id, next: next))
            } catch let error as DepositServerError where error.status == 400 {
                // 次の週の日付がサーバーの筋に合わない(暦を大きく変えた など):つながった印だけ送る
                if let updated = try? await api.seen(depositID: week.id, next: nil) { replace(updated) }
            } catch let error as DepositServerError where error.status == 401 {
                throw error
            } catch {
                // 圏外・Stripe の不調など:印は次の機会に。返金の知らせは続ける
                continue
            }
        }
    }

    /// 結果が決まった日の返金を頼む。1日うまくいかなくても、ほかの日は続けて頼む
    private func reportFinishedDays(_ api: DepositAPI) async throws {
        let outcomes = app.outcomeMap()
        let cal = app.cycleCalendar
        let now = Date()
        for week in weeks where week.acceptsReports {
            for day in week.days where !day.refunded {
                guard let cycle = day.cycle, let outcome = outcomes[cycle] else { continue }
                let lastCheckIn = app.summary(for: cycle)?.counted.map(\.at).max()
                guard DepositRules.shouldReport(outcome: outcome, cycleEnd: cal.end(of: cycle), lastCheckIn: lastCheckIn,
                                                alreadyRefunded: day.refunded, now: now) else { continue }
                do {
                    replace(try await api.report(depositID: week.id, day: day.key, outcome: outcome))
                    app.log("deposit", "預け金:\(day.key) の分(\(Fmt.yen(week.daily)))の返金を頼んだ")
                    app.save()
                } catch let error as DepositServerError where error.status != 401 {
                    // この日だけの問題(まだ始まっていない・締め切った・Stripe が返金を断った など):次の日へ
                    continue
                }
            }
        }
    }

    /// サーバーから届いた週で、同じ id の週を置きかえる(もう画面にない週なら何もしない)
    private func replace(_ updated: DepositWeek) {
        if let i = weeks.firstIndex(where: { $0.id == updated.id }) { weeks[i] = updated }
    }

    // MARK: 預ける

    /// 7日分の支払いを用意して、Stripe の支払い画面を出す
    func startDeposit() async {
        #if DEBUG
        if isSample {
            message = "見本なので、支払いはしません"
            return
        }
        #endif
        guard let api, canStartNew else { return }
        let days = nextPlan
        phase = .preparing
        defer { phase = .idle }
        do {
            let checkout = try await api.createDeposit(daily: daily, days: days, renew: renewForNew)
            STPAPIClient.shared.publishableKey = checkout.publishableKey
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = checkout.merchantName
            configuration.returnURL = Self.returnURL
            configuration.allowsDelayedPaymentMethods = false
            configuration.primaryButtonLabel = "\(Fmt.yen(checkout.amount))を預ける"
            paymentSheet = PaymentSheet(paymentIntentClientSecret: checkout.clientSecret, configuration: configuration)
            pendingAmount = checkout.amount
            presentingPayment = true
        } catch {
            message = Self.describe(error)
        }
    }

    /// Stripe の支払い画面が閉じた
    func paymentFinished(_ result: PaymentSheetResult) {
        presentingPayment = false
        paymentSheet = nil
        switch result {
        case .completed:
            let amount = pendingAmount.map(Fmt.yen) ?? ""
            app.log("deposit", "預け金 \(amount) を預けた(\(nextPlan.first?.key ?? "")から7日)")
            app.save()
            message = "\(amount)を預けました。明日から7日間、達成した日の分が返ってきます。"
            Task { await sync(force: true) }
        case .canceled:
            break
        case .failed(let error):
            message = "支払いできませんでした:\(error.localizedDescription)"
        }
        pendingAmount = nil
    }

    /// 次の週も自動で預けるか(止めるのはいつでも。いまの週はそのまま)
    func setRenew(_ on: Bool, for week: DepositWeek) async {
        guard !isSample, let api else { return }
        do {
            replace(try await api.setRenew(depositID: week.id, on: on))
            app.log("deposit", on ? "預け金:次の週も自動で預ける" : "預け金:自動で続けるのを止めた")
            app.save()
        } catch {
            message = Self.describe(error)
        }
    }

    /// やめる(やめる合図):明日からの分を返してもらい、自動で続けるのも止める。今日までは結果しだい
    func cancel(_ week: DepositWeek) async {
        guard !isSample, let api else { return }
        do {
            let updated = try await api.cancel(depositID: week.id)
            replace(updated)
            let returned = updated.days.filter { $0.outcome == "canceled" }.reduce(0) { $0 + $1.refundedAmount }
            app.log("deposit", "預け金をやめた(明日からの分 \(Fmt.yen(returned)) を返金)")
            app.save()
            message = returned > 0
                ? "やめました。明日からの\(Fmt.yen(returned))を返金します。今日までの分は、これまでどおりです。"
                : "やめました。次の週は預けません。"
        } catch {
            // サーバーは返金より先に「自動で続ける」を止める。読み直して、どこまで済んだかを伝える
            await sync(force: true)
            if weeks.first(where: { $0.id == week.id })?.isCanceled == true {
                message = "次の週は預けないようにしましたが、明日からの分の返金がうまくいきませんでした(\(Self.describe(error)))。少したってから、もう一度頼んでください。"
            } else {
                message = Self.describe(error)
            }
        }
    }

    /// やめたときに返ってくる額(まだ始まっていない日の分)
    func cancelableAmount(_ week: DepositWeek, now: Date = Date()) -> Int {
        week.days.filter { $0.startsAt > now && !$0.refunded }.count * week.daily
    }

    // MARK: きっかけ

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(forName: .goukakuDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 取り消しの時間(5分)が過ぎてから知らせる
                self.delayedSync?.cancel()
                self.delayedSync = Task {
                    try? await Task.sleep(for: .seconds(DepositRules.undoWindow + 15))
                    guard !Task.isCancelled else { return }
                    await self.sync(force: true)
                }
            }
        })
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? DepositServerError { return error.message }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return "インターネットにつながっていません"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "サーバーが見つかりません(URL を確かめてください)"
            case .timedOut: return "サーバーの返事がありませんでした"
            default: break
            }
        }
        return error.localizedDescription
    }

    // MARK: 見本(DEBUG)

    #if DEBUG
    /// シミュレータでの画面確認用:4日目の週を、サーバーなしで見せる
    func loadSample() {
        isSample = true
        connected = true
        if serverText.isEmpty { serverText = "https://goukaku-deposit.example.workers.dev" }
        config = DepositConfig(ready: true, publishableKey: "pk_test_sample", testMode: true, currency: "jpy",
                               minDaily: 100, maxDaily: 3000, days: 7, graceDays: 7, merchantName: "合格ロック",
                               requiresCode: false)
        let cal = app.cycleCalendar
        let first = cal.cycle(app.currentCycle, offsetBy: -3)
        let plan = DepositRules.plan(startingAt: first, calendar: cal)
        let outcomes: [String?] = ["achieved", "missed", "minimum", nil, nil, nil, nil]
        let days = plan.enumerated().map { i, day in
            DepositWeek.Day(key: day.key, startsAt: day.startsAt, endsAt: day.endsAt,
                            refunded: i == 0 || i == 2, refundedAmount: i == 0 || i == 2 ? 300 : 0,
                            outcome: outcomes[i], refundStatus: i == 0 || i == 2 ? "succeeded" : nil)
        }
        let last = cal.cycle(first, offsetBy: -7)
        let lastPlan = DepositRules.plan(startingAt: last, calendar: cal)
        let lastDays = lastPlan.enumerated().map { i, day in
            DepositWeek.Day(key: day.key, startsAt: day.startsAt, endsAt: day.endsAt, refunded: i != 4,
                            refundedAmount: i != 4 ? 300 : 0, outcome: i != 4 ? "achieved" : "missed",
                            refundStatus: i != 4 ? "succeeded" : nil)
        }
        weeks = [
            DepositWeek(id: "pi_sample_now", status: .active, daily: 300, total: 2100, currency: "jpy", days: days,
                        refunded: 600, forfeited: nil, startsAt: plan[0].startsAt, endsAt: plan[6].endsAt,
                        closesAt: plan[6].endsAt.addingTimeInterval(7 * 86400), renew: true, next: nil, prev: "pi_sample_last",
                        renewError: nil, livemode: false),
            DepositWeek(id: "pi_sample_last", status: .ended, daily: 300, total: 2100, currency: "jpy", days: lastDays,
                        refunded: 1800, forfeited: nil, startsAt: lastPlan[0].startsAt, endsAt: lastPlan[6].endsAt,
                        closesAt: lastPlan[6].endsAt.addingTimeInterval(7 * 86400), renew: true, next: "pi_sample_now",
                        prev: nil, renewError: nil, livemode: false),
        ]
    }
    #endif
}
