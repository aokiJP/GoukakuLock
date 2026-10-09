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
        XCTAssertEqual(d.tuning.contextItems, 3, "小さいモデルにはプロンプトを短く")
        XCTAssertFalse(d.tuning.useHints, "小さいモデルにはきっかけの言葉を添えない")
        XCTAssertFalse(d.tuning.freeSuggestions, "小さいモデルは体験帳にひとことを添える")
        XCTAssertTrue(d.reasons.contains { $0.contains("体験帳の確かな体験") }, "提案のしかたも理由に出す")
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
            XCTAssertNotNil(m.freeSuggestions, "\(m.id):提案のしかた(自由か、体験帳にひとことか)を決めておく")
        }
    }

    func testSuggestionStyleFollowsCatalogThenSize() {
        // 目録で決めたもの
        var small = spec("lfm", runtimeGB: 1.0, japanese: 3)
        small.freeSuggestions = false
        var big = spec("gemma", runtimeGB: 3.2, japanese: 5)
        big.freeSuggestions = true
        var tuning = GenerationTuning()
        tuning.apply(for: installed(small))
        XCTAssertFalse(tuning.freeSuggestions)
        tuning.apply(for: installed(big))
        XCTAssertTrue(tuning.freeSuggestions)
        // 大きくても、目録で「ひとこと」にしたものはそれ(Qwen3.5 4B)
        var qwen4 = spec("qwen4b", runtimeGB: 2.75, japanese: 3)
        qwen4.freeSuggestions = false
        tuning.apply(for: installed(qwen4))
        XCTAssertFalse(tuning.freeSuggestions)
        XCTAssertTrue(tuning.useHints, "きっかけの言葉は大きさで決める")
        // 目録にないモデルは大きさで
        tuning.apply(for: installed(spec("unknown-small", runtimeGB: 1.2, japanese: 3)))
        XCTAssertFalse(tuning.freeSuggestions)
        tuning.apply(for: installed(spec("unknown-big", runtimeGB: 3.0, japanese: 3)))
        XCTAssertTrue(tuning.freeSuggestions)
    }
}
