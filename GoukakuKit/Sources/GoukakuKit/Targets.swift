import Foundation
import FamilyControls
import ManagedSettings
import GoukakuCore
import GoukakuShared

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
