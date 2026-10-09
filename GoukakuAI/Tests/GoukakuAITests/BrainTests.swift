import XCTest
@testable import GoukakuAI

final class BrainTests: XCTestCase {
    var nightAtHome: CompanionContext {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let friday9pm = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 21))!
        return CompanionContext(now: friday9pm, timeZone: cal.timeZone, budget: .fifteen, place: .home, mood: .tired,
                                notes: ["英語の勉強をしている", "散歩が好き"], recentExperiences: ["夕焼けを見に屋上へ"],
                                commits: ["英単語20個を覚えて、自作テストで7割"])
    }

    func collect<V>(_ stream: AsyncThrowingStream<BrainEvent<V>, Error>) async throws -> (values: [V], notices: [String], progress: Int) {
        var values: [V] = []
        var notices: [String] = []
        var progress = 0
        for try await event in stream {
            switch event {
            case .value(let v): values.append(v)
            case .notice(let n): notices.append(n)
            case .progress: progress += 1
            }
        }
        return (values, notices, progress)
    }

    func testContextBlockReadsNaturally() {
        let block = PromptBook.contextBlock(nightAtHome, items: 6)
        XCTAssertTrue(block.hasPrefix("いまの様子: 金曜日の夜(21時ごろ)。使える時間は15分くらい。場所は家。少し疲れていて、おだやかに過ごしたい。"), block)
        XCTAssertTrue(block.contains("この人について: 英語の勉強をしている。散歩が好き。"))
        XCTAssertTrue(block.contains("続けていること: 英単語20個を覚えて、自作テストで7割"))
    }

    func testSuggestionRequestUsesOneShotExample() {
        let req = PromptBook.suggestion(context: nightAtHome, angle: .mind, avoid: ["星を見る"], tuning: GenerationTuning())
        XCTAssertEqual(req.examples.count, 2)
        XCTAssertTrue(req.history.isEmpty, "手本は会話の履歴とは分けて渡す")
        XCTAssertEqual(req.examples[0].role, .user)
        XCTAssertTrue(req.examples[1].text.hasPrefix("体験: "))
        XCTAssertEqual(req.turns, req.examples)
        XCTAssertTrue(req.prompt.contains("「こころ」に近い体験を1つ"))
        XCTAssertTrue(req.prompt.contains("もう出した体験(これとはテーマのちがうものにする): 星を見る"))
        XCTAssertTrue(req.prompt.hasSuffix("体験:\nひとこと:\nはじめ方:\n時間:\n種類:"))
        XCTAssertEqual(req.system, PromptBook.system)
    }

    func testAnglesAreDistinctAndNothingIsShutOut() {
        var seen = Set<ExperienceCategory>()
        for seed in 0..<200 {
            let angles = AnglePlanner.angles(for: nightAtHome, count: 3, seed: UInt64(seed))
            XCTAssertEqual(angles.count, 3)
            XCTAssertEqual(Set(angles).count, 3)
            seen.formUnion(angles)
        }
        XCTAssertEqual(seen, Set(ExperienceCategory.allCases), "夜・家・疲れていても、締め出す種類はない")
        XCTAssertEqual(AnglePlanner.angles(for: nightAtHome, seed: 7), AnglePlanner.angles(for: nightAtHome, seed: 7))
    }

    /// どのお願いにも「〜しない」「〜は避ける」のような決まりごとを書かない(縛ると話し方に癖がつくため)
    func testPromptsCarryNoProhibitions() {
        let tuning = GenerationTuning()
        let memo = ExperienceMemo(title: "散歩", category: .outside, feeling: .calm, note: "風")
        let requests = [
            PromptBook.suggestion(context: nightAtHome, angle: .mind, avoid: [], tuning: tuning),
            PromptBook.reframe(commit: "英単語", context: nightAtHome, avoid: [], tuning: tuning),
            PromptBook.someday(context: nightAtHome, angle: .first, theme: nil, avoid: [], tuning: tuning),
            PromptBook.reflection(title: "散歩", note: "風", feeling: .calm, tuning: tuning),
            PromptBook.letter(experiences: ["散歩"], achievedDays: 3, plannedDays: 7, notes: [], tuning: tuning),
            PromptBook.insight(experiences: [memo], notes: [], unexplored: [.people], tuning: tuning),
            PromptBook.chat(context: nightAtHome, history: [], message: "こんばんは", tuning: tuning),
        ]
        let banned = ["しない", "しません", "使わず", "使いません", "避け", "禁止", "すべき", "なさい", "専門家",
                      "安全", "お金がかからず", "点数", "比べ", "評価", "かも」", "〜かも", "だけで書", "文で書", "絵文字"]
        for request in requests {
            let text = ([request.system, request.prompt] + request.turns.map(\.text)).joined(separator: "\n")
            for word in banned {
                XCTAssertFalse(text.contains(word), "「\(word)」: \(text)")
            }
        }
    }

    func testAISuggestionsStreamThreeIdeas() async throws {
        let replies = [
            "体験: 好きな音楽を聴く\nひとこと: 心が少し緩むかもしれない\nはじめ方: 一曲だけ選ぶ\n時間: 15分\n種類: こころ",
            "体験: 短文で日記を書く\nひとこと: 言葉を選ぶ楽しさがあるかも\nはじめ方: 三行だけ書く\n時間: 15分\n種類: つくる",
            "体験: 伸びをする\nひとこと: 体の力が抜けるかも\nはじめ方: 椅子に座る\n時間: 5分\n種類: からだ",
        ]
        let counter = Counter()
        let engine = ScriptedEngine { _ in replies[counter.next() % replies.count] }
        let brain = CompanionBrain(engine: engine)
        let result = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 1))
        XCTAssertEqual(result.values.map(\.title), ["好きな音楽を聴く", "短文で日記を書く", "伸びをする"])
        XCTAssertTrue(result.values.allSatisfy(\.isFromAI))
        XCTAssertGreaterThan(result.progress, 0, "生成中の文も届く")
        XCTAssertTrue(result.notices.isEmpty)
    }

    func testUnformattedAIOutputIsRetriedThenUsedAsWritten() async throws {
        let counter = Counter()
        // 見出しのない文:1回目は作り直してもらい、2回目はそのままカードにする(体験帳で置きかえない)
        let engine = ScriptedEngine { _ in
            let n = counter.next()
            return "思いつき\(n)\n夜の部屋で、好きなことを好きなだけやってみてください。"
        }
        let brain = CompanionBrain(engine: engine)
        let result = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 3))
        XCTAssertEqual(result.values.count, 3)
        XCTAssertTrue(result.values.allSatisfy(\.isFromAI), "AIの書いたことを使う")
        XCTAssertEqual(result.values.map(\.title), ["思いつき1", "思いつき3", "思いつき5"])
        XCTAssertEqual(counter.value, 6, "1つにつき2回まで試す")
        XCTAssertTrue(result.notices.isEmpty)
    }

    /// 中身でははじかない:夜の家でも出かける提案、お金を使う提案、食べ物の提案を、そのまま使う
    func testAnyIdeaIsKeptAsTheAIWroteIt() async throws {
        let replies = [
            "体験: 街角のカフェで英語を練習\nひとこと: 夜のカフェは昼とちがう顔をしています\nはじめ方: 近くのカフェを調べる\n時間: 1時間\n種類: 学ぶ",
            "体験: 新しい服を買いに行く\nひとこと: 気分が変わります\nはじめ方: 店を探す\n時間: 1時間\n種類: そと",
            "体験: 夜食に好きなものを作る\nひとこと: 夜中の台所は特別です\nはじめ方: 冷蔵庫を開ける\n時間: 30分\n種類: つくる",
        ]
        let counter = Counter()
        let brain = CompanionBrain(engine: ScriptedEngine { _ in replies[counter.next() % replies.count] })
        let result = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 8))
        XCTAssertEqual(result.values.map(\.title), ["街角のカフェで英語を練習", "新しい服を買いに行く", "夜食に好きなものを作る"])
        XCTAssertEqual(counter.value, 3, "作り直さない")
        XCTAssertEqual(result.values.first?.duration, .hour, "使える時間(15分)より長くても、AIの書いたとおり")
    }

    func testSmallModelsGetNoHintWords() async throws {
        let reply = "体験: 好きな音楽を聴く\nひとこと: 心が緩むかも\nはじめ方: 1曲選ぶ\n時間: 5分\n種類: こころ"
        let recorder = Recorder()
        let engine = ScriptedEngine { request in recorder.add(request); return reply }
        // 大きいモデル:1回目にきっかけの言葉を添える
        _ = try await collect(CompanionBrain(engine: engine).suggestions(context: nightAtHome, count: 1, avoid: [], seed: 2))
        XCTAssertTrue(recorder.all.first?.prompt.contains("思いつきのきっかけ") == true)
        XCTAssertEqual(recorder.all.first?.temperature ?? 0, 0.85, accuracy: 0.001)
        // 小さいモデル:言葉を添えず、温度も低め
        recorder.reset()
        let small = GenerationTuning(contextItems: 3, chatTurns: 3, useHints: false, suggestionTemperature: 0.7)
        _ = try await collect(CompanionBrain(engine: engine, tuning: small).suggestions(context: nightAtHome, count: 1, avoid: [], seed: 2))
        XCTAssertFalse(recorder.all.contains { $0.prompt.contains("思いつきのきっかけ") })
        XCTAssertEqual(recorder.all.first?.temperature ?? 0, 0.7, accuracy: 0.001)
    }

    /// 小さいモデルも、大きいモデルと同じように自分で考える(体験帳に置きかえない)
    func testSmallModelsThinkFreelyToo() async throws {
        let recorder = Recorder()
        let engine = ScriptedEngine { request in
            recorder.add(request)
            return "体験: 星の名前を1つ覚える\nひとこと: 夜空の見え方が変わります\nはじめ方: 窓から空を見る\n時間: 5分\n種類: 学ぶ"
        }
        let small = GenerationTuning(contextItems: 4, chatTurns: 6, useHints: false, suggestionTemperature: 0.7)
        let brain = CompanionBrain(engine: engine, tuning: small)
        let one = try await collect(brain.suggestions(context: nightAtHome, count: 1, avoid: [], seed: 1))
        XCTAssertEqual(one.values.first?.title, "星の名前を1つ覚える")
        XCTAssertEqual(one.values.first?.origin, .ai("見本のAI"))
        XCTAssertTrue(recorder.all.allSatisfy { $0.prompt.contains("に近い体験を1つ") })
        let reframes = try await collect(brain.reframes(commit: "英単語20個", context: nightAtHome, count: 1, avoid: []))
        XCTAssertEqual(reframes.values.first?.isFromAI, true)
        let someday = try await collect(brain.someday(context: nightAtHome, theme: "旅", count: 1, avoid: [], seed: 4))
        XCTAssertEqual(someday.values.first?.isFromAI, true)
        XCTAssertTrue(recorder.all.contains { $0.prompt.contains("いま気になっていること: 旅") })
    }

    /// 体験帳の体験を出しつくしても、提案は3つそろう(小さいモデルは体験帳が土台なので大事)
    func testLibraryNeverRunsDryAfterManyRounds() async throws {
        let brain = CompanionBrain(engine: nil)
        var shown: [String] = []
        for round in 0..<12 {
            let r = try await collect(brain.suggestions(context: nightAtHome, avoid: Array(shown.suffix(24)), seed: UInt64(round)))
            XCTAssertEqual(r.values.count, 3, "\(round) 回目")
            XCTAssertEqual(Set(r.values.map(\.title)).count, 3, "同じ回の中では重ならない")
            shown += r.values.map(\.title)
        }
    }

    func testInsightFromExperiences() async throws {
        let memos = [
            ExperienceMemo(title: "夕焼けを見に屋上へ", category: .outside, feeling: .calm, note: "空がオレンジから紫に"),
            ExperienceMemo(title: "静かな音楽と深呼吸", category: .mind, feeling: .calm, note: ""),
            ExperienceMemo(title: "お茶をいれる", category: .mind, feeling: .discovery, note: "香りがよかった"),
        ]
        let unexplored: [ExperienceCategory] = [.people, .first]
        // 体験帳(AIなし)
        let rules = try await collect(CompanionBrain(engine: nil).insight(experiences: memos, notes: [], unexplored: unexplored))
        let text = try XCTUnwrap(rules.values.first?.text)
        XCTAssertEqual(rules.values.first?.fromAI, false)
        XCTAssertTrue(text.contains("「こころ」の体験がいちばん多い"), text)
        XCTAssertTrue(text.contains("「おだやか」"), text)
        XCTAssertTrue(text.contains("「ひと」"), text)
        // AI
        let recorder = Recorder()
        let reply = "<think></think>静かな時間を味わう体験が多く、香りや空の色にふれると、おだやかになれるようですね。次は「ひと」の体験として、昔の友だちに一言送ってみるのはどうでしょう。"
        let engine = ScriptedEngine { request in recorder.add(request); return reply }
        let ai = try await collect(CompanionBrain(engine: engine).insight(experiences: memos, notes: ["散歩が好き"], unexplored: unexplored))
        XCTAssertEqual(ai.values.first?.text.hasPrefix("静かな時間を味わう体験が多く"), true)
        XCTAssertEqual(ai.values.first?.fromAI, true)
        let prompt = try XCTUnwrap(recorder.all.first?.prompt)
        XCTAssertTrue(prompt.contains("- 夕焼けを見に屋上へ(そと・おだやか):空がオレンジから紫に"), prompt)
        XCTAssertTrue(prompt.contains("まだやっていない種類: ひと、はじめて"))
        XCTAssertTrue(prompt.contains("この人について: 散歩が好き。"))
        // 英語で返しても、そのまま使う
        let english = try await collect(CompanionBrain(engine: ScriptedEngine { _ in "You seem calm." })
            .insight(experiences: memos, notes: [], unexplored: unexplored))
        XCTAssertEqual(english.values.first?.text, "You seem calm.")
        XCTAssertEqual(english.values.first?.fromAI, true)
        // 何も返さなければ、記録から書く
        let blank = try await collect(CompanionBrain(engine: ScriptedEngine { _ in "<think></think>" })
            .insight(experiences: memos, notes: [], unexplored: unexplored))
        XCTAssertEqual(blank.values.first?.text, text)
        XCTAssertEqual(blank.values.first?.fromAI, false)
        // 記録がなければ、AIに頼まない
        let empty = Recorder()
        let none = try await collect(CompanionBrain(engine: ScriptedEngine { r in empty.add(r); return "x" })
            .insight(experiences: [], notes: [], unexplored: unexplored))
        XCTAssertTrue(none.values.first?.text.contains("まだ体験の記録がありません") == true)
        XCTAssertTrue(empty.all.isEmpty)
    }

    func testDuplicateAIIdeasAreNotRepeated() async throws {
        let engine = ScriptedEngine { _ in "体験: 好きな音楽を聴く\nひとこと: 心が緩むかも\nはじめ方: 1曲選ぶ\n時間: 5分\n種類: こころ" }
        let brain = CompanionBrain(engine: engine)
        let result = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 5))
        XCTAssertEqual(result.values.count, 3)
        XCTAssertEqual(result.values.filter(\.isFromAI).count, 1)
        XCTAssertEqual(Set(result.values.map(\.title)).count, 3)
    }

    func testEngineErrorFallsBackWithNotice() async throws {
        struct Failing: LanguageEngine {
            let info = EngineInfo(kind: .mlx, id: "x", name: "x")
            func generate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> {
                AsyncThrowingStream { $0.finish(throwing: AIError.loadFailed("メモリ")) }
            }
        }
        let brain = CompanionBrain(engine: Failing())
        let result = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 9))
        XCTAssertEqual(result.values.count, 3)
        XCTAssertEqual(result.notices.count, 1, "知らせは1回だけ")
        let reflection = try await collect(brain.reflection(title: "散歩", note: "風が気持ちよかった", feeling: .calm, category: .outside))
        XCTAssertEqual(reflection.values.count, 1)
        XCTAssertFalse(reflection.values[0].fromAI)
    }

    func testRulesBrainAnswersEverythingButChat() async throws {
        let brain = CompanionBrain(engine: nil)
        XCTAssertEqual(brain.info, .rules)
        let s = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 11))
        XCTAssertEqual(s.values.count, 3)
        XCTAssertEqual(Set(s.values.map(\.category)).count, 3)
        let r = try await collect(brain.reflection(title: "お茶をいれる", note: "香りがよかった", feeling: .calm, category: .mind))
        XCTAssertTrue(r.values[0].reply.contains("お茶をいれる"))
        XCTAssertNotNil(r.values[0].question)
        let letter = try await collect(brain.letter(experiences: [("お茶", .mind), ("散歩", .outside)], achievedDays: 5,
                                                    plannedDays: 7, notes: [], context: nightAtHome, seed: 2))
        XCTAssertTrue(letter.values[0].contains("2つの体験"))
        let reframes = try await collect(brain.reframes(commit: "英単語20個", context: nightAtHome, avoid: []))
        XCTAssertEqual(reframes.values.count, 2)
        XCTAssertEqual(reframes.values[0].title, "覚えた言葉で今日を1文にする")
        let someday = try await collect(brain.someday(context: nightAtHome, theme: nil, avoid: [], seed: 4))
        XCTAssertEqual(someday.values.count, 3)
        do {
            _ = try await collect(brain.chat(context: nightAtHome, history: [], message: "こんにちは"))
            XCTFail("体験帳では話せない")
        } catch let error as AIError {
            guard case .unavailable = error else { return XCTFail("\(error)") }
        }
    }

    func testAIReflectionAndChat() async throws {
        let engine = ScriptedEngine { request in
            if request.prompt.contains("返事:") {
                return "返事: 風が気持ちよかったんですね。\n問い: どの道が好きでしたか?\nメモ: 外を歩くのが好き"
            }
            return "<think>\n\n</think>\n\nこんばんは。今日はどんな一日でしたか?"
        }
        let brain = CompanionBrain(engine: engine)
        let r = try await collect(brain.reflection(title: "散歩", note: "風が気持ちよかった", feeling: .calm, category: .outside))
        XCTAssertEqual(r.values.first?.reply, "風が気持ちよかったんですね。")
        XCTAssertEqual(r.values.first?.noteCandidate, "外を歩くのが好き")
        let c = try await collect(brain.chat(context: nightAtHome, history: [ChatTurn(.user, "やあ"), ChatTurn(.assistant, "やあ")],
                                             message: "こんばんは"))
        XCTAssertEqual(c.values.first, "こんばんは。今日はどんな一日でしたか?")
    }

    /// 会話で同じ行をくり返しはじめたら、生成を止め、くり返す前までを返事にする
    func testChatStopsWhenTheModelLoops() async throws {
        let loop = "今夜のプランです。\n" + String(repeating: "21時:夕焼けを見に屋上へ行く。\n22時:夜の散歩をする時間。\n", count: 20)
        let brain = CompanionBrain(engine: ScriptedEngine { _ in loop })
        let reply = try await collect(brain.chat(context: nightAtHome, history: [], message: "今夜なにしよう"))
        XCTAssertEqual(reply.values.first, "今夜のプランです。\n21時:夕焼けを見に屋上へ行く。\n22時:夜の散歩をする時間。")
    }

    func testChatHistoryIsTrimmedForSmallModels() {
        var tuning = GenerationTuning()
        tuning.chatTurns = 2
        let history = (0..<10).map { ChatTurn($0 % 2 == 0 ? .user : .assistant, "\($0)") }
        let req = PromptBook.chat(context: nightAtHome, history: history, message: "次", tuning: tuning)
        XCTAssertEqual(req.history.map(\.text), ["6", "7", "8", "9"])
        XCTAssertTrue(req.examples.isEmpty, "会話には手本を入れない(1往復目の会話を手本と取りちがえないため)")
        XCTAssertTrue(req.system.contains("この人について知っていること: 英語の勉強をしている。散歩が好き。"))
        XCTAssertTrue(req.system.contains("あなたは相棒として返事をします"), "だれとだれの会話かを書く")
        XCTAssertGreaterThanOrEqual(req.maxTokens, 600, "返事の長さをしばらない")
    }
}

/// AIへの頼みを記録する(テスト用)
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [GenerationRequest] = []

    func add(_ request: GenerationRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        requests.removeAll()
    }

    var all: [GenerationRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
}

/// スレッドをまたいで数える(テスト用)
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        let c = count
        count += 1
        return c
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
