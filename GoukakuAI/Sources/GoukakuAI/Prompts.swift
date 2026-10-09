import Foundation

/// AIへのお願いの書き方。
/// 話す中身はしばらない(「〜しない」「〜は避ける」を並べると、話し方に変な癖がつき、人と自然に話せなくなるため)。
/// 役割の説明は1文だけにして、あとは「いまの様子」と「この人について」を渡し、AIが自分の言葉で考える。
/// カードに出す提案とふり返りだけは、画面に並べるために「体験:」などの見出しの形を手本で見せる
/// (形が崩れても、AIの書いたことをそのまま使う)。
public enum PromptBook {
    /// 役割の説明(すべてのお願いで共通)
    public static let system = "あなたは、この人の相棒です。この人が人生の中でどんな体験ができるかを一緒に考えながら、思ったことを自分の言葉で自由に話します。"

    // MARK: 体験の提案(1回に1つ)

    static let suggestionFormat = "次の形で書いてください。\n体験:\nひとこと:\nはじめ方:\n時間:\n種類:"

    static let suggestionExample = (
        user: "いまの様子: 日曜日の朝(9時ごろ)。使える時間は30分くらい。場所は家。元気。\nこの人について: 料理が好き。\n\n「つくる」に近い体験を1つ。" + suggestionFormat,
        assistant: "体験: 冷蔵庫の残りで名前のない一品\nひとこと: レシピなしで作ると、自分でも思いがけない組み合わせが生まれて楽しいですよ。\nはじめ方: 冷蔵庫を開けて、目についた材料を3つ選ぶ\n時間: 30分\n種類: つくる"
    )

    /// 「いまの様子」と「この人について」のまとまり
    public static func contextBlock(_ c: CompanionContext, items: Int) -> String {
        var lines: [String] = []
        lines.append("いまの様子: \(c.whenPhrase)。使える時間は\(c.budget.phrase)。場所は\(c.place.phrase)。\(c.mood.phrase)。")
        let notes = c.notes.prefix(items)
        if !notes.isEmpty { lines.append("この人について: " + notes.map(sentence).joined()) }
        let recent = c.recentExperiences.prefix(max(2, items / 2))
        if !recent.isEmpty { lines.append("最近やった体験: " + recent.joined(separator: "、")) }
        let liked = c.liked.prefix(max(2, items / 2))
        if !liked.isEmpty { lines.append("気に入った体験: " + liked.joined(separator: "、")) }
        let disliked = c.disliked.prefix(max(2, items / 2))
        if !disliked.isEmpty { lines.append("合わなかった提案(似たものは避ける): " + disliked.joined(separator: "、")) }
        if !c.commits.isEmpty { lines.append("続けていること: " + c.commits.prefix(3).joined(separator: "、")) }
        return lines.joined(separator: "\n")
    }

