import XCTest
@testable import GoukakuAI

/// 実際のモデル(Gemma 4 E2B・Qwen3.5・LFM2.5)が手元で返した文をそのまま使って、読み取りを確かめる
final class ParsingTests: XCTestCase {
    func testGemmaSuggestion() throws {
        let raw = "体験: 新しい英語のフレーズを声に出してみる\nひとこと: 完璧でなくていい、まずは口に出してみるのが楽しいかも\nはじめ方: 今日覚えた新しい単語や短い文を一つ選んで、自分に話しかけてみる\n時間: 15分\n種類: 学ぶ"
        let d = try XCTUnwrap(ExperienceParser.suggestion(from: raw, angle: .mind, budget: .fifteen, engine: "Gemma"))
        XCTAssertEqual(d.title, "新しい英語のフレーズを声に出してみる")
        XCTAssertEqual(d.category, .learn)
        XCTAssertEqual(d.duration, .fifteen)
        XCTAssertTrue(d.line.hasPrefix("完璧でなくていい"))
        XCTAssertEqual(d.origin, .ai("Gemma"))
    }

    func testFullWidthColonsAndSpacedMinutes() throws {
        // Qwen3.5 2B:全角コロン・「5 分」
        let raw = "体験\u{FF1A}英語の暗記\nひとこと\u{FF1A}寝る前に単語帳を開くと、ことばが夢に出てくるかも\nはじめ方\u{FF1A}単語帳を枕元に置く\n時間\u{FF1A}5 分\n種類\u{FF1A}学ぶ"
        let d = try XCTUnwrap(ExperienceParser.suggestion(from: raw, angle: .mind, budget: .fifteen, engine: "Qwen"))
        XCTAssertEqual(d.title, "英語の暗記")
        XCTAssertEqual(d.duration, .five)
        XCTAssertEqual(d.category, .learn)
    }

    func testMissingColonsAndOddCategory() throws {
        // Qwen3.5 2B(Q8):コロンの抜け・「種類からだ」・知らない種類
        let raw = "体験: お腹の空気を深呼吸で満たす\nひとこと 疲れたら、ゆっくり吸い込むと気持ちよくなるかも\nはじめ方 3回ほど鼻から吸って口から吐く\n時間 15 分\n種類からだ"
        let d = try XCTUnwrap(ExperienceParser.suggestion(from: raw, angle: .mind, budget: .thirty, engine: "Qwen"))
        XCTAssertEqual(d.line, "疲れたら、ゆっくり吸い込むと気持ちよくなるかも")
        XCTAssertEqual(d.firstStep, "3回ほど鼻から吸って口から吐く")
        XCTAssertEqual(d.category, .body)
        XCTAssertEqual(d.duration, .fifteen)

        let odd = "体験: 窓の外をゆっくり見る\nひとこと: 息を吐くと体が軽くなるかも\nはじめ方: 椅子に座る\n時間: 15 分\n種類: 感じる"
        let o = try XCTUnwrap(ExperienceParser.suggestion(from: odd, angle: .outside, budget: .fifteen, engine: "Qwen"))
        XCTAssertEqual(o.category, .body)   // 「感じる」は からだ に寄せる
    }

    func testRepeatedBlocksTakeFirstAndAnnotationsAreRemoved() throws {
        // LFM2.5 JP:同じまとまりを2回書く・「(15文字)」の注釈・かぎかっこ
        let raw = "体験: 「星空観察」(15文字)\nひとこと: 暗い部屋で星を見ると、頭がスッキリする\nはじめ方: 窓の外を見つめる\n時間: 30分\n種類: こころ\n\n体験: 夕焼け散歩\nひとこと: 静かな美しさ"
        let d = try XCTUnwrap(ExperienceParser.suggestion(from: raw, angle: .mind, budget: .fifteen, engine: "LFM"))
        XCTAssertEqual(d.title, "星空観察")
        XCTAssertEqual(d.duration, .fifteen, "使える時間(15分)に合わせる")
    }

    func testMarkdownDecorationAndNumbering() throws {
        let raw = "1. **体験:** 雲の形に名前をつける\n- **ひとこと:** 見上げるだけで風が通るかも\n- **はじめ方:** 空を見上げる\n- **時間:** 5分\n- **種類:** そと"
        let d = try XCTUnwrap(ExperienceParser.suggestion(from: raw, angle: .mind, budget: .fifteen, engine: "x"))
        XCTAssertEqual(d.title, "雲の形に名前をつける")
        XCTAssertEqual(d.category, .outside)
        XCTAssertEqual(d.duration, .five)
    }

    func testThinkBlocksAndSpecialTokensAreRemoved() {
        XCTAssertEqual(OutputCleaner.clean("<think>\nうーん\n</think>\n\n体験: A<|im_end|>"), "体験: A")
        XCTAssertEqual(OutputCleaner.clean("<think>考え中"), "", "閉じていない思考は出さない")
        XCTAssertEqual(OutputCleaner.clean("<|channel>thought\nxx<channel|>返事: はい<turn|>"), "返事: はい")
    }

