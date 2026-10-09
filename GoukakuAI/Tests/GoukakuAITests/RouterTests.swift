import XCTest
@testable import GoukakuAI

final class RouterTests: XCTestCase {
    let GB: UInt64 = 1_073_741_824

    func spec(_ id: String, runtimeGB: Double, japanese: Int) -> ModelSpec {
        ModelSpec(id: id, name: id, summary: "", family: "qwen3_5", repo: "r/\(id)", revision: "main",
                  files: ["config.json"], stripPrefixes: [], downloadBytes: 1, installedBytes: 1,
                  runtimeBytes: Int64(runtimeGB * 1_073_741_824), recommendedRAMGB: 8, japanese: japanese,
                  speed: 3, speedNote: "", license: "", licenseURL: "")
    }

    func installed(_ s: ModelSpec, source: ModelManifest.Source = .bundled) -> InstalledModel {
        InstalledModel(manifest: ModelManifest(id: s.id, name: s.name, family: s.family, source: source, bytes: 1),
                       directory: URL(fileURLWithPath: "/tmp/\(s.id)"), spec: s)
    }

    func profile(ramGB: Double = 8, availableGB: Double? = 5, thermal: ThermalLevel = .nominal, lowPower: Bool = false,
                 apple: AppleIntelligenceState = .unavailable, simulator: Bool = false) -> DeviceProfile {
        DeviceProfile(physicalMemory: UInt64(ramGB * Double(GB)), availableMemory: availableGB.map { UInt64($0 * Double(GB)) },
                      osMajor: 26, osMinor: 0, model: "iPhone17,1", isSimulator: simulator, thermal: thermal,
                      lowPowerMode: lowPower, appleIntelligence: apple)
    }

    func testPicksMostNaturalJapaneseThatFits() {
        let gemma = installed(spec("gemma", runtimeGB: 3.2, japanese: 5))
        let qwen2 = installed(spec("qwen2b", runtimeGB: 1.5, japanese: 2))
        let d = EngineRouter.decide(profile: profile(availableGB: 5), installed: [qwen2, gemma], preference: .automatic)
        XCTAssertEqual(d.choice, .mlx(gemma))
        XCTAssertEqual(d.tuning.contextItems, 6)
    }

    func testSkipsModelsThatDoNotFitInMemory() {
        let gemma = installed(spec("gemma", runtimeGB: 3.2, japanese: 5))
        let lfm = installed(spec("lfm", runtimeGB: 1.0, japanese: 3))
        let d = EngineRouter.decide(profile: profile(ramGB: 6, availableGB: 2.6), installed: [gemma, lfm], preference: .automatic)
        XCTAssertEqual(d.choice, .mlx(lfm))
        XCTAssertEqual(d.skipped.map(\.name), ["gemma"])
        XCTAssertTrue(d.skipped[0].reason.contains("メモリが足りない"))
        XCTAssertEqual(d.tuning.contextItems, 4, "小さいモデルにはプロンプトを短く")
        XCTAssertFalse(d.tuning.useHints, "小さいモデルにはきっかけの言葉を添えない")
        XCTAssertFalse(d.reasons.contains { $0.contains("体験帳") }, "小さいモデルも自分で考える")
        XCTAssertEqual(d.tuning.suggestionTemperature, 0.7, accuracy: 0.001)
        let big = EngineRouter.decide(profile: profile(ramGB: 8, availableGB: 6), installed: [gemma, lfm], preference: .automatic)
        XCTAssertEqual(big.choice, .mlx(gemma))
        XCTAssertTrue(big.tuning.useHints)
    }

