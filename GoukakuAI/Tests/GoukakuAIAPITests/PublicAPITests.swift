import XCTest
import GoukakuAI   // @testable なし:アプリから見える形(public)で使えるかを確かめる

/// 本体アプリが使う GoukakuAI の部品が、外から(public で)使えることを確かめる
final class PublicAPITests: XCTestCase {
    func testAppFacingSurfaceCompiles() async throws {
        let spec = ModelSpec(id: "m", name: "M", summary: "s", family: "qwen3_5", repo: "a/b", revision: "main",
                             files: ["config.json"], stripPrefixes: ["vision_tower."], downloadBytes: 2, installedBytes: 1,
                             runtimeBytes: 3, recommendedRAMGB: 6, japanese: 3, speed: 3, speedNote: "", license: "", licenseURL: "")
        let catalog = ModelCatalog(models: [spec])
        XCTAssertEqual(catalog.spec(id: "m")?.url(for: "config.json")?.absoluteString, "https://huggingface.co/a/b/resolve/main/config.json")
        XCTAssertFalse(spec.keepsTensor(named: "vision_tower.x"))
        let manifest = ModelManifest(id: "m", name: "M", family: "qwen3_5", source: .downloaded, installedAt: Date(), bytes: 1)
        let decoded = try ModelManifest.decode(manifest.encoded())
        XCTAssertEqual(decoded.id, "m")
        XCTAssertEqual(ModelManifest.fileName, "goukaku-model.json")
        let installed = InstalledModel(manifest: decoded, directory: URL(fileURLWithPath: "/tmp/m"), spec: spec)
        XCTAssertEqual(installed.runtimeBytes, 3)
        XCTAssertEqual(ModelConfigProbe.family(fromConfig: Data(#"{"model_type":"lfm2"}"#.utf8)), "lfm2")

        let profile = DeviceProfile(physicalMemory: 8 << 30, availableMemory: nil, osMajor: 26, osMinor: 0, model: "x",
                                    isSimulator: false, thermal: .nominal, lowPowerMode: false, appleIntelligence: .available)
        var decision = EngineRouter.decide(profile: profile, installed: [installed], preference: EnginePreference(rawValue: "auto"))
        decision.skipped.append(RouteDecision.Skipped(name: "x", reason: "y"))
        let manual = RouteDecision(choice: .rules, tuning: GenerationTuning(), reasons: [], skipped: [])
        XCTAssertEqual(manual.choice, .rules)
        _ = (decision.reasons, decision.tuning.contextItems, profile.thermal.label, profile.appleIntelligence.label)

        let engine = ScriptedEngine(info: EngineInfo(kind: .mlx, id: "s", name: "S")) { request in
            _ = (request.system, request.history.map(\.text), request.prompt, request.maxTokens, request.temperature)
            return "体験: 空を見る\nひとこと: 風を感じるかも\nはじめ方: 外に出る\n時間: 5分\n種類: そと"
        }
        let brain = CompanionBrain(engine: engine, tuning: GenerationTuning())
        let context = CompanionContext(now: Date(), budget: TimeBudget(rawValue: 15) ?? .fifteen, place: .anywhere, mood: .normal,
                                       notes: ["散歩が好き"], recentExperiences: [], liked: [], disliked: [], commits: [],
                                       categoryAffinity: [.outside: 1])
        var drafts: [ExperienceDraft] = []
        for try await event in brain.suggestions(context: context, count: 1, avoid: [], seed: 1) {
            switch event {
            case .progress(let text): _ = text
            case .value(let d): drafts.append(d)
            case .notice(let n): _ = n
            }
        }
        XCTAssertEqual(drafts.first?.isFromAI, true)
        let own = ExperienceDraft(title: "t", line: "", firstStep: "", duration: .nearest(minutes: 12), category: .first, origin: .user)
        XCTAssertEqual(own.duration, .fifteen)
        // 小さいモデル向け:体験帳の体験にひとことを添える
        let tailoredOrigin = ExperienceDraft.Origin.tailored("S", "id")
        let tailored = ExperienceDraft(title: "t", line: "l", firstStep: "", duration: .five, category: .mind, origin: tailoredOrigin)
        XCTAssertTrue(tailored.isTailored && tailored.isFromAI)
        var small = GenerationTuning(freeSuggestions: false)
        small.apply(for: installed)
        _ = (small.freeSuggestions, small.useHints, small.suggestionTemperature, spec.freeSuggestions)
        _ = ExperienceParser.tailoredLine(from: "ひとこと: 静かな夜に、小さな発見があるかも", title: "t")
        _ = PromptBook.tailor(tailored, context: CompanionContext(), tuning: small)
        _ = ContextFit.fits(tailored, context: CompanionContext())
        _ = (ExperienceCategory(rawValue: "outside")?.symbol, DurationBucket(rawValue: 5)?.label, Feeling.calm.symbol, Place.home.label, Mood.tired.label)
        _ = ChatTurn(.user, "やあ").role == ChatTurn.Role.user
        _ = EngineInfo.rules.name

        let growth = GrowthSnapshot.make(experienceCategories: [.mind], notes: 1, liked: 0, disliked: 0, since: Date())
        _ = (growth.level.label, growth.level.next?.label, growth.pointsToNext, growth.progressToNext, growth.unexplored, growth.counts[.mind])
        XCTAssertTrue(CompanionMemory.isNew("夕焼けが好き", existing: []))
        _ = CompanionMemory.split(selfIntroduction: "a、b")
        _ = CompanionMemory.capacity
        _ = AIError.unavailable("x").errorDescription
    }
}
