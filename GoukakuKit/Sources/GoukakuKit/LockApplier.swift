import Foundation
import ManagedSettings
import GoukakuCore
import GoukakuShared

extension ManagedSettingsStore.Name {
    /// 本体と拡張が共有する名前つきストア(Swift 6 の並行性チェックで止まらないよう計算プロパティにする)
    public static var moneyLock: Self { Self("moneyLock") }
}

/// 判定結果を ManagedSettings に反映する。何度呼んでも同じ結果(冪等)。
public enum LockApplier {
    public static func apply(_ decision: LockDecision, targets: LockTargets, options: LockOptions) {
        let store = ManagedSettingsStore(named: .moneyLock)
        guard decision.shouldLock else {
            store.clearAllSettings()
            return
        }
        // 「常に許可」が優先(安全の床:交通・地図・銀行などを確実に外すため)
        let allowApps = targets.allow.applicationTokens
        let allowDomains = targets.allow.webDomainTokens
        let apps = targets.lock.applicationTokens.subtracting(allowApps)
        let domains = targets.lock.webDomainTokens.subtracting(allowDomains)
        let categories = targets.lock.categoryTokens

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories, except: allowApps)
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories, except: allowDomains)
        store.appStore.denyInAppPurchases = options.denyInAppPurchases ? true : nil
        let named = Set(targets.blockedDomains.map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = named.isEmpty ? nil : .specific(named)
        // denyAppRemoval は使わない(全アプリが削除不能になる・individual 認可では保証されない・解除後も残る報告がある)
    }
}

/// 共有状態を読み → 判定し → ロックを適用する。本体・拡張のどこから何度呼んでも同じ結果になる。
/// 状態が読めないとき(初期設定前など)は何も変えない(=現状維持)。
public enum Reconciler {
    /// 区間の始まり・終わりの合図がわずかに早く届いても取りこぼさないよう、拡張はこの秒数だけ先の時刻で判定する
    public static let callbackLeadSeconds: TimeInterval = 5

    /// targets を省くと、store と同じ場所の targets.json を読む(本体と拡張で必ず同じ場所を見るため)
    @discardableResult
    public static func run(store: SharedStateStore? = AppGroup.store,
                           targets: LockTargets? = nil,
                           now: Date = Date(),
                           source: String,
                           logToInbox: Bool) -> LockDecision? {
        guard let store, let targets = targets ?? TargetsStore.load(from: store.directory),
              let state = try? store.load() else { return nil }
        let decision = LockEngine.evaluate(state, extra: store.pendingAchievements(), now: now)
        LockApplier.apply(decision, targets: targets, options: state.options)
        if logToInbox {
            let entry = LogEntry(at: now, kind: decision.shouldLock ? "lock" : "unlock", detail: "\(source) \(decision.reason)")
            _ = try? store.appendInbox(.log(entry), now: now)
        }
        return decision
    }
}
