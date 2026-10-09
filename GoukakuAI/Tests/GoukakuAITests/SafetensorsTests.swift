import XCTest
@testable import GoukakuAI

final class SafetensorsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("st-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// テンソル(名前 → 中身のバイト)から safetensors を作る
    func write(_ tensors: [(String, [UInt8])], to url: URL, metadata: [String: String]? = ["format": "mlx"]) throws {
        var header: [String: Any] = [:]
        if let metadata { header["__metadata__"] = metadata }
        var offset = 0
        var body = Data()
        for (name, bytes) in tensors {
            header[name] = ["dtype": "U8", "shape": [bytes.count], "data_offsets": [offset, offset + bytes.count]]
            offset += bytes.count
            body.append(contentsOf: bytes)
        }
        let json = try JSONSerialization.data(withJSONObject: header)
        var data = Data()
        var length = UInt64(json.count).littleEndian
        data.append(Data(bytes: &length, count: 8))
        data.append(json)
        data.append(body)
        try data.write(to: url)
    }

    /// safetensors を読んで、名前 → 中身 にする(テストの答え合わせ用)
    func read(_ url: URL) throws -> [String: [UInt8]] {
        let data = try Data(contentsOf: url)
        let length = data.prefix(8).enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * UInt64($1.offset))) }
        let header = try JSONSerialization.jsonObject(with: data.subdata(in: 8..<(8 + Int(length)))) as! [String: Any]
        let start = 8 + Int(length)
        XCTAssertEqual(start % 8, 0, "ヘッダは8バイト境界")
        var out: [String: [UInt8]] = [:]
        for (name, value) in header where name != "__metadata__" {
            let offsets = (value as! [String: Any])["data_offsets"] as! [Int]
            out[name] = [UInt8](data.subdata(in: (start + offsets[0])..<(start + offsets[1])))
        }
        return out
    }

    func testDropsVisionTensorsAndKeepsBytesIntact() throws {
        let input = dir.appendingPathComponent("model.safetensors")
        try write([
            ("language_model.model.embed_tokens.weight", [1, 2, 3, 4, 5]),
            ("vision_tower.blocks.0.weight", Array(repeating: 9, count: 1000)),
            ("language_model.model.layers.0.weight", [6, 7, 8]),
            ("audio_tower.layers.0.weight", Array(repeating: 7, count: 300)),
            ("language_model.lm_head.weight", [10, 11]),
        ], to: input)
        let output = dir.appendingPathComponent("slim.safetensors")
        let spec = ModelSpec(id: "t", name: "t", summary: "", family: "gemma4", repo: "r", revision: "main", files: [],
                             stripPrefixes: ["vision_tower.", "audio_tower."], downloadBytes: 0, installedBytes: 0,
                             runtimeBytes: 0, recommendedRAMGB: 8, japanese: 3, speed: 3, speedNote: "", license: "", licenseURL: "")
        let result = try SafetensorsSlimmer.slim(input: input, output: output, keep: spec.keepsTensor(named:))
        XCTAssertEqual(result.kept, 3)
        XCTAssertEqual(result.dropped, 2)
        XCTAssertLessThan(result.bytesAfter, result.bytesBefore)
        let tensors = try read(output)
        XCTAssertEqual(tensors["language_model.model.embed_tokens.weight"], [1, 2, 3, 4, 5])
        XCTAssertEqual(tensors["language_model.model.layers.0.weight"], [6, 7, 8])
        XCTAssertEqual(tensors["language_model.lm_head.weight"], [10, 11])
        XCTAssertNil(tensors["vision_tower.blocks.0.weight"])
        let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as! NSNumber
        XCTAssertEqual(size.int64Value, result.bytesAfter)
    }

    func testDirectorySlimmingRewritesIndexAndRemovesEmptyShards() throws {
        try write([("language_model.a", [1, 2]), ("vision_tower.b", [3, 3, 3])], to: dir.appendingPathComponent("model-00001-of-00002.safetensors"))
        try write([("vision_tower.c", [4, 4])], to: dir.appendingPathComponent("model-00002-of-00002.safetensors"))
        let index: [String: Any] = ["metadata": ["total_size": 7],
                                    "weight_map": ["language_model.a": "model-00001-of-00002.safetensors",
                                                   "vision_tower.b": "model-00001-of-00002.safetensors",
                                                   "vision_tower.c": "model-00002-of-00002.safetensors"]]
        try JSONSerialization.data(withJSONObject: index).write(to: dir.appendingPathComponent("model.safetensors.index.json"))
        let result = try SafetensorsSlimmer.slimDirectory(dir) { !$0.hasPrefix("vision_tower.") }
        XCTAssertEqual(result.kept, 1)
        XCTAssertEqual(result.dropped, 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(files, ["model-00001-of-00002.safetensors", "model.safetensors.index.json"])
        let newIndex = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("model.safetensors.index.json"))) as! [String: Any]
        XCTAssertEqual(newIndex["weight_map"] as? [String: String], ["language_model.a": "model-00001-of-00002.safetensors"])
        XCTAssertEqual(try read(dir.appendingPathComponent("model-00001-of-00002.safetensors")), ["language_model.a": [1, 2]])
    }

    func testNothingToDropLeavesFileUntouched() throws {
        let url = dir.appendingPathComponent("model.safetensors")
        try write([("model.a", [1]), ("model.b", [2])], to: url)
        let before = try Data(contentsOf: url)
        let result = try SafetensorsSlimmer.slimDirectory(dir) { _ in true }
        XCTAssertEqual(result.dropped, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testMalformedFileThrows() throws {
        let url = dir.appendingPathComponent("bad.safetensors")
        try Data([1, 2, 3]).write(to: url)
        XCTAssertThrowsError(try SafetensorsSlimmer.tensorNames(at: url))
    }
}
