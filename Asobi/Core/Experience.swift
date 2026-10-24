import Foundation

public struct Experience: Codable, Sendable, Equatable {
    public var title: String
    public var premise: String
    public var start: String
    public var variables: [String: Int]
    public var nodes: [Node]
    public var tags: [String]
}
public struct Node: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var seconds: Int?
    public var timeout: String?
    public var actions: [Action]
    public var ending: Bool
}
public struct Action: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var input: Bool
    public var effects: [Effect]
    public var next: String
    public var condition: Condition?
    public var alternate: String?
    public var random: [String]?
}
public struct Effect: Codable, Sendable, Equatable {
    public var key: String
    public var delta: Int
}
public struct Condition: Codable, Sendable, Equatable {
    public var key: String
    public var atLeast: Int
}
public enum PlayError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
public enum Validator {
    public static func decode(_ text: String) throws -> Experience {
        guard text.utf8.count <= 48_000 else { throw PlayError.invalid("生成結果が長すぎます") }
        let value = try JSONDecoder().decode(Experience.self, from: Data(text.utf8))
        try validate(value)
        return value
    }
    public static func validate(_ e: Experience) throws {
        func require(_ ok: Bool, _ message: String) throws { if !ok { throw PlayError.invalid(message) } }
        try require((1...60).contains(e.title.count) && (1...300).contains(e.premise.count), "タイトルまたは導入が不正です")
        try require((2...16).contains(e.nodes.count) && e.variables.count <= 6 && e.tags.count <= 8, "構造の上限を超えました")
        try require(e.tags.allSatisfy { $0.count <= 30 }, "タグが長すぎます")
        let ids = Set(e.nodes.map(\.id))
        try require(ids.count == e.nodes.count && ids.contains(e.start), "開始地点またはIDが不正です")
        try require(e.variables.allSatisfy { !$0.key.isEmpty && $0.key.count <= 20 && (-9999...9999).contains($0.value) }, "変数が不正です")
        var edges: [String: Set<String>] = [:]
        for n in e.nodes {
            try require(!n.id.isEmpty && n.id.count <= 30 && (1...500).contains(n.text.count), "場面が不正です")
            try require(n.ending ? n.actions.isEmpty : (1...4).contains(n.actions.count), "操作数が不正です")
            try require(Set(n.actions.map(\.id)).count == n.actions.count, "操作IDが重複しています")
            var targets = Set<String>()
            if let seconds = n.seconds {
                try require(!n.ending && (3...300).contains(seconds) && n.timeout != nil, "タイマーが不正です")
                targets.insert(n.timeout!)
            } else { try require(n.timeout == nil, "タイマーがありません") }
            for a in n.actions {
                try require(!a.id.isEmpty && a.id.count <= 30 && (1...60).contains(a.label.count) && a.effects.count <= 6, "操作が不正です")
                targets.insert(a.next)
                for effect in a.effects {
                    try require(e.variables[effect.key] != nil && (-100...100).contains(effect.delta), "得点操作が不正です")
                }
                if let c = a.condition {
                    try require(e.variables[c.key] != nil && (-9999...9999).contains(c.atLeast) && a.alternate != nil, "分岐が不正です")
                    targets.insert(a.alternate!)
                } else { try require(a.alternate == nil, "条件がありません") }
                if let random = a.random {
                    try require((1...4).contains(random.count) && a.condition == nil, "ランダム分岐が不正です")
                    targets.formUnion(random)
                }
            }
            try require(targets.isSubset(of: ids), "移動先が存在しません")
            edges[n.id] = targets
        }
        var reached: Set<String> = [e.start]
        for _ in e.nodes { for id in Array(reached) { reached.formUnion(edges[id] ?? []) } }
        try require(reached == ids, "到達できない場面があります")
        var canEnd = Set(e.nodes.filter(\.ending).map(\.id))
        for _ in e.nodes { for n in e.nodes where !(edges[n.id] ?? []).isDisjoint(with: canEnd) { canEnd.insert(n.id) } }
        try require(canEnd == ids, "終了できない場面があります")
    }
}
public struct Move: Codable, Sendable, Equatable {
    public var node: String
    public var action: String
    public var note: String
}
public struct Session: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var experience: Experience
    public var nodeID: String
    public var values: [String: Int]
    public var moves: [Move] = []
    public var remaining: Int?
    public var finished = false
    public var created = Date()
    public var node: Node { experience.nodes.first { $0.id == nodeID }! }
    public init(_ experience: Experience) throws {
        try Validator.validate(experience)
        self.experience = experience
        nodeID = experience.start
        values = experience.variables
        remaining = experience.nodes.first { $0.id == experience.start }?.seconds
        finished = node.ending
    }
    public mutating func apply(_ id: String, note: String = "", randomIndex: Int = 0) throws {
        guard !finished, let action = node.actions.first(where: { $0.id == id }) else { throw PlayError.invalid("この操作は使えません") }
        if action.input && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw PlayError.invalid("ひとこと入力してください") }
        guard note.count <= 200 else { throw PlayError.invalid("200文字以内で入力してください") }
        moves.append(Move(node: nodeID, action: action.label, note: note))
        for effect in action.effects { values[effect.key] = max(-9999, min(9999, values[effect.key, default: 0] + effect.delta)) }
        var next = action.next
        if let c = action.condition, values[c.key, default: 0] < c.atLeast { next = action.alternate! }
        if let choices = action.random { next = choices[max(0, randomIndex) % choices.count] }
        enter(next)
    }
    public mutating func tick() {
        guard !finished, let time = remaining else { return }
        if time <= 1, let next = node.timeout {
            moves.append(Move(node: nodeID, action: "時間切れ", note: "")); enter(next)
        } else { remaining = time - 1 }
    }
    private mutating func enter(_ id: String) {
        nodeID = id
        remaining = node.seconds
        finished = node.ending || moves.count >= 100
    }
    public func validateSaved() throws {
        try Validator.validate(experience)
        guard experience.nodes.contains(where: { $0.id == nodeID }), moves.count <= 100,
              Set(values.keys) == Set(experience.variables.keys), values.values.allSatisfy({ (-9999...9999).contains($0) }),
              moves.allSatisfy({ $0.note.count <= 200 }),
              remaining.map({ (0...300).contains($0) }) ?? true else { throw PlayError.invalid("保存データが不正です") }
    }
}