    func testFallsBackToAppleThenRules() {
        let big = installed(spec("big", runtimeGB: 9, japanese: 5))
        let withApple = EngineRouter.decide(profile: profile(apple: .available), installed: [big], preference: .automatic)
        XCTAssertEqual(withApple.choice, .apple)
        let none = EngineRouter.decide(profile: profile(apple: .notEnabled), installed: [big], preference: .automatic)
        XCTAssertEqual(none.choice, .rules)
        XCTAssertTrue(none.reasons[0].contains("体験帳"))
        let empty = EngineRouter.decide(profile: profile(), installed: [], preference: .automatic)
        XCTAssertTrue(empty.reasons[0].contains("モデルが入っていない"))
    }

    func testPreferenceIsHonoredWhenPossible() {
        let gemma = installed(spec("gemma", runtimeGB: 3.2, japanese: 5))
        let qwen2 = installed(spec("qwen2b", runtimeGB: 1.5, japanese: 2))
        let chosen = EngineRouter.decide(profile: profile(apple: .available), installed: [gemma, qwen2], preference: .model("qwen2b"))
        XCTAssertEqual(chosen.choice, .mlx(qwen2))
        let apple = EngineRouter.decide(profile: profile(apple: .available), installed: [gemma], preference: .apple)
        XCTAssertEqual(apple.choice, .apple)
        let appleMissing = EngineRouter.decide(profile: profile(apple: .deviceNotEligible), installed: [gemma], preference: .apple)
        XCTAssertEqual(appleMissing.choice, .mlx(gemma))
        XCTAssertTrue(appleMissing.reasons.contains { $0.contains("Apple Intelligence は今は使えない") })
        let off = EngineRouter.decide(profile: profile(apple: .available), installed: [gemma], preference: .off)
        XCTAssertEqual(off.choice, .rules)
    }

    func testHeatAndLowPowerAdapt() {
        let gemma = installed(spec("gemma", runtimeGB: 3.2, japanese: 5))
        let lfm = installed(spec("lfm", runtimeGB: 1.0, japanese: 3))
        let hot = EngineRouter.decide(profile: profile(thermal: .serious), installed: [gemma, lfm], preference: .automatic)
        XCTAssertEqual(hot.choice, .mlx(lfm), "熱いときは軽いモデル")
        XCTAssertEqual(hot.tuning.lengthScale, 0.7, accuracy: 0.001)
        let critical = EngineRouter.decide(profile: profile(thermal: .critical), installed: [gemma], preference: .automatic)
        XCTAssertEqual(critical.choice, .rules)
        let lowPower = EngineRouter.decide(profile: profile(lowPower: true, apple: .available), installed: [gemma], preference: .automatic)
        XCTAssertEqual(lowPower.choice, .apple, "低電力モードでは電池にやさしい方")
        XCTAssertEqual(lowPower.tuning.tokens(100), 80)
    }

    func testOldGPUSkipsMLX() {
        let lfm = installed(spec("lfm", runtimeGB: 1.0, japanese: 3))
        var old = profile(ramGB: 4, availableGB: 2.5)
        old.supportsMLX = false
        let d = EngineRouter.decide(profile: old, installed: [lfm], preference: .automatic)
        XCTAssertEqual(d.choice, .rules)
        XCTAssertTrue(d.skipped.first?.reason.contains("GPU") == true)
    }

    func testSimulatorNeverRunsMLX() {
        let lfm = installed(spec("lfm", runtimeGB: 1.0, japanese: 3))
        let d = EngineRouter.decide(profile: profile(simulator: true), installed: [lfm], preference: .automatic)
        XCTAssertEqual(d.choice, .rules)
        XCTAssertEqual(d.skipped.first?.reason, "シミュレータでは MLX が動かない")
    }

    func testUnknownMemoryUsesHalfOfRAM() {
        let mid = installed(spec("mid", runtimeGB: 3.2, japanese: 4))
        let ok = EngineRouter.decide(profile: profile(ramGB: 8, availableGB: nil), installed: [mid], preference: .automatic)
        XCTAssertEqual(ok.choice, .mlx(mid))
        let small = EngineRouter.decide(profile: profile(ramGB: 6, availableGB: nil), installed: [mid], preference: .automatic)
        XCTAssertEqual(small.choice, .rules)
    }