    func testRejectsSpendingAndNonJapanese() {
        let spend = "体験: 新しい服を買いに行く\nひとこと: 気分が変わるかも\nはじめ方: 店を探す\n時間: 1時間\n種類: そと"
        XCTAssertNil(ExperienceParser.suggestion(from: spend, angle: .outside, budget: .hourPlus, engine: "x"))
        let english = "体験: Go for a walk\nひとこと: nice\n時間: 15分"
        XCTAssertNil(ExperienceParser.suggestion(from: english, angle: .outside, budget: .hourPlus, engine: "x"))
        XCTAssertNil(ExperienceParser.suggestion(from: "", angle: .outside, budget: .five, engine: "x"))
    }

    func testDoesNotMistakeSentenceForKey() {
        // 「体験してみると…」はキーではない
        XCTAssertNil(FieldReader.split("体験してみると楽しいかも", keys: ["体験"]))
        XCTAssertEqual(FieldReader.split("【体験】空を見る", keys: ["体験"])?.value, "空を見る")
        XCTAssertEqual(FieldReader.split("最初の一歩: 調べる", keys: ["はじめ方"])?.key, "はじめ方")
    }

    func testGemmaReflection() throws {
        let raw = "返事: 夕焼けの色が心に染みたようですね。風を感じられたのですね。\n問い: 次はどんな景色に目を向けてみる?\nメモ: 夕焼けの色が心を落ち着かせる"
        let r = try XCTUnwrap(ExperienceParser.reflection(from: raw, title: "夕焼けを見に屋上へ", note: "空が変わるのを見た"))
        XCTAssertEqual(r.reply, "夕焼けの色が心に染みたようですね。風を感じられたのですね。")
        XCTAssertEqual(r.question, "次はどんな景色に目を向けてみる?")
        XCTAssertEqual(r.noteCandidate, "夕焼けの色が心を落ち着かせる")
        XCTAssertTrue(r.fromAI)
    }

    func testReflectionWithoutKeysAndBadMemo() throws {
        // 手本なしの Qwen:キーを書かない
        let raw = "夕焼けの空が色づく瞬間、少しだけ深呼吸できましたね。\nもっと長く見上げるのはどうでしょう。"
        let r = try XCTUnwrap(ExperienceParser.reflection(from: raw, title: "夕焼け", note: "空を見た"))
        XCTAssertTrue(r.reply.hasPrefix("夕焼けの空が色づく瞬間"))
        XCTAssertNil(r.noteCandidate)

        // LFM:メモが問いになっている・「なし」
        XCTAssertNil(ExperienceParser.noteCandidate("風をどれくらい感じましたか?", title: "x"))
        XCTAssertNil(ExperienceParser.noteCandidate("なし", title: "x"))
        XCTAssertNil(ExperienceParser.noteCandidate("書いたこと: 空を見た", title: "x"))
        XCTAssertEqual(ExperienceParser.noteCandidate("料理に名前をつけて楽しむ。", title: "x"), "料理に名前をつけて楽しむ")
    }

    func testReflectionThatOnlyEchoesTheNoteIsRejected() {
        let raw = "空の色が変わるのを10分見た"
        XCTAssertNil(ExperienceParser.reflection(from: raw, title: "夕焼け", note: "空の色が変わるのを10分見た"))
    }

    func testProse() {
        XCTAssertEqual(ExperienceParser.prose(from: "手紙: 今週もおつかれさま。"), "今週もおつかれさま。")
        XCTAssertNil(ExperienceParser.prose(from: "<think>…"))
        let long = String(repeating: "あいうえお。", count: 200)
        XCTAssertLessThanOrEqual(ExperienceParser.prose(from: long, limit: 100)!.count, 100)
    }

    func testDurationParsing() {
        XCTAssertEqual(DurationBucket.from(text: "15分"), .fifteen)
        XCTAssertEqual(DurationBucket.from(text: "１５分"), .fifteen)
        XCTAssertEqual(DurationBucket.from(text: "10 分"), .fifteen)
        XCTAssertEqual(DurationBucket.from(text: "1時間"), .hour)
        XCTAssertEqual(DurationBucket.from(text: "2時間"), .halfDay)
        XCTAssertEqual(DurationBucket.from(text: "半日"), .halfDay)
        XCTAssertNil(DurationBucket.from(text: "すぐ"))
    }

    func testCategoryMapping() {
        XCTAssertEqual(ExperienceCategory.from(text: "そと"), .outside)
        XCTAssertEqual(ExperienceCategory.from(text: "散歩"), .outside)
        XCTAssertEqual(ExperienceCategory.from(text: "描く"), .make)
        XCTAssertEqual(ExperienceCategory.from(text: "からだ・そと"), .body)
        XCTAssertNil(ExperienceCategory.from(text: "???"))
    }
}
