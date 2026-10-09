import Foundation

/// 拡張から本体への受け渡し(拡張は state.json を書かず、受信箱に1件1ファイルで置く)
public enum InboxItem: Codable, Equatable, Sendable {
    case achievement(Achievement)
    case log(LogEntry)

    var folder: String {
        switch self {
        case .achievement: return "achievements"
        case .log: return "logs"
        }
    }
}

public struct LogEntry: Codable, Equatable, Sendable {
    public var at: Date
    public var kind: String
    public var detail: String

    public init(at: Date, kind: String, detail: String) {
        self.at = at
        self.kind = kind
        self.detail = detail
    }
}

/// App Group コンテナの中のファイル置き場。
/// - state.json:本体アプリだけが書く(atomic write)。拡張とウィジェットは読むだけ。
/// - inbox/achievements/・inbox/logs/:拡張が1件1ファイルで書く。本体が取り込んで消す。
/// 1つのファイルを複数のプロセスが書かないので、プロセス間の競合が起きない。
public struct SharedStateStore: Sendable {
    public let directory: URL
    /// 拡張が書くログの上限(本体が長く開かれなくても受信箱が膨らまないように)
    public static let logCap = 300

    public init(directory: URL) {
        self.directory = directory
    }

    public var stateURL: URL { directory.appendingPathComponent("state.json") }
    public var backupURL: URL { directory.appendingPathComponent("state.backup.json") }
    public var inboxURL: URL { directory.appendingPathComponent("inbox", isDirectory: true) }

    // MARK: state.json(本体アプリ専用の書き込み)

    /// ファイルがなければ nil、壊れていれば throw(拡張は throw なら何もしない=現状維持)
    public func load() throws -> SharedState? {
        try decode(stateURL)
    }

    /// 1つ前に保存した状態(state.json が壊れたときの復旧用。本体だけが使う)
    public func loadBackup() throws -> SharedState? {
        try decode(backupURL)
    }

    public func save(_ state: SharedState) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: stateURL.path), (try? decode(stateURL)) != nil {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: stateURL, to: backupURL)
        }
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    private func decode(_ url: URL) throws -> SharedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SharedState.self, from: Data(contentsOf: url))
    }

    // MARK: inbox(拡張が書く/本体が取り込む)

    @discardableResult
    public func appendInbox(_ item: InboxItem, now: Date = Date()) throws -> URL? {
        let folder = inboxURL.appendingPathComponent(item.folder, isDirectory: true)
        if case .log = item, fileNames(in: folder).count >= Self.logCap { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        let url = folder.appendingPathComponent("\(millis)-\(UUID().uuidString).json")
        try JSONEncoder().encode(item).write(to: url, options: .atomic)
        return url
    }

    /// 受信箱の中身を古い順に返す(本体用。壊れたファイルは飛ばす)
    public func readInbox() -> [(url: URL, item: InboxItem)] {
        ["achievements", "logs"]
            .flatMap { entries(in: inboxURL.appendingPathComponent($0, isDirectory: true)) }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    public func removeInbox(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// エンジンの extra に渡す:受信箱にある(まだ本体が取り込んでいない)達成。拡張はこれだけを読む。
    public func pendingAchievements() -> [Achievement] {
        entries(in: inboxURL.appendingPathComponent("achievements", isDirectory: true)).compactMap { entry in
            if case .achievement(let a) = entry.item { return a }
            return nil
        }
    }

    // MARK: private

    private func fileNames(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }
    }

    private func entries(in folder: URL) -> [(url: URL, item: InboxItem)] {
        fileNames(in: folder).sorted().compactMap { name in
            let url = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let item = try? JSONDecoder().decode(InboxItem.self, from: data) else { return nil }
            return (url, item)
        }
    }
}
