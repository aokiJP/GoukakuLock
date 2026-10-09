import Foundation
import FamilyControls
import ManagedSettings
import GoukakuCore

/// 本体・拡張・ウィジェットが共有する場所。
///
/// App Group ID は次の順で決める(再署名で ID が変わっても、本体と拡張が同じ場所を指すように):
/// 1. 署名に埋め込まれたプロビジョニングプロファイルの App Group
///    (Info.plist の値と一致するもの → "goukaku" を含むもの → 先頭の順)
/// 2. Info.plist の `GoukakuAppGroupID`(project.yml の APP_GROUP_ID から入る)
/// 3. 既定値
public enum AppGroup {
    public static let defaultIdentifier = "group.com.aokijp.goukakulock"
    public static let infoPlistKey = "GoukakuAppGroupID"

    /// 起動中に変わらないので、最初に1回だけ求める
    public static let identifier: String = resolve(bundle: .main)

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static var store: SharedStateStore? {
        containerURL.map { SharedStateStore(directory: $0) }
    }

    static func resolve(bundle: Bundle) -> String {
        let configured = (bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 }
        return choose(configured: configured, provisioned: provisionedGroups(bundle: bundle))
    }

    /// 選び方だけを分けておく(テスト用)
    static func choose(configured: String?, provisioned: [String]) -> String {
        if let configured, provisioned.isEmpty || provisioned.contains(configured) { return configured }
        if let hit = provisioned.first(where: { $0.lowercased().contains("goukaku") }) { return hit }
        if let first = provisioned.first { return first }
        return configured ?? defaultIdentifier
    }

    /// embedded.mobileprovision(CMS で署名された plist)から App Group の一覧を読む。
    /// プロファイルがない(アドホック署名・TrollStore など)ときは空。
    static func provisionedGroups(bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let object = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil),
              let plist = object as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }
}

/// ロック対象と「常に許可」。FamilyActivityPicker で選ぶ(アプリ名は分からず、トークンだけを持つ)
public struct LockTargets: Codable {
    public var lock = FamilyActivitySelection()
    public var allow = FamilyActivitySelection()
    /// 買い物サイトをドメイン文字列で直接指定(任意。WebContentSettings のフィルタ。Safari 等の WebKit で有効)
    public var blockedDomains: [String] = []

    /// 上限を超えると何もシールドされなくなる報告があるため、アプリ側は余裕をみて 40 までにする
    public static let maxItemsPerKind = 40

    public init() {}

    public var isEmpty: Bool {
        lock.applicationTokens.isEmpty && lock.categoryTokens.isEmpty
            && lock.webDomainTokens.isEmpty && blockedDomains.isEmpty
    }

    /// 保存前の検証。空配列なら保存してよい
    public var problems: [String] {
        var result: [String] = []
        if isEmpty { result.append("ロック対象が1つもありません") }
        if lock.applicationTokens.count > Self.maxItemsPerKind { result.append("個別アプリは\(Self.maxItemsPerKind)個までです") }
        if lock.webDomainTokens.count > Self.maxItemsPerKind { result.append("サイトは\(Self.maxItemsPerKind)個までです") }
        if allow.applicationTokens.count > Self.maxItemsPerKind { result.append("「常に許可」のアプリは\(Self.maxItemsPerKind)個までです") }
        if allow.webDomainTokens.count > Self.maxItemsPerKind { result.append("「常に許可」のサイトは\(Self.maxItemsPerKind)個までです") }
        if blockedDomains.count > Self.maxItemsPerKind { result.append("直接指定のドメインは\(Self.maxItemsPerKind)個までです") }
        if !lock.applicationTokens.isDisjoint(with: allow.applicationTokens) {
            result.append("同じアプリが「ロック対象」と「常に許可」の両方にあります(常に許可が優先されます)")
        }
        return result
    }
}

/// targets.json(本体だけが書く)と、使用時間で判定するコミットの対象アプリ(usage-<id>.json)。
/// directory を省くと App Group を使う(拡張はいつも省く)。
public enum TargetsStore {
    public static let fileName = "targets.json"

    static func url(_ name: String, in directory: URL?) -> URL? {
        directory?.appendingPathComponent(name)
    }

    public static func load(from directory: URL? = AppGroup.containerURL) -> LockTargets? {
        guard let url = url(fileName, in: directory), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LockTargets.self, from: data)
    }

    public static func save(_ targets: LockTargets, to directory: URL? = AppGroup.containerURL) throws {
        guard let url = url(fileName, in: directory) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(targets).write(to: url, options: .atomic)
    }

    public static func loadUsageSelection(habitID: UUID, from directory: URL? = AppGroup.containerURL) -> FamilyActivitySelection? {
        guard let url = url("usage-\(habitID.uuidString).json", in: directory),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    public static func saveUsageSelection(_ selection: FamilyActivitySelection, habitID: UUID,
                                          to directory: URL? = AppGroup.containerURL) throws {
        guard let url = url("usage-\(habitID.uuidString).json", in: directory) else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(selection).write(to: url, options: .atomic)
    }

    /// 全削除用:targets.json と usage-*.json を消す
    public static func removeAll(in directory: URL? = AppGroup.containerURL) {
        guard let directory else { return }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name == fileName || (name.hasPrefix("usage-") && name.hasSuffix(".json")) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
