import Foundation

/// AIへのお願いの書き方。小さなモデルでも形を守れるよう、
/// ① 短い役割の説明 ② 手本の1往復 ③ 1回に1つだけ・決まった行だけで書く、にしている
/// (Gemma 4 E2B・Qwen3.5・LFM2.5 で試して決めた形。リポジトリの scripts/prompt-lab を参照)。
public enum PromptBook {
    /// 役割の説明(すべてのお願いで共通)
    public static let system = """
    あなたは、この人が人生の中でできる「体験」を一緒に見つける相棒です。
    体験とは、気持ちや五感が少し動く、小さな発見のある出来事です。義務やノルマではありません。
    「〜しなさい」「〜すべき」は使わず、「〜してみると、〜かも」と誘います。決めるのは本人で、点数はつけません。
    お金がかからず、安全で、今の様子に合うことを選びます。やさしく短い日本語で書き、絵文字は使いません。
    """

    // MARK: 体験の提案(1回に1つ)

    static let suggestionFormat = "次の5行だけで書いてください。\n体験:\nひとこと:\nはじめ方:\n時間:\n種類:"

    static let suggestionExample = (
        user: "いまの様子: 日曜日の朝(9時ごろ)。使える時間は30分くらい。場所は家。元気。\nこの人について: 料理が好き。\n\n「つくる」に近い体験を1つ。" + suggestionFormat,
        assistant: "体験: 冷蔵庫の残りで名前のない一品\nひとこと: 決まったレシピがないと、思いがけない組み合わせに出会えるかも\nはじめ方: 冷蔵庫を開けて、目についた材料を3つ選ぶ\n時間: 30分\n種類: つくる"
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

    /// 体験を1つ考えてもらう
    public static func suggestion(context: CompanionContext, angle: ExperienceCategory, avoid: [String],
                                  tuning: GenerationTuning, temperature: Double = 0.85) -> GenerationRequest {
        var prompt = contextBlock(context, items: tuning.contextItems)
        if !avoid.isEmpty {
            prompt += "\nもう出した体験(ちがうものにする): " + avoid.suffix(6).joined(separator: "、")
        }
        prompt += "\n\n「\(angle.label)」に近い体験を1つ。" + suggestionFormat
        return GenerationRequest(system: system,
                                 history: [ChatTurn(.user, suggestionExample.user), ChatTurn(.assistant, suggestionExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(110), temperature: temperature, topP: 0.95)
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
                                 history: [ChatTurn(.user, suggestionExample.user), ChatTurn(.assistant, suggestionExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(110), temperature: 0.8, topP: 0.95)
    }

    // MARK: いつかの体験(人生の中で味わってみたいこと)

    static let lifeFormat = "次の4行だけで書いてください。\n体験:\nひとこと:\n最初の一歩:\n種類:"

    static let lifeExample = (
        user: "この人について: 料理が好き。海の近くで育った。\n\n「そと」に近い、人生のどこかで味わってみたい「いつかの体験」を1つ。大きな体験でもかまいません。" + lifeFormat,
        assistant: "体験: 漁港の朝市で、とれたての魚を見る\nひとこと: 海から台所までの道のりを、目と鼻で感じられるかも\n最初の一歩: 近くの漁港の朝市が何曜日にあるか調べてみる\n種類: そと"
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
                                 history: [ChatTurn(.user, lifeExample.user), ChatTurn(.assistant, lifeExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(110), temperature: 0.9, topP: 0.95)
    }

    // MARK: やってみたあとのふり返り

    static let reflectionFormat = "次の3行だけで返事を書いてください。\n返事:\n問い:\nメモ:"

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
                                 history: [ChatTurn(.user, reflectionExample.user), ChatTurn(.assistant, reflectionExample.assistant)],
                                 prompt: prompt, maxTokens: tuning.tokens(140), temperature: 0.7, topP: 0.9)
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
        prompt += "\n\nこの人に、短い手紙を3〜4文で書いてください。できたことや感じたことにふれて、来週ためしてみたくなる体験を1つだけ添えます。数字で評価したり、ほかの人と比べたりはしません。手紙の文だけを書いてください。"
        return GenerationRequest(system: system, prompt: prompt, maxTokens: tuning.tokens(220), temperature: 0.8, topP: 0.95)
    }

    // MARK: 相棒と話す

    public static func chatSystem(context: CompanionContext, tuning: GenerationTuning) -> String {
        var text = system + "\n返事は2〜4文の話し言葉で書きます。わからないことは、わからないと言います。病気・法律・お金の判断が要る話は、専門家に相談するよう伝えます。"
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
                                 prompt: message, maxTokens: tuning.tokens(260), temperature: 0.8, topP: 0.95)
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

/// 3つの提案をどの「種類」から出すかを決める(調子・場所・時間帯・好みで重みを変える)
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
        let tod = context.timeOfDay
        if !tod.allowsOutside || (context.place == .home && tod == .night) {
            weights[.outside] = 0
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
