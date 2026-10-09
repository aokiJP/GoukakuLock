import Foundation

/// サイクル(=アプリにとっての1日)の識別子。
/// サイクルが始まる日付(現地時間)で表す。例: 日付切替 4:00 なら
/// 「2026-10-09」は 10/9 4:00 〜 10/10 3:59 のサイクル。
public struct CycleID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "yyyy-MM-dd" から作る。形式が違えば nil。
    public init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CycleID, rhs: CycleID) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CycleID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CycleID(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid CycleID: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
