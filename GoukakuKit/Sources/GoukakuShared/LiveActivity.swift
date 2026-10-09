#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity / Dynamic Island の中身(仕様書 第9.3節:常時の表示には使わず、緊急解除・集中タイマー・稼働型の解除枠だけ)
public struct GoukakuActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable {
            case emergency   // 緊急解除:startsAt から endsAt まで解除
            case focus       // 集中タイマー:endsAt に目標に届く(一時停止中は pausedRemaining)
            case earn        // 稼働型:endsAt まで解除
        }

        public var kind: Kind
        public var title: String
        public var startsAt: Date
        public var endsAt: Date
        /// 集中タイマーの一時停止中の残り秒(動いているときは nil)
        public var pausedRemaining: Double?

        public init(kind: Kind, title: String, startsAt: Date, endsAt: Date, pausedRemaining: Double? = nil) {
            self.kind = kind
            self.title = title
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.pausedRemaining = pausedRemaining
        }
    }

    public var name: String

    public init(name: String) {
        self.name = name
    }
}
#endif
