import Foundation

/// モデルの出力の掃除(考えている途中の部分・特別なトークン・Markdown の飾りを取る)
public enum OutputCleaner {
    static let specialTokens = [
        "<|im_end|>", "<|im_start|>", "<|endoftext|>", "<end_of_turn>", "<start_of_turn>", "<turn|>", "<|turn>",
        "<eos>", "<bos>", "<|eot_id|>", "<|end|>", "</s>", "<|startoftext|>", "<channel|>",
    ]

    /// 表示できる形にする。考えている途中(<think> が閉じていない)なら空を返す
    public static func clean(_ raw: String) -> String {
        var text = raw
        // <think> … </think>(Qwen など)
        while let open = text.range(of: "<think>") {
            if let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                text.removeSubrange(open.lowerBound..<text.endIndex)
            }
        }
        if let close = text.range(of: "</think>") {   // 開きタグが前のチャンクにあった
            text.removeSubrange(text.startIndex..<close.upperBound)
        }
        // Gemma の思考チャンネル <|channel>thought … <channel|>
        while let open = text.range(of: "<|channel>") {
            if let close = text.range(of: "<channel|>", range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                text.removeSubrange(open.lowerBound..<text.endIndex)
            }
        }
        for token in specialTokens {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 行頭の飾り(**・#・-・・・番号)と行末の ** を取る
    static func stripDecoration(_ line: String) -> String {
        var s = Substring(line.trimmingCharacters(in: .whitespaces))
        var changed = true
        while changed {
            changed = false
            for prefix in ["**", "*", "#", "- ", "・", "• ", "> "] where s.hasPrefix(prefix) {
                s = s.dropFirst(prefix.count).drop { $0 == " " || $0 == "　" }
                changed = true
            }
            // 1. 1) (1) ① など
            if let first = s.first {
                if "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳".contains(first) {
                    s = s.dropFirst().drop { $0 == " " || $0 == "　" || $0 == "." }
                    changed = true
                } else if first.isNumber || first == "(" || first == "（" {
                    let rest = s.drop { $0.isNumber || $0 == "(" || $0 == "（" }
                    if rest.count < s.count, let next = rest.first, ".)）.、:：".contains(next) {
                        s = rest.dropFirst().drop { $0 == " " || $0 == "　" }
                        changed = true
                    }
                }
            }
        }
        var out = String(s)
        out = out.replacingOccurrences(of: "**", with: "")
        return out.trimmingCharacters(in: .whitespaces)
    }
}

/// 「キー: 値」の行を読む(全角のコロンや、コロンの抜けにも寛容に)
public enum FieldReader {
    /// 同じ意味のキー(先頭が正式名)
    public static let aliases: [String: [String]] = [
        "体験": ["体験", "名前", "タイトル", "体験名"],
        "ひとこと": ["ひとこと", "一言", "説明"],
        "はじめ方": ["はじめ方", "始め方", "最初の一歩", "一歩目", "一歩", "はじめの一歩"],
        "時間": ["時間", "所要時間", "かかる時間"],
        "種類": ["種類", "カテゴリ", "カテゴリー", "分類"],
        "返事": ["返事", "返答", "回答", "ことば", "答え"],
        "問い": ["問い", "質問", "問いかけ", "といかけ"],
        "メモ": ["メモ", "覚えておくこと"],
    ]

    /// 1行を (正式なキー, 値) に分ける。キーで始まらなければ nil
    public static func split(_ rawLine: String, keys: [String]) -> (key: String, value: String)? {
        let line = OutputCleaner.stripDecoration(rawLine)
        guard !line.isEmpty else { return nil }
        // 長い別名から試す(「一歩目」を「一歩」より先に)
        var candidates: [(canonical: String, alias: String)] = []
        for key in keys {
            for alias in aliases[key] ?? [key] { candidates.append((key, alias)) }
        }
        candidates.sort { $0.alias.count > $1.alias.count }
        for (canonical, alias) in candidates {
            var rest = Substring(line)
            var bracketed = false
            if rest.hasPrefix("【\(alias)】") {
                rest = rest.dropFirst(alias.count + 2)
                bracketed = true
            } else if rest.hasPrefix(alias) {
                rest = rest.dropFirst(alias.count)
            } else {
                continue
            }
            let afterAlias = rest
            rest = rest.drop { $0 == " " || $0 == "\u{3000}" || $0 == "*" }
            let hadSpace = rest.count < afterAlias.count
            if let first = rest.first, ":\u{FF1A}\u{3011}\u{300D}=".contains(first) {
                rest = rest.dropFirst()
            } else if !hadSpace && !bracketed {
                // 区切りなし:「時間15分」「種類からだ」だけ受け付ける(「体験してみる」のような文を誤読しない)
                guard canonical == "時間" || canonical == "種類" else { continue }
            }
            let value = cleanValue(String(rest))
            return (canonical, value)
        }
        return nil
    }

    /// 値の掃除:前後の空白・かぎかっこ・「(15文字)」のような注釈
    static func cleanValue(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: CharacterSet(charactersIn: " 　*\t"))
        // (39文字) (30文字まで) のような注釈を消す
        while let open = v.range(of: "(", options: .backwards) ?? v.range(of: "（", options: .backwards),
              v[open.lowerBound...].contains("文字") {
            v = String(v[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if v.count >= 2, let f = v.first, let l = v.last,
           (f == "「" && l == "」") || (f == "\"" && l == "\"") || (f == "『" && l == "』") {
            v = String(v.dropFirst().dropLast())
        }
        return v.trimmingCharacters(in: .whitespaces)
    }

    /// 文章全体を、キーごとの値のまとまりに分ける。startKey が出るたびに新しいまとまり
    public static func blocks(in text: String, keys: [String], startKey: String) -> [[String: String]] {
        var result: [[String: String]] = []
        var current: [String: String] = [:]
        var lastKey: String?
        for rawLine in text.components(separatedBy: .newlines) {
            if let (key, value) = split(rawLine, keys: keys) {
                if key == startKey, !current.isEmpty {
                    result.append(current)
                    current = [:]
                }
                if current[key] == nil || current[key]?.isEmpty == true {
                    current[key] = value
                }
                lastKey = key
            } else {
                // 値が次の行に続いている(キーの行が空だった)ときだけつなぐ
                let line = OutputCleaner.stripDecoration(rawLine)
                if let k = lastKey, !line.isEmpty, current[k]?.isEmpty == true {
                    current[k] = cleanValue(line)
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// 体験の提案・ふり返り・手紙を読む。
/// 中身でははじかない(AIが書いたことは、そのまま本人に見せる)。見るのは、カードに並べられる形かどうかだけ
public enum ExperienceParser {
    static let suggestionKeys = ["体験", "ひとこと", "はじめ方", "時間", "種類"]

    /// 体験の候補を読む(1つ目のまとまり)。見出しの形でなければ nil。
    /// loose なら、見出しがなくても AIの書いたことをそのまま使う(1行目を名前、残りをひとことに)
    public static func suggestion(from raw: String, angle: ExperienceCategory, budget: TimeBudget,
                                  engine: String, loose: Bool = false) -> ExperienceDraft? {
        let text = OutputCleaner.clean(raw)
        let blocks = FieldReader.blocks(in: text, keys: suggestionKeys, startKey: "体験")
        for block in blocks {
            if let draft = draft(from: block, angle: angle, budget: budget, engine: engine) {
                return draft
            }
        }
        guard loose, let block = looseBlock(text) else { return nil }
        return draft(from: block, angle: angle, budget: budget, engine: engine)
    }

    static func draft(from block: [String: String], angle: ExperienceCategory, budget: TimeBudget?,
                      engine: String) -> ExperienceDraft? {
        guard var title = block["体験"], !title.isEmpty else { return nil }
        title = trimTitle(title)
        guard !title.isEmpty else { return nil }
        let line = trimSentence(block["ひとこと"] ?? "", limit: 240)
        let step = trimSentence(block["はじめ方"] ?? "", limit: 200)
        // 時間は、AIが書いたものをそのまま(書いていなければ、使える時間から)
        let duration = block["時間"].flatMap(DurationBucket.from(text:)) ?? budget.map(defaultDuration) ?? .fifteen
        let category = block["種類"].flatMap(ExperienceCategory.from(text:)) ?? angle
        return ExperienceDraft(title: title, line: line, firstStep: step, duration: duration,
                               category: category, origin: .ai(engine))
    }

    /// 見出しのそろっていない文章を、カードの形にする
    /// (見出しのついた行はその欄に、見出しのない最初の行を名前に、残りをひとことに)
    static func looseBlock(_ text: String) -> [String: String]? {
        var block: [String: String] = [:]
        var free: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            if let (key, value) = FieldReader.split(rawLine, keys: suggestionKeys) {
                if !value.isEmpty, block[key] == nil { block[key] = value }
            } else {
                let line = OutputCleaner.stripDecoration(rawLine)
                if !line.isEmpty { free.append(FieldReader.cleanValue(line)) }
            }
        }
        if block["体験"] == nil {
            if !free.isEmpty {
                block["体験"] = free.removeFirst()
            } else if let line = block.removeValue(forKey: "ひとこと") {
                block["体験"] = line
            } else {
                return nil
            }
        }
        if block["ひとこと"] == nil, !free.isEmpty { block["ひとこと"] = free.joined(separator: " ") }
        return block
    }

    static func defaultDuration(_ budget: TimeBudget) -> DurationBucket {
        switch budget {
        case .five: return .five
        case .fifteen: return .fifteen
        case .thirty: return .thirty
        case .hourPlus: return .hour
        }
    }

    /// 「いつかの体験」を読む(時間は問わない)
    public static func someday(from raw: String, angle: ExperienceCategory, engine: String,
                               loose: Bool = false) -> ExperienceDraft? {
        let text = OutputCleaner.clean(raw)
        var blocks = FieldReader.blocks(in: text, keys: suggestionKeys, startKey: "体験")
        if loose, let block = looseBlock(text) { blocks.append(block) }
        for block in blocks {
            if var draft = draft(from: block, angle: angle, budget: nil, engine: engine) {
                draft.duration = block["時間"].flatMap(DurationBucket.from(text:)) ?? .halfDay
                return draft
            }
        }
        return nil
    }

    /// ふり返りの返事を読む
    public static func reflection(from raw: String, title: String, note: String) -> ReflectionDraft? {
        let text = OutputCleaner.clean(raw)
        guard !text.isEmpty else { return nil }
        let keys = ["返事", "問い", "メモ"]
        var reply = ""
        var question: String?
        var memo: String?
        var loose: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            if let (key, value) = FieldReader.split(rawLine, keys: keys) {
                switch key {
                case "返事": if reply.isEmpty { reply = value }
                case "問い": if question == nil, !value.isEmpty { question = value }
                case "メモ": if memo == nil { memo = value }
                default: break
                }
            } else {
                let line = OutputCleaner.stripDecoration(rawLine)
                if !line.isEmpty, question == nil, memo == nil { loose.append(line) }
            }
        }
        if reply.isEmpty { reply = loose.joined(separator: "\n") }
        // 「返事: 回答: …」のように見出しが重なっていたら外す
        if let (_, inner) = FieldReader.split(reply, keys: ["返事"]), !inner.isEmpty { reply = inner }
        reply = trimSentence(reply, limit: 800)
        // 空の返事と、書いたことをそのまま写しただけのもの(生成の失敗)は使わない
        let normalizedNote = note.replacingOccurrences(of: " ", with: "")
        if reply.isEmpty || reply.replacingOccurrences(of: " ", with: "") == normalizedNote { return nil }
        if let q = question {
            question = trimSentence(q, limit: 400)
            // 「問い: -」のような、記号だけの問いは出さない
            if let value = question, !value.contains(where: { $0.isLetter }) {
                question = nil
            }
        }
        return ReflectionDraft(reply: reply, question: question, noteCandidate: noteCandidate(memo, title: title),
                               fromAI: true)
    }

    /// 覚えておきたいこと(本人が「覚えてもらう」を押したときだけ覚えるので、ここでは「なし」だけを外す)
    static func noteCandidate(_ raw: String?, title: String) -> String? {
        guard var memo = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty else { return nil }
        memo = trimSentence(memo, limit: 120)
        let none = ["なし", "特になし", "とくになし", "ない", "無し", "なし。", "-", "ー", "none", "None", "N/A"]
        if none.contains(memo) || memo.hasPrefix("なし") || !memo.contains(where: { $0.isLetter }) { return nil }
        if memo == title || memo.hasPrefix("書いたこと") { return nil }
        if memo.hasSuffix("。") { memo.removeLast() }
        return memo
    }

    /// 手紙・会話の返事を読む(書いたことはそのまま。見出しと飾りの ** だけ外す)
    public static func prose(from raw: String, limit: Int = 4000) -> String? {
        var text = OutputCleaner.clean(raw)
        for prefix in ["手紙:", "手紙：", "返事:", "返事："] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.replacingOccurrences(of: "**", with: "")
        guard !text.isEmpty else { return nil }
        if text.count > limit {
            let cut = text.prefix(limit)
            if let end = cut.lastIndex(where: { "。.!?！？".contains($0) }) { text = String(cut[...end]) } else { text = String(cut) }
        }
        return text
    }

    // MARK: 長さの調整(カードに並べるためだけ。中身は変えない)

    static func trimTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        while let last = t.last, "。.、,".contains(last) { t.removeLast() }
        if t.count > 40, let cut = t.firstIndex(where: { "、。,(（".contains($0) }), t.distance(from: t.startIndex, to: cut) >= 4 {
            t = String(t[..<cut])
        }
        if t.count > 60 { t = String(t.prefix(60)) + "…" }
        return t
    }

    static func trimSentence(_ raw: String, limit: Int) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        let cut = t.prefix(limit)
        if let end = cut.lastIndex(where: { "。!?！？".contains($0) }) { return String(cut[...end]) }
        return String(cut) + "…"
    }
}

/// 生成のくり返し(小さなモデルが同じ行を何度も書きつづける)を見つけて止める。
/// 中身でははじかない。同じ行(8文字以上)が3回目に出たら「くり返し」とみなし、くり返しが始まる前までを使う
public enum RepetitionGuard {
    public static let minimumLength = 8
    public static let limit = 3

    /// (使う文, くり返しに入っていたか)
    public static func check(_ text: String) -> (text: String, looping: Bool) {
        let lines = text.components(separatedBy: "\n")
        var counts: [String: Int] = [:]
        var firstRepeat: Int?
        for (index, line) in lines.enumerated() {
            let key = OutputCleaner.stripDecoration(line).filter { !$0.isWhitespace }
            guard key.count >= minimumLength else { continue }
            let count = (counts[key] ?? 0) + 1
            counts[key] = count
            if count == 2, firstRepeat == nil { firstRepeat = index }
            if count >= limit {
                let cut = firstRepeat ?? index
                let kept = lines[..<cut].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return (kept, true)
            }
        }
        return (text, false)
    }
}

/// 文字の種類を調べる
public enum TextCheck {
    /// ひらがな・カタカナ・漢字を1文字以上含むか
    public static func hasJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            (0x3040...0x30FF).contains(s.value) || (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
        }
    }
}
