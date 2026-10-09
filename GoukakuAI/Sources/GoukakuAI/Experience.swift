import Foundation

/// 体験の種類(体験の地図の8つの区画)
public enum ExperienceCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case learn      // 学ぶ
    case body       // からだ
    case make       // つくる
    case people     // ひと
    case outside    // そと
    case mind       // こころ
    case living     // くらし
    case first      // はじめて(いつもと違う)

    /// 画面とプロンプトで使う名前
    public var label: String {
        switch self {
        case .learn: return "学ぶ"
        case .body: return "からだ"
        case .make: return "つくる"
        case .people: return "ひと"
        case .outside: return "そと"
        case .mind: return "こころ"
        case .living: return "くらし"
        case .first: return "はじめて"
        }
    }

    /// SF Symbols の名前
    public var symbol: String {
        switch self {
        case .learn: return "book"
        case .body: return "figure.walk"
        case .make: return "scissors"
        case .people: return "person.2"
        case .outside: return "leaf"
        case .mind: return "cloud"
        case .living: return "house"
        case .first: return "sparkle"
        }
    }

    /// 地図の区画に添える短い説明
    public var blurb: String {
        switch self {
        case .learn: return "知る・わかる"
        case .body: return "動く・感じる"
        case .make: return "つくる・書く"
        case .people: return "人と過ごす"
        case .outside: return "外に出る"
        case .mind: return "ととのえる"
        case .living: return "暮らしを味わう"
        case .first: return "いつもと違う"
        }
    }

    /// モデルが書いた「種類」を8つのどれかに寄せる。わからなければ nil
    public static func from(text raw: String) -> ExperienceCategory? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for c in allCases where text.contains(c.label) { return c }
        let table: [(ExperienceCategory, [String])] = [
            (.learn, ["学", "知る", "調べ", "読む", "勉強", "英語", "語学", "考え"]),
            (.outside, ["外", "自然", "散歩", "景色", "空", "街", "公園"]),
            (.body, ["体", "身体", "運動", "動", "歩", "呼吸", "ストレッチ", "感じる"]),
            (.make, ["作", "創", "描", "書く", "料理", "工作", "写真", "音楽", "演奏"]),
            (.people, ["人", "友", "家族", "話", "会う", "つながり"]),
            (.mind, ["心", "気持ち", "休", "落ち着", "静", "見る", "聴く", "味わ", "ひたす"]),
            (.living, ["暮らし", "生活", "家", "片づけ", "掃除", "食", "お茶"]),
            (.first, ["初", "新し", "挑戦", "冒険", "いつもと違う", "未知"]),
        ]
        for (category, words) in table where words.contains(where: { text.contains($0) }) {
            return category
        }
        return nil
    }
}

/// かかる時間のめやす
public enum DurationBucket: Int, Codable, Sendable, CaseIterable, Comparable {
    case five = 5
    case fifteen = 15
    case thirty = 30
    case hour = 60
    case halfDay = 240

    public var label: String {
        switch self {
        case .five: return "5分"
        case .fifteen: return "15分"
        case .thirty: return "30分"
        case .hour: return "1時間"
        case .halfDay: return "半日"
        }
    }

    public static func < (lhs: DurationBucket, rhs: DurationBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 分数にいちばん近いもの(切り上げ)
    public static func nearest(minutes: Int) -> DurationBucket {
        allCases.first { minutes <= $0.rawValue } ?? .halfDay
    }

    /// 「15分」「1時間」「半日」「10 分」などを読む。読めなければ nil
    public static func from(text raw: String) -> DurationBucket? {
        let text = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        if text.contains("半日") { return .halfDay }
        if text.contains("時間") {
            let digits = Self.leadingNumber(in: text) ?? 1
            return digits >= 2 ? .halfDay : .hour
        }
        if let minutes = Self.leadingNumber(in: text) { return nearest(minutes: minutes) }
        return nil
    }

    private static func leadingNumber(in text: String) -> Int? {
        let normalized = text.unicodeScalars.map { scalar -> Character in
            // 全角数字を半角に
            if (0xFF10...0xFF19).contains(scalar.value), let half = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) {
                return Character(half)
            }
            return Character(scalar)
        }
        var digits = ""
        for ch in normalized {
            if ch.isASCII && ch.isNumber { digits.append(ch) } else if !digits.isEmpty { break }
        }
        return Int(digits)
    }
}

/// いま使える時間(画面のチップ)
public enum TimeBudget: Int, Codable, Sendable, CaseIterable {
    case five = 5
    case fifteen = 15
    case thirty = 30
    case hourPlus = 60