    /// 体験を1つ考えてもらう(hint は発想のきっかけの言葉。小さなモデルが同じ話題に寄るのを防ぐ)
    public static func suggestion(context: CompanionContext, angle: ExperienceCategory, avoid: [String],
                                  tuning: GenerationTuning, temperature: Double = 0.85,
                                  hint: String? = nil) -> GenerationRequest {
        var prompt = contextBlock(context, items: tuning.contextItems)
        if !avoid.isEmpty {
            prompt += "\nもう出した体験(これとはテーマのちがうものにする): " + avoid.suffix(6).joined(separator: "、")
        }
        if let hint {
            prompt += "\n思いつきのきっかけ: 「\(hint)」(使わなくてもかまいません)"
        }
        prompt += "\n\n「\(angle.label)」に近い体験を1つ。" + suggestionFormat
        return GenerationRequest(system: system,
                                 examples: [ChatTurn(.user, suggestionExample.user), ChatTurn(.assistant, suggestionExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(180), temperature: temperature, topP: 0.95)
    }

    /// 続けていること(コミット)を、ちょっと楽しみな体験に変える工夫を1つ
    public static func reframe(commit: String, context: CompanionContext, avoid: [String],
                               tuning: GenerationTuning) -> GenerationRequest {
        var prompt = contextBlock(context, items: tuning.contextItems)
        if !avoid.isEmpty {
            prompt += "\nもう出した工夫(ちがうものにする): " + avoid.suffix(6).joined(separator: "、")
        }
        prompt += "\n\nこの人が続けている「\(commit)」を、やらされる作業ではなく、ちょっと楽しみな体験に変える工夫を1つ。" + suggestionFormat
        return GenerationRequest(system: system,
                                 examples: [ChatTurn(.user, suggestionExample.user), ChatTurn(.assistant, suggestionExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(180), temperature: 0.8, topP: 0.95)
    }

    // MARK: いつかの体験(人生の中で味わってみたいこと)

    static let lifeFormat = "次の形で書いてください。\n体験:\nひとこと:\n最初の一歩:\n種類:"

    static let lifeExample = (
        user: "この人について: 料理が好き。海の近くで育った。\n\n「そと」に近い、人生のどこかで味わってみたい「いつかの体験」を1つ。大きな体験でもかまいません。" + lifeFormat,
        assistant: "体験: 漁港の朝市で、とれたての魚を見る\nひとこと: 港の朝の活気は、スーパーの魚売り場とはまるで別の世界です。\n最初の一歩: 近くの漁港の朝市が何曜日にあるか調べてみる\n種類: そと"
    )

    public static func someday(context: CompanionContext, angle: ExperienceCategory, theme: String?,
                               avoid: [String], tuning: GenerationTuning) -> GenerationRequest {
        let notes = context.notes.prefix(tuning.contextItems)
        var prompt = "この人について: " + (notes.isEmpty ? "まだよく知らない。" : notes.map(sentence).joined())
        if let theme, !theme.trimmingCharacters(in: .whitespaces).isEmpty {
            prompt += "\nいま気になっていること: \(theme)"
        }
        if !avoid.isEmpty {
            prompt += "\nもう出した体験(ちがうものにする): " + avoid.suffix(8).joined(separator: "、")
        }
        prompt += "\n\n「\(angle.label)」に近い、人生のどこかで味わってみたい「いつかの体験」を1つ。大きな体験でもかまいません。" + lifeFormat
        return GenerationRequest(system: system,
                                 examples: [ChatTurn(.user, lifeExample.user), ChatTurn(.assistant, lifeExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(180), temperature: 0.9, topP: 0.95)
    }

    // MARK: やってみたあとのふり返り

    /// 返事・問いかけ・覚えておきたいこと(画面で分けて出すため、見出しをつけてもらう)
    static let reflectionFormat = "次の形で返事を書いてください。\n返事:\n問い:\nメモ:"

    static let reflectionExample = (
        user: "この人がやってみた体験を書きました。\n体験: 冷蔵庫の残りで名前のない一品\n書いたこと: 卵とトマトとチーズで焼いてみた。思ったよりおいしくて、名前を「朝の小さな太陽」にした。\n気持ち: たのしい\n\n" + reflectionFormat,
        assistant: "返事: 卵とトマトの組み合わせに「朝の小さな太陽」と名前をつけたところに、楽しんだ様子が出ていますね。\n問い: 次に名前をつけるとしたら、どんな材料で試してみたいですか?\nメモ: 料理に名前をつけて楽しむ"
    )

    public static func reflection(title: String, note: String, feeling: Feeling?,
                                  tuning: GenerationTuning) -> GenerationRequest {
        var prompt = "この人がやってみた体験を書きました。\n体験: \(oneLine(title))\n書いたこと: \(oneLine(note))"
        if let feeling { prompt += "\n気持ち: \(feeling.label)" }
        prompt += "\n\n" + reflectionFormat
        return GenerationRequest(system: system,
                                 examples: [ChatTurn(.user, reflectionExample.user), ChatTurn(.assistant, reflectionExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(300), temperature: 0.7, topP: 0.9)
    }

    // MARK: 週の手紙

    public static func letter(experiences: [String], achievedDays: Int, plannedDays: Int, notes: [String],
                              tuning: GenerationTuning) -> GenerationRequest {
        var prompt = ""
        if experiences.isEmpty {
            prompt += "この1週間、体験の記録はありませんでした。"
        } else {
            prompt += "この1週間にこの人がやってみた体験:\n" + experiences.prefix(8).map { "- \(oneLine($0))" }.joined(separator: "\n")
        }
        if plannedDays > 0 {
            prompt += "\n続けていることは、予定した\(plannedDays)日のうち\(achievedDays)日できました。"
        }
        if !notes.isEmpty {
            prompt += "\nこの人について: " + notes.prefix(tuning.contextItems).map(sentence).joined()
        }
        prompt += "\n\nこの1週間のこの人に、相棒として手紙を書いてください。来週やってみたくなる体験も添えてください。手紙の本文を書いてください。"
        return GenerationRequest(system: system, prompt: prompt, maxTokens: tuning.tokens(450), temperature: 0.8, topP: 0.95)
    }

    // MARK: 相棒の気づき(体験の記録から)

    /// やってみた体験の記録から、相棒が気づいたことを書いてもらう(育ちの画面)
    public static func insight(experiences: [ExperienceMemo], notes: [String], unexplored: [ExperienceCategory],
                               tuning: GenerationTuning) -> GenerationRequest {
        var prompt = "この人がやってみた体験の記録(新しい順):\n"
        prompt += experiences.prefix(12).map { memo in
            var line = "- \(oneLine(memo.title))(\(memo.category.label)"
            if let feeling = memo.feeling { line += "・\(feeling.label)" }
            line += ")"
            if !memo.note.isEmpty { line += ":" + String(oneLine(memo.note).prefix(40)) }
            return line
        }.joined(separator: "\n")
        if !notes.isEmpty {
            prompt += "\nこの人について: " + notes.prefix(tuning.contextItems).map(sentence).joined()
        }
        if let next = unexplored.first {
            prompt += "\nまだやっていない種類: " + unexplored.prefix(3).map(\.label).joined(separator: "、")
            prompt += "\n\nこの記録を見て、相棒として気づいたことを書いてください。まだやっていない「\(next.label)」の体験も1つ、誘ってみてください。気づいたことの本文を書いてください。"
        } else {
            prompt += "\n\nこの記録を見て、相棒として気づいたことを書いてください。気づいたことの本文を書いてください。"
        }
        return GenerationRequest(system: system, prompt: prompt, maxTokens: tuning.tokens(360), temperature: 0.7, topP: 0.95)
    }

    // MARK: 相棒と話す

    /// 会話の役割の説明。決まりごとは足さず、この人について知っていることと、いまの時間だけを添える
    public static func chatSystem(context: CompanionContext, tuning: GenerationTuning) -> String {
        var text = system
        let notes = context.notes.prefix(tuning.contextItems)
        if !notes.isEmpty { text += "\nこの人について知っていること: " + notes.map(sentence).joined() }
        let recent = context.recentExperiences.prefix(3)
        if !recent.isEmpty { text += "\n最近やった体験: " + recent.joined(separator: "、") }
        text += "\nいま: \(context.whenPhrase)"
        return text
    }

    public static func chat(context: CompanionContext, history: [ChatTurn], message: String,
                            tuning: GenerationTuning) -> GenerationRequest {
        let turns = Array(history.suffix(tuning.chatTurns * 2))
        return GenerationRequest(system: chatSystem(context: context, tuning: tuning), history: turns,
                                 prompt: message, maxTokens: tuning.tokens(800), temperature: 0.8, topP: 0.95)
    }

    // MARK: 小さな道具

    /// 改行をつぶして1行に(プロンプトの形を崩さないため)
    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 「英語の勉強をしている」→「英語の勉強をしている。」
    static func sentence(_ text: String) -> String {
        let t = oneLine(text)
        guard let last = t.last else { return "" }
        return "。.!?！？".contains(last) ? t : t + "。"
    }
}

/// 発想のきっかけの言葉(種類ごと)。毎回ちがう言葉を添えて、提案が同じ話題に寄らないようにする
public enum IdeaHints {
    static let words: [ExperienceCategory: [String]] = [
        .learn: ["言葉", "地図", "歴史", "しくみ", "数字", "外国", "図鑑", "昔の自分"],
        .body: ["呼吸", "足の裏", "手", "背中", "リズム", "水", "目", "姿勢"],
        .make: ["紙", "台所", "写真", "声", "ことば遊び", "色", "手紙", "メモ"],
        .people: ["家族", "昔の友だち", "近所", "ありがとう", "声", "思い出", "おすすめ", "あいさつ"],
        .outside: ["空", "木", "道", "光", "風", "音", "影", "公園"],
        .mind: ["音楽", "香り", "感謝", "思い出", "静けさ", "明かり", "書くこと", "ひと口"],
        .living: ["机", "器", "窓", "靴", "冷蔵庫", "かばん", "植物", "寝る前"],
        .first: ["反対の手", "知らないジャンル", "初めての道", "知らない国", "引き出し", "目を閉じる", "番組", "おすすめ"],
    ]

    public static func pick(_ category: ExperienceCategory, seed: UInt64) -> String? {
        guard let list = words[category], !list.isEmpty else { return nil }
        var rng = SeededGenerator(seed: seed)
        return list.randomElement(using: &rng)
    }
}

/// 3つの提案をどの「種類」から出すかを決める(調子・場所・好みで重みを変えるだけで、締め出す種類はない)
public enum AnglePlanner {
    public static func angles(for context: CompanionContext, count: Int = 3, seed: UInt64) -> [ExperienceCategory] {
        var weights: [ExperienceCategory: Double] = [:]
        for c in ExperienceCategory.allCases { weights[c] = 1 }
        switch context.mood {
        case .tired:
            weights[.mind, default: 1] += 1.2
            weights[.living, default: 1] += 0.8
            weights[.body, default: 1] += 0.2
            weights[.first, default: 1] -= 0.5
            weights[.outside, default: 1] -= 0.3
        case .energetic:
            weights[.outside, default: 1] += 0.8
            weights[.first, default: 1] += 0.8
            weights[.body, default: 1] += 0.6
            weights[.make, default: 1] += 0.4
        case .normal:
            break
        }
        if context.place == .outside {
            weights[.outside, default: 1] += 0.8
            weights[.living, default: 1] -= 0.6
        }
        if context.budget == .five {
            weights[.outside, default: 1] -= 0.4
            weights[.first, default: 1] -= 0.2
        }
        for (category, score) in context.categoryAffinity {
            weights[category, default: 1] += Double(max(-3, min(3, score))) * 0.25
        }

        var rng = SeededGenerator(seed: seed)
        var pool = ExperienceCategory.allCases.filter { (weights[$0] ?? 0) > 0.05 }
        var picked: [ExperienceCategory] = []
        while picked.count < count && !pool.isEmpty {
            let total = pool.reduce(0) { $0 + max(0.05, weights[$1] ?? 0) }
            var roll = Double.random(in: 0..<total, using: &rng)
            var index = pool.count - 1
            for (i, c) in pool.enumerated() {
                roll -= max(0.05, weights[c] ?? 0)
                if roll < 0 { index = i; break }
            }
            picked.append(pool.remove(at: index))
        }
        return picked
    }
}

/// 種(seed)から同じ並びを出す乱数(テストで結果を固定するため)
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
