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
        XCTAssertEqual(req.history.count, 2)
        XCTAssertEqual(req.history[0].role, .user)
        XCTAssertTrue(req.history[1].text.hasPrefix("体験: "))
        XCTAssertTrue(req.prompt.contains("「こころ」に近い体験を1つ"))
        XCTAssertTrue(req.prompt.contains("もう出した体験(これとはテーマのちがうものにする): 星を見る"))
        XCTAssertTrue(req.prompt.hasSuffix("体験:\nひとこと:\nはじめ方:\n時間:\n種類:"))
        XCTAssertEqual(req.system, PromptBook.system)
    }

    func testAnglesAvoidOutsideAtNightAtHome() {
        for seed in 0..<50 {
            let angles = AnglePlanner.angles(for: nightAtHome, count: 3, seed: UInt64(seed))
            XCTAssertEqual(angles.count, 3)
            XCTAssertEqual(Set(angles).count, 3)
            XCTAssertFalse(angles.contains(.outside), "夜に家にいる人に外の体験を出さない")
        }
        XCTAssertEqual(AnglePlanner.angles(for: nightAtHome, seed: 7), AnglePlanner.angles(for: nightAtHome, seed: 7))
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

    func testBrokenAIOutputIsRetriedThenFilledFromLibrary() async throws {
        let counter = Counter()
        // 1回目はでたらめ、2回目は買い物(はじく)→ 体験帳で補う
        let engine = ScriptedEngine { _ in
            counter.next() % 2 == 0 ? "わかりません" : "体験: 服を買う\nひとこと: 楽しい\n時間: 15分\n種類: そと"
        }
        let brain = CompanionBrain(engine: engine)
        let result = try await collect(brain.suggestions(context: nightAtHome, avoid: [], seed: 3))
        XCTAssertEqual(result.values.count, 3)
        XCTAssertTrue(result.values.allSatisfy { !$0.isFromAI })
        XCTAssertEqual(counter.value, 6, "1つにつき2回まで試す")
        for v in result.values {
            XCTAssertTrue(TimeBudget.fifteen.allows(v.duration))
            XCTAssertNotEqual(v.category, .outside)
        }
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

    func testChatHistoryIsTrimmedForSmallModels() {
        var tuning = GenerationTuning()
        tuning.chatTurns = 2
        let history = (0..<10).map { ChatTurn($0 % 2 == 0 ? .user : .assistant, "\($0)") }
        let req = PromptBook.chat(context: nightAtHome, history: history, message: "次", tuning: tuning)
        XCTAssertEqual(req.history.map(\.text), ["6", "7", "8", "9"])
        XCTAssertTrue(req.system.contains("この人について知っていること: 英語の勉強をしている。散歩が好き。"))
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
