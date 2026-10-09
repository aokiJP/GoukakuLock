import Foundation

/// AIに渡す「いまの様子」と「この人について」。すべて端末の中のデータから作る(位置情報は使わない)
public struct CompanionContext: Sendable, Equatable {
    public var now: Date
    public var timeZone: TimeZone
    public var budget: TimeBudget
    public var place: Place
    public var mood: Mood
    /// AIが覚えていること・本人が書いた自分のこと
    public var notes: [String]
    /// 最近やってみた体験(新しい順)
    public var recentExperiences: [String]
    /// 気に入った体験(新しい順)
    public var liked: [String]
    /// 合わなかった提案(新しい順)
    public var disliked: [String]
    /// 今日のコミット(合格ロックで続けていること)
    public var commits: [String]
    /// 種類ごとの好み(いいね − ちがう。体験帳の選び方にも使う)
    public var categoryAffinity: [ExperienceCategory: Int]

    public init(now: Date = Date(), timeZone: TimeZone = .current, budget: TimeBudget = .fifteen,
                place: Place = .home, mood: Mood = .normal, notes: [String] = [],
                recentExperiences: [String] = [], liked: [String] = [], disliked: [String] = [],
                commits: [String] = [], categoryAffinity: [ExperienceCategory: Int] = [:]) {
        self.now = now
        self.timeZone = timeZone
        self.budget = budget
        self.place = place
        self.mood = mood
        self.notes = notes
        self.recentExperiences = recentExperiences
        self.liked = liked
        self.disliked = disliked
        self.commits = commits
        self.categoryAffinity = categoryAffinity
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    public var hour: Int { calendar.component(.hour, from: now) }

    /// 1=日 … 7=土
    public var weekday: Int { calendar.component(.weekday, from: now) }

    public var isWeekend: Bool { weekday == 1 || weekday == 7 }

    /// 時間帯の言い方
    public var timeOfDay: TimeOfDay { TimeOfDay(hour: hour) }

    /// 出かける体験を出してよいか(深夜は出さない。夜に家にいる人にも出さない)
    public var allowsGoingOut: Bool {
        timeOfDay.allowsOutside && !(place == .home && timeOfDay == .night)
    }

    /// 「金曜日の夜(21時ごろ)」
    public var whenPhrase: String {
        let days = ["日", "月", "火", "水", "木", "金", "土"]
        return "\(days[weekday - 1])曜日の\(timeOfDay.label)(\(hour)時ごろ)"
    }
}

/// 時間帯
public enum TimeOfDay: String, Sendable, CaseIterable {
    case lateNight   // 0-4
    case morning     // 5-10
    case daytime     // 11-15
    case evening     // 16-18
    case night       // 19-23

    public init(hour: Int) {
        switch hour {
        case 5...10: self = .morning
        case 11...15: self = .daytime
        case 16...18: self = .evening
        case 19...23: self = .night
        default: self = .lateNight
        }
    }

    public var label: String {
        switch self {
        case .lateNight: return "深夜"
        case .morning: return "朝"
        case .daytime: return "昼"
        case .evening: return "夕方"
        case .night: return "夜"
        }
    }

    /// 外に出る体験を出してよい時間帯か(深夜は家の中だけ)
    public var allowsOutside: Bool { self != .lateNight }
}
