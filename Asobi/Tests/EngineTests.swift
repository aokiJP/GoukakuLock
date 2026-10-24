import XCTest
@testable import AsobiCore

final class EngineTests: XCTestCase {
    let json = #"{"title":"音の標本","premise":"音を架空の生き物に変えよう","start":"a","variables":{"発見":0},"tags":["創作"],"nodes":[{"id":"a","text":"名前をつける","seconds":3,"timeout":"end","ending":false,"actions":[{"id":"name","label":"記録","input":true,"effects":[{"key":"発見","delta":2}],"next":"b","condition":{"key":"発見","atLeast":2},"alternate":"end"}]},{"id":"b","text":"標本を開く","ending":false,"actions":[{"id":"open","label":"開く","input":false,"effects":[],"next":"end","random":["end"]}]},{"id":"end","text":"発見が残った","ending":true,"actions":[]}]}"#
    func sample() throws -> Experience { try Validator.decode(json) }
    func testStartToFinishAndInputRecorded() throws {
        var s = try Session(sample())
        XCTAssertEqual(s.nodeID, "a")
        try s.apply("name", note: "カタカタ鳥")
        XCTAssertEqual(s.nodeID, "b"); XCTAssertEqual(s.values["発見"], 2)
        try s.apply("open"); XCTAssertTrue(s.finished)
        XCTAssertEqual(s.moves.first?.note, "カタカタ鳥")
        XCTAssertThrowsError(try s.apply("open"))
    }
    func testTimeout() throws {
        var s = try Session(sample()); s.tick(); s.tick()
        XCTAssertEqual(s.remaining, 1); s.tick(); XCTAssertTrue(s.finished)
        XCTAssertEqual(s.moves.last?.action, "時間切れ")
    }
    func testMissingInputDoesNotMutate() throws {
        var s = try Session(sample()); let old = s
        XCTAssertThrowsError(try s.apply("name")); XCTAssertEqual(s, old)
    }
    func testInvalidActionDoesNotMutate() throws {
        var s = try Session(sample()); let old = s
        XCTAssertThrowsError(try s.apply("nope")); XCTAssertEqual(s, old)
    }
    func testSaveResumeThenFinish() throws {
        var s = try Session(sample()); try s.apply("name", note: "雲")
        var restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        try restored.validateSaved(); XCTAssertEqual(s, restored)
        try restored.apply("open"); XCTAssertTrue(restored.finished)
    }
    func testDanglingTarget() throws {
        var e = try sample(); e.nodes[0].actions[0].next = "missing"
        XCTAssertThrowsError(try Validator.validate(e))
    }
    func testNoEndingRejected() throws {
        var e = try sample(); e.nodes[2].ending = false
        e.nodes[2].actions = e.nodes[1].actions
        XCTAssertThrowsError(try Validator.validate(e))
    }
    func testUnknownVariable() throws {
        var e = try sample(); e.variables = [:]
        XCTAssertThrowsError(try Validator.validate(e))
    }
    func testIntegerMinRejectedWithoutTrap() throws {
        var e = try sample(); e.variables["発見"] = Int.min
        XCTAssertThrowsError(try Validator.validate(e))
    }
    func testDuplicateIDs() throws {
        var e = try sample(); e.nodes[1].id = "a"
        XCTAssertThrowsError(try Validator.validate(e))
    }
    func testOversizeAndCodeRejected() {
        XCTAssertThrowsError(try Validator.decode(String(repeating: "a", count: 49_000)))
        XCTAssertThrowsError(try Validator.decode("print(123)"))
    }
    func testInvalidTimer() throws {
        var e = try sample(); e.nodes[0].seconds = -1
        XCTAssertThrowsError(try Validator.validate(e))
    }
    func testConditionFalse() throws {
        var e = try sample(); e.nodes[0].actions[0].condition?.atLeast = 3
        var s = try Session(e); try s.apply("name", note: "風")
        XCTAssertTrue(s.finished)
    }
    func testBoundedLoops() throws {
        var e = try sample(); e.nodes[1].actions[0].random = ["b", "end"]
        var s = try Session(e); try s.apply("name", note: "音")
        for _ in 0..<99 { try s.apply("open", randomIndex: 0) }
        XCTAssertTrue(s.finished); XCTAssertEqual(s.moves.count, 100)
    }
    func testCorruptSavedNode() throws {
        var s = try Session(sample()); s.nodeID = "missing"
        XCTAssertThrowsError(try s.validateSaved())
    }
}