    func testPreferenceRawValueRoundTrip() {
        for p in [EnginePreference.automatic, .apple, .off, .model("gemma4-e2b")] {
            XCTAssertEqual(EnginePreference(rawValue: p.rawValue), p)
        }
        XCTAssertEqual(EnginePreference(rawValue: "???"), .automatic)
    }

    func testCatalogFileDecodesAndIsConsistent() throws {
        // リポジトリの AI/models.json(CI と同じもの)を読む
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AI/models.json")
        let catalog = try ModelCatalog.decode(Data(contentsOf: url))
        XCTAssertFalse(catalog.models.isEmpty)
        XCTAssertEqual(Set(catalog.models.map(\.id)).count, catalog.models.count, "id が重複している")
        for m in catalog.models {
            XCTAssertTrue(ModelConfigProbe.isSupported(family: m.family), "\(m.id) の family \(m.family) を MLX が読めない")
            XCTAssertTrue(m.files.contains("config.json"), m.id)
            XCTAssertTrue(m.files.contains("tokenizer.json"), m.id)
            XCTAssertTrue(m.files.contains { $0.hasSuffix(".safetensors") }, m.id)
            XCTAssertNotNil(m.url(for: "config.json"), m.id)
            XCTAssertGreaterThan(m.runtimeBytes, m.installedBytes, "\(m.id):動かすメモリは重みより大きい")
            XCTAssertLessThanOrEqual(m.installedBytes, m.downloadBytes, m.id)
            XCTAssertEqual(m.revision.count, 40, "\(m.id):リビジョンはコミットで固定する")
            XCTAssertTrue((1...5).contains(m.japanese) && (1...5).contains(m.speed), m.id)
        }
    }

    /// 大きさで変えるのは、プロンプトに入れる量・会話を覚えている長さ・きっかけの言葉と温度だけ
    func testTuningFollowsSizeOnly() {
        var tuning = GenerationTuning()
        tuning.apply(for: installed(spec("lfm", runtimeGB: 1.0, japanese: 3)))
        XCTAssertEqual(tuning.contextItems, 4)
        XCTAssertEqual(tuning.chatTurns, 6)
        XCTAssertFalse(tuning.useHints)
        tuning.apply(for: installed(spec("qwen2b", runtimeGB: 1.5, japanese: 2)))
        XCTAssertEqual(tuning.chatTurns, 8)
        tuning.apply(for: installed(spec("gemma", runtimeGB: 3.2, japanese: 5)))
        XCTAssertEqual(tuning.contextItems, 6)
        XCTAssertEqual(tuning.chatTurns, 10)
        XCTAssertTrue(tuning.useHints)
        XCTAssertEqual(tuning.suggestionTemperature, 0.85, accuracy: 0.001)
        XCTAssertEqual(tuning.chatTemperature, 0.8, accuracy: 0.001)
        // 会話の温度:目録のおすすめが先、なければ大きさで(小さいほど低く)
        var lfm = spec("lfm", runtimeGB: 1.0, japanese: 3)
        lfm.chatTemperature = 0.3
        lfm.chatTopP = 0.9
        tuning.apply(for: installed(lfm))
        XCTAssertEqual(tuning.chatTemperature, 0.3, accuracy: 0.001)
        XCTAssertEqual(tuning.chatTopP, 0.9, accuracy: 0.001)
        tuning.apply(for: installed(spec("imported-small", runtimeGB: 1.0, japanese: 3)))
        XCTAssertEqual(tuning.chatTemperature, 0.4, accuracy: 0.001)
        let chat = PromptBook.chat(context: CompanionContext(), history: [], message: "やあ", tuning: tuning)
        XCTAssertEqual(chat.temperature, 0.4, accuracy: 0.001)
        XCTAssertEqual(chat.topP, 0.8, accuracy: 0.001)
    }
}
