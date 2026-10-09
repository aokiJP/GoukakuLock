import XCTest
import GoukakuAI
@testable import GoukakuAIMLX

/// 実際のモデルを MLX で読み、相棒の頭(CompanionBrain)を通して日本語の提案とふり返りが返るかを確かめる。
/// CI(macOS)で `TEST_RUNNER_GOUKAKU_MODEL_DIR=<モデルのフォルダ>` を渡したときだけ動く。
/// GPU のない環境では `TEST_RUNNER_GOUKAKU_MLX_CPU=1` で CPU を使う。
final class MLXSmokeTests: XCTestCase {
    var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// 目録のモデル(あれば)
    var spec: ModelSpec? {
        guard let id = environment["GOUKAKU_MODEL_ID"], let catalogPath = environment["GOUKAKU_CATALOG"],
              let data = FileManager.default.contents(atPath: catalogPath) else { return nil }
        return try? ModelCatalog.decode(data).spec(id: id)
    }

    /// アプリがこのモデルを選んだときと同じ調整(小さいモデルはプロンプトを短く・きっかけの言葉なし)
    var tuning: GenerationTuning {
        var tuning = GenerationTuning()
        if let spec {
            let manifest = ModelManifest(id: spec.id, name: spec.name, family: spec.family, source: .bundled,
                                         bytes: spec.installedBytes)
            tuning.apply(for: InstalledModel(manifest: manifest, directory: URL(fileURLWithPath: "/"), spec: spec))
        }
        return tuning
    }

    func engine() throws -> MLXEngine {
        guard let path = environment["GOUKAKU_MODEL_DIR"], !path.isEmpty else {
            throw XCTSkip("GOUKAKU_MODEL_DIR が指定されていないので飛ばす")
        }
        let directory = URL(fileURLWithPath: path)
        let spec = self.spec
        return MLXEngine(directory: directory, id: spec?.id ?? "smoke", name: spec?.name ?? directory.lastPathComponent,
                         extraEOSTokens: spec?.extraEOSTokens ?? [],
                         templateFlags: spec?.templateFlags ?? ["enable_thinking": false],
                         repetitionPenalty: spec?.repetitionPenalty,
                         useCPU: environment["GOUKAKU_MLX_CPU"] == "1")
    }

    func testModelLoadsAndCompanionAnswersInJapanese() async throws {
        let engine = try engine()
        let started = Date()
        try await engine.load()
        print("[smoke] 読み込み \(String(format: "%.1f", Date().timeIntervalSince(started)))秒")

        // 素の生成
        let hello = try await engine.complete(GenerationRequest(system: PromptBook.system, prompt: "ひとことだけ、あいさつしてください。",
                                                                maxTokens: 40, temperature: 0.3))
        print("[smoke] あいさつ: \(OutputCleaner.clean(hello))")
        XCTAssertTrue(TextCheck.hasJapanese(OutputCleaner.clean(hello)), "日本語が返らない:\(hello)")
        if let stats = await engine.lastStats() {
            print("[smoke] 速さ:毎秒 \(String(format: "%.1f", stats.tokensPerSecond)) トークン(プロンプト \(stats.promptTokens))")
        }

        // 相棒の提案(3つ)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let context = CompanionContext(now: cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 21))!,
                                       timeZone: cal.timeZone, budget: .fifteen, place: .home, mood: .tired,
                                       notes: ["英語の勉強をしている", "散歩が好き"], recentExperiences: ["夕焼けを見に屋上へ"])
        let tuning = self.tuning
        print("[smoke] 調整: 文脈 \(tuning.contextItems)・きっかけの言葉 \(tuning.useHints ? "あり" : "なし")・温度 \(tuning.suggestionTemperature)")
        let brain = CompanionBrain(engine: engine, tuning: tuning)
        var ideas: [ExperienceDraft] = []
        for try await event in brain.suggestions(context: context, avoid: [], seed: 1) {
            switch event {
            case .value(let draft):
                ideas.append(draft)
                print("[smoke] 提案(\(draft.isFromAI ? "AI" : "体験帳")): \(draft.title) / \(draft.line) / \(draft.firstStep) / \(draft.duration.label) / \(draft.category.label)")
            case .notice(let notice):
                print("[smoke] 知らせ: \(notice)")
            case .progress:
                break
            }
        }
        XCTAssertEqual(ideas.count, 3)
        // 小さいモデルは、いまの様子に合わない提案をはじかれて体験帳で補うことがある(それも正しい動き)
        if ideas.allSatisfy({ !$0.isFromAI }) { print("[smoke] 注意: AIの提案はすべて体験帳で補った") }

        // ふり返り
        var reflection: ReflectionDraft?
        for try await event in brain.reflection(title: "夕焼けを見に屋上へ", note: "空がオレンジから紫に変わるのを10分見ていた。風が気持ちよかった。",
                                                feeling: .calm, category: .outside) {
            if case .value(let r) = event { reflection = r }
        }
        let r = try XCTUnwrap(reflection)
        print("[smoke] ふり返り(\(r.fromAI ? "AI" : "体験帳")): \(r.reply) / 問い: \(r.question ?? "-") / メモ: \(r.noteCandidate ?? "-")")
        XCTAssertTrue(r.fromAI, "AIのふり返りが使えなかった")

        await engine.unload()
        let loaded = await engine.isLoaded()
        XCTAssertFalse(loaded)
    }
}
