import Foundation

/// 会話の1発言
public struct ChatTurn: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

/// 文章を作る頼み(どのAIでも同じ形)
public struct GenerationRequest: Sendable, Equatable {
    /// 役割の説明(system)
    public var system: String
    /// これまでのやりとり(手本の1往復や会話の履歴)
    public var history: [ChatTurn]
    /// 今回のお願い
    public var prompt: String
    public var maxTokens: Int
    public var temperature: Double
    public var topP: Double

    public init(system: String, history: [ChatTurn] = [], prompt: String, maxTokens: Int,
                temperature: Double = 0.8, topP: Double = 0.95) {
        self.system = system
        self.history = history
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
    }
}

/// AIの名前と種類(画面に出す)
public struct EngineInfo: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case mlx
        case apple
        case rules
    }

    public var kind: Kind
    public var id: String
    /// 例:「Gemma 4 E2B」「Apple Intelligence」「体験帳(AIなし)」
    public var name: String

    public init(kind: Kind, id: String, name: String) {
        self.kind = kind
        self.id = id
        self.name = name
    }

    public static let rules = EngineInfo(kind: .rules, id: "rules", name: "体験帳(AIなし)")
}

/// 文章を作るAI。MLX と Apple Intelligence がこれを満たす
public protocol LanguageEngine: Sendable {
    var info: EngineInfo { get }
    /// 文章を少しずつ返す(増えた分だけ)。キャンセルすると止まる
    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error>
}

public enum AIError: LocalizedError, Sendable, Equatable {
    case unavailable(String)
    case loadFailed(String)
    case generationFailed(String)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .unavailable(let why): return "AIを使えません:\(why)"
        case .loadFailed(let why): return "モデルを読み込めませんでした:\(why)"
        case .generationFailed(let why): return "文章を作れませんでした:\(why)"
        case .emptyOutput: return "AIの返事が空でした"
        }
    }
}

extension LanguageEngine {
    /// 最後まで生成して、全文を返す
    public func complete(_ request: GenerationRequest) async throws -> String {
        var text = ""
        for try await piece in generate(request) {
            text += piece
        }
        return text
    }
}

/// 決まった文章を返す AI(テストと、シミュレータでの画面確認用)
public struct ScriptedEngine: LanguageEngine {
    public let info: EngineInfo
    private let reply: @Sendable (GenerationRequest) -> String

    public init(info: EngineInfo = EngineInfo(kind: .mlx, id: "scripted", name: "見本のAI"),
                reply: @escaping @Sendable (GenerationRequest) -> String) {
        self.info = info
        self.reply = reply
    }

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> {
        let text = reply(request)
        return AsyncThrowingStream { continuation in
            // 生成している感じを出すため、数文字ずつ返す
            var rest = Substring(text)
            while !rest.isEmpty {
                let piece = rest.prefix(6)
                continuation.yield(String(piece))
                rest = rest.dropFirst(piece.count)
            }
            continuation.finish()
        }
    }
}