    public var label: String {
        switch self {
        case .five: return "5分"
        case .fifteen: return "15分"
        case .thirty: return "30分"
        case .hourPlus: return "1時間〜"
        }
    }

    /// プロンプトに書く言い方
    public var phrase: String {
        switch self {
        case .five: return "5分くらい"
        case .fifteen: return "15分くらい"
        case .thirty: return "30分くらい"
        case .hourPlus: return "1時間以上"
        }
    }

    /// この時間に収まる体験か
    public func allows(_ duration: DurationBucket) -> Bool {
        switch self {
        case .five: return duration <= .five
        case .fifteen: return duration <= .fifteen
        case .thirty: return duration <= .thirty
        case .hourPlus: return true
        }
    }
}

/// いまいる場所(位置情報は使わない。本人が選ぶ)
public enum Place: String, Codable, Sendable, CaseIterable {
    case home
    case outside
    case anywhere

    public var label: String {
        switch self {
        case .home: return "家"
        case .outside: return "外"
        case .anywhere: return "どこでも"
        }
    }

    public var phrase: String {
        switch self {
        case .home: return "家"
        case .outside: return "外出先"
        case .anywhere: return "決まっていない"
        }
    }
}

/// いまの調子
public enum Mood: String, Codable, Sendable, CaseIterable {
    case energetic
    case normal
    case tired

    public var label: String {
        switch self {
        case .energetic: return "元気"
        case .normal: return "ふつう"
        case .tired: return "おだやかに"
        }
    }

    public var phrase: String {
        switch self {
        case .energetic: return "元気"
        case .normal: return "ふつう"
        case .tired: return "少し疲れていて、おだやかに過ごしたい"
        }
    }
}

/// やってみたあとの気持ち
public enum Feeling: String, Codable, Sendable, CaseIterable {
    case fun
    case discovery
    case calm
    case moved
    case hard
    case soso

    public var label: String {
        switch self {
        case .fun: return "たのしい"
        case .discovery: return "発見"
        case .calm: return "おだやか"
        case .moved: return "うれしい"
        case .hard: return "むずかしい"
        case .soso: return "ふつう"
        }
    }

    public var symbol: String {
        switch self {
        case .fun: return "face.smiling"
        case .discovery: return "lightbulb"
        case .calm: return "leaf"
        case .moved: return "heart"
        case .hard: return "mountain.2"
        case .soso: return "minus.circle"
        }
    }
}

/// 体験の候補(AIか体験帳が出したもの。保存する前の形)
public struct ExperienceDraft: Codable, Sendable, Equatable, Hashable {
    public enum Origin: Codable, Sendable, Equatable, Hashable {
        /// AIが考えた(エンジンの名前)
        case ai(String)
        /// 体験帳(ルールで選んだ。項目の id)
        case library(String)
        /// 体験帳の体験に、AIがこの人向けのひとことを添えた(エンジンの名前・項目の id)。
        /// 小さいモデルは自由に考えると話がそれやすいので、確かな体験を土台にする
        case tailored(String, String)
        /// 本人が書いた
        case user
    }

    public var title: String
    /// どんな気持ちや発見がありそうか
    public var line: String
    /// 最初の小さな一歩
    public var firstStep: String
    public var duration: DurationBucket
    public var category: ExperienceCategory
    public var origin: Origin

    public init(title: String, line: String, firstStep: String, duration: DurationBucket,
                category: ExperienceCategory, origin: Origin) {
        self.title = title
        self.line = line
        self.firstStep = firstStep
        self.duration = duration
        self.category = category
        self.origin = origin
    }

    /// AIが関わったか(自分で考えた・体験帳にひとことを添えた)
    public var isFromAI: Bool {
        switch origin {
        case .ai, .tailored: return true
        case .library, .user: return false
        }
    }

    /// 体験帳の体験に、AIがひとことを添えたものか
    public var isTailored: Bool {
        if case .tailored = origin { return true }
        return false
    }
}

/// やってみたあとの返事(ふり返り)
public struct ReflectionDraft: Codable, Sendable, Equatable {
    public var reply: String
    /// 体験をもう少し味わうための問い
    public var question: String?
    /// AIが「覚えておきたい」と思ったこと(本人が覚えるかを決める)
    public var noteCandidate: String?
    public var fromAI: Bool

    public init(reply: String, question: String?, noteCandidate: String?, fromAI: Bool) {
        self.reply = reply
        self.question = question
        self.noteCandidate = noteCandidate
        self.fromAI = fromAI
    }
}
