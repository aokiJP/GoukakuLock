import Foundation
import GoukakuCore

/// ウィジェットが state.json だけでは分からない数字(連続・通算など)。本体が書き、ウィジェットは読むだけ。
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var streak: Int
    public var total: Int
    public var longest: Int
    public var emergencyThisWeek: Int
    /// 直近のサイクルの結果(古い順。CycleOutcome の rawValue)
    public var recent: [String]
    public var updatedAt: Date

    public static let fileName = "widget.json"

    public init(streak: Int = 0, total: Int = 0, longest: Int = 0, emergencyThisWeek: Int = 0,
                recent: [String] = [], updatedAt: Date = Date()) {
        self.streak = streak
        self.total = total
        self.longest = longest
        self.emergencyThisWeek = emergencyThisWeek
        self.recent = recent
        self.updatedAt = updatedAt
    }

    public var recentOutcomes: [CycleOutcome] { recent.compactMap(CycleOutcome.init(rawValue:)) }

    public static func load(from directory: URL?) -> WidgetSnapshot? {
        guard let url = directory?.appendingPathComponent(fileName), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(to directory: URL?) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
