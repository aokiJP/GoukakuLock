import Foundation

/// AIの「この人の理解」の段階。覚えていること・一緒にした体験・手ごたえ(いいね/ちがう)で育つ
public enum CompanionLevel: Int, Sendable, CaseIterable, Comparable {
    case hello = 0       // はじめまして
    case acquainted      // 知りはじめ
    case familiar        // 顔なじみ
    case partner         // 相棒

    public static func < (lhs: CompanionLevel, rhs: CompanionLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .hello: return "はじめまして"
        case .acquainted: return "知りはじめ"
        case .familiar: return "顔なじみ"
        case .partner: return "相棒"
        }
    }

    /// この段階に上がるのに要る「理解」の点
    public var threshold: Int {
        switch self {
        case .hello: return 0
        case .acquainted: return 6
        case .familiar: return 18
        case .partner: return 40
        }
    }

    public static func level(points: Int) -> CompanionLevel {
        allCases.last { points >= $0.threshold } ?? .hello
    }

    public var next: CompanionLevel? { CompanionLevel(rawValue: rawValue + 1) }
}

/// 体験の地図とAIの理解(育ちの画面に出すもの)
public struct GrowthSnapshot: Sendable, Equatable {
    public var totalExperiences: Int
    public var counts: [ExperienceCategory: Int]
    /// 1回でも体験した種類の数(8つのうち)
    public var explored: Int
    /// 一緒に過ごした日数(最初の体験・メモから今日まで)
    public var daysTogether: Int
    public var notes: Int
    public var liked: Int
    public var disliked: Int
    public var points: Int
    public var level: CompanionLevel

    /// 次の段階までの残り(点)。最高段階なら nil
    public var pointsToNext: Int? {
        guard let next = level.next else { return nil }
        return max(0, next.threshold - points)
    }

    /// 次の段階までの進み(0〜1)
    public var progressToNext: Double {
        guard let next = level.next else { return 1 }
        let span = Double(next.threshold - level.threshold)
        return min(1, max(0, Double(points - level.threshold) / span))
    }

    /// まだ体験していない種類(次の一歩の候補)
    public var unexplored: [ExperienceCategory] {
        ExperienceCategory.allCases.filter { (counts[$0] ?? 0) == 0 }
    }

    /// 理解の点:覚えていること×2 + 体験 + 手ごたえ÷2
    public static func points(notes: Int, experiences: Int, feedback: Int) -> Int {
        notes * 2 + experiences + feedback / 2
    }

    public static func make(experienceCategories: [ExperienceCategory], notes: Int, liked: Int, disliked: Int,
                            since: Date?, now: Date = Date(), calendar: Calendar = .current) -> GrowthSnapshot {
        var counts: [ExperienceCategory: Int] = [:]
        for c in experienceCategories { counts[c, default: 0] += 1 }
        var days = 0
        if let since {
            let from = calendar.startOfDay(for: since)
            let to = calendar.startOfDay(for: now)
            days = (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
        }
        let points = Self.points(notes: notes, experiences: experienceCategories.count, feedback: liked + disliked)
        return GrowthSnapshot(totalExperiences: experienceCategories.count, counts: counts,
                              explored: counts.filter { $0.value > 0 }.count, daysTogether: max(0, days),
                              notes: notes, liked: liked, disliked: disliked, points: points,
                              level: .level(points: points))
    }
}

/// AIが覚えていること(メモ)の扱い
public enum CompanionMemory {
    /// 覚えておける数(古いAIのメモから消える。本人が書いたものは消さない)
    public static let capacity = 40

    /// 新しいメモを足せるか(同じような内容がもうあれば足さない)
    public static func isNew(_ text: String, existing: [String]) -> Bool {
        let key = CompanionBrain.normalize(text)
        guard key.count >= 2 else { return false }
        return !existing.contains { other in
            let o = CompanionBrain.normalize(other)
            return o == key || o.contains(key) || key.contains(o)
        }
    }

    /// 本人が書いた「わたしについて」を、プロンプト用のメモに分ける(読点・改行で区切る)
    public static func split(selfIntroduction text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n、。,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
            .prefix(12)
            .map { String($0.prefix(40)) }
    }
}
