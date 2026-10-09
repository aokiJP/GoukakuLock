import XCTest
@testable import GoukakuAI

final class LibraryAndGrowthTests: XCTestCase {
    func testLibraryIsCompleteAndSafe() {
        let items = ExperienceLibrary.items
        XCTAssertEqual(items.count, 96)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "id が重複している")
        XCTAssertEqual(Set(items.map(\.title)).count, items.count, "名前が重複している")
        for c in ExperienceCategory.allCases {
            XCTAssertEqual(items.filter { $0.category == c }.count, 12, c.label)
        }
        for item in items + ExperienceLibrary.somedayItems + ExperienceLibrary.genericReframes {
            XCTAssertLessThanOrEqual(item.title.count, 30, item.title)
            XCTAssertFalse(item.line.hasSuffix("。"), "ひとことは「かも」で終える:\(item.title)")
        }
        for entry in ExperienceLibrary.reframes {
            XCTAssertGreaterThanOrEqual(entry.items.count, 2, entry.keywords.joined())
        }
    }

    func testPickRespectsContext() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let lateNight = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 1))!
        for seed in 0..<40 {
            let ctx = CompanionContext(now: lateNight, timeZone: cal.timeZone, budget: .five, place: .home, mood: .tired)
            let picks = ExperienceLibrary.pick(for: ctx, count: 3, avoid: [], seed: UInt64(seed))
            XCTAssertEqual(picks.count, 3)
            for p in picks {
                XCTAssertEqual(p.duration, .five, p.title)
                guard case .library(let id) = p.origin, let item = ExperienceLibrary.item(id) else { return XCTFail() }
                XCTAssertNotEqual(item.place, .outside, p.title)
                XCTAssertEqual(item.energy, .low, p.title)
                XCTAssertTrue(item.when.allows(.lateNight), p.title)
            }
        }
    }

    func testPickPrefersInterestsAndAvoidsSeen() {
        let ctx = CompanionContext(budget: .hourPlus, place: .anywhere, mood: .normal, notes: ["料理が好き"])
        var cookingHits = 0
        for seed in 0..<30 {
            let picks = ExperienceLibrary.pick(for: ctx, count: 3, avoid: [], seed: UInt64(seed), angles: [.make])
            if case .library(let id) = picks[0].origin, ExperienceLibrary.item(id)?.tags.contains("料理") == true {
                cookingHits += 1
            }
        }
        XCTAssertGreaterThan(cookingHits, 20, "興味に合う体験が先に来る")
        let all = Set(ExperienceLibrary.items.map(\.title))
        let rest = ExperienceLibrary.pick(for: ctx, count: 3, avoid: all.subtracting(["靴をみがく"]), seed: 1)
        XCTAssertEqual(rest.first?.title, "靴をみがく")
    }

    func testRuleReflectionIsStableAndQuotesTheNote() {
        let a = ExperienceLibrary.reflection(title: "雲の形に名前をつける", note: "クジラみたいな雲がいた", feeling: .fun, category: .outside)
        let b = ExperienceLibrary.reflection(title: "雲の形に名前をつける", note: "クジラみたいな雲がいた", feeling: .fun, category: .outside)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.reply.contains("クジラみたいな雲がいた"))
        XCTAssertFalse(a.fromAI)
        XCTAssertNil(a.noteCandidate)
    }

    func testGrowthLevels() {
        XCTAssertEqual(CompanionLevel.level(points: 0), .hello)
        XCTAssertEqual(CompanionLevel.level(points: 6), .acquainted)
        XCTAssertEqual(CompanionLevel.level(points: 39), .familiar)
        XCTAssertEqual(CompanionLevel.level(points: 100), .partner)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let g = GrowthSnapshot.make(experienceCategories: [.mind, .mind, .outside], notes: 2, liked: 3, disliked: 1,
                                    since: start, now: start.addingTimeInterval(86_400 * 4))
        XCTAssertEqual(g.totalExperiences, 3)
        XCTAssertEqual(g.explored, 2)
        XCTAssertEqual(g.points, 2 * 2 + 3 + 4 / 2)
        XCTAssertEqual(g.level, .acquainted)
        XCTAssertEqual(g.daysTogether, 5)
        XCTAssertEqual(g.pointsToNext, 18 - 9)
        XCTAssertEqual(g.unexplored.count, 6)
        XCTAssertGreaterThan(g.progressToNext, 0)
    }

    func testMemoryDedupe() {
        XCTAssertTrue(CompanionMemory.isNew("夕焼けが好き", existing: ["料理が好き"]))
        XCTAssertFalse(CompanionMemory.isNew("夕焼けが好き", existing: ["夕焼けが好き。"]))
        XCTAssertFalse(CompanionMemory.isNew("散歩", existing: ["散歩が好き"]))
        XCTAssertEqual(CompanionMemory.split(selfIntroduction: "英語を勉強中、散歩が好き。\n猫と暮らしている"),
                       ["英語を勉強中", "散歩が好き", "猫と暮らしている"])
    }

    /// 体験帳(AIが動かないときの備え)の体験は、どの様子でも「いまいる場所」に合う
    func testLibraryPicksAlwaysFitThePlace() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        for hour in [2, 7, 14, 21] {
            for place in Place.allCases {
                for mood in Mood.allCases {
                    let c = CompanionContext(now: cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: hour))!,
                                             timeZone: cal.timeZone, budget: .hourPlus, place: place, mood: mood)
                    for seed in 0..<30 {
                        let picks = ExperienceLibrary.pick(for: c, count: 3, avoid: [], seed: UInt64(seed))
                        XCTAssertEqual(picks.count, 3)
                        for d in picks {
                            guard case .library(let id) = d.origin, let item = ExperienceLibrary.item(id) else {
                                return XCTFail(d.title)
                            }
                            if place == .home { XCTAssertNotEqual(item.place, .outside, "\(hour)時・\(place):\(d.title)") }
                            if place == .outside { XCTAssertNotEqual(item.place, .home, "\(hour)時・\(place):\(d.title)") }
                        }
                    }
                }
            }
        }
    }
}
