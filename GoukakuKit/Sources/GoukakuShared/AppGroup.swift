import Foundation
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
