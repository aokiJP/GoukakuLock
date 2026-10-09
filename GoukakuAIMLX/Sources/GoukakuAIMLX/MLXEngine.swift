import Foundation
import GoukakuAI
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// 生成の速さなど(設定の画面とテストで使う)
public struct MLXGenerationStats: Sendable, Equatable {
    public var promptTokens: Int
    public var generatedTokens: Int
    public var promptSeconds: Double
    public var generateSeconds: Double

    public var tokensPerSecond: Double {
        generateSeconds > 0 ? Double(generatedTokens) / generateSeconds : 0
    }
}

/// MLX でモデルを動かすAI。モデルのフォルダ(config.json・tokenizer.json・*.safetensors)から読む。
/// 読み込みは最初の生成のときに1回だけ(メモリが足りないと言われたら unload で手放す)。
public final class MLXEngine: LanguageEngine {
    public let info: EngineInfo
    public let directory: URL
    let extraEOSTokens: Set<String>
    let templateFlags: [String: Bool]
    let repetitionPenalty: Double?
    let useCPU: Bool
    private let box = ContainerBox()

    /// この端末で MLX を動かせるか(シミュレータでは Metal の機能が足りず動かない)
    public static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    public init(directory: URL, id: String, name: String, extraEOSTokens: [String] = [],
                templateFlags: [String: Bool] = [:], repetitionPenalty: Double? = nil, useCPU: Bool = false) {
        self.info = EngineInfo(kind: .mlx, id: id, name: name)
        self.directory = directory
        self.extraEOSTokens = Set(extraEOSTokens)
        self.templateFlags = templateFlags
        self.repetitionPenalty = repetitionPenalty
        self.useCPU = useCPU
    }

    /// 端末に入っているモデルから作る(目録にあれば、その止め方・テンプレートの設定を使う)
    public convenience init(model: InstalledModel, useCPU: Bool = false) {
        self.init(directory: model.directory, id: model.id, name: model.name,
                  extraEOSTokens: model.spec?.extraEOSTokens ?? [],
                  templateFlags: model.spec?.templateFlags ?? ["enable_thinking": false],
                  repetitionPenalty: model.spec?.repetitionPenalty, useCPU: useCPU)
    }

    /// 先に読み込んでおく(画面を開いたときなど)
    public func load() async throws {
        _ = try await container()
    }

    public func isLoaded() async -> Bool {
        await box.isLoaded
    }

    /// モデルを手放す(メモリの警告・バックグラウンド)
    public func unload() async {
        await box.clear()
        Memory.clearCache()
    }

    /// 最後の生成の速さ
    public func lastStats() async -> MLXGenerationStats? {
        await box.stats
    }

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.onDevice {
                        try await self.stream(request, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 中身

    private func stream(_ request: GenerationRequest,
                        into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let container = try await container()
        let parameters = GenerateParameters(
            maxTokens: request.maxTokens,
            temperature: Float(request.temperature),
            topP: Float(request.topP),
            repetitionPenalty: repetitionPenalty.map { Float($0) },
            repetitionContextSize: 64
        )
        let history: [Chat.Message] = request.history.map {
            $0.role == .user ? .user($0.text) : .assistant($0.text)
        }
        var context: [String: any Sendable]? = nil
        if !templateFlags.isEmpty {
            var flags: [String: any Sendable] = [:]
            for (key, value) in templateFlags { flags[key] = value }
            context = flags
        }
        let session = ChatSession(container, instructions: request.system, history: history,
                                  generateParameters: parameters, additionalContext: context)
        for try await event in session.streamDetails(to: request.prompt) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                continuation.yield(text)
            case .info(let info):
                await box.setStats(MLXGenerationStats(promptTokens: info.promptTokenCount,
                                                      generatedTokens: info.generationTokenCount,
                                                      promptSeconds: info.promptTime,
                                                      generateSeconds: info.generateTime))
            default:
                break
            }
        }
    }

    private func container() async throws -> ModelContainer {
        let directory = directory
        let eos = extraEOSTokens
        return try await box.get {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
                throw AIError.loadFailed("config.json がありません(\(directory.lastPathComponent))")
            }
            #if os(iOS)
            // iPhone ではキャッシュを小さく(使い終わったメモリをすぐ返す)
            Memory.cacheLimit = 32 * 1024 * 1024
            #endif
            let configuration = ModelConfiguration(directory: directory, extraEOSTokens: eos)
            do {
                return try await LLMModelFactory.shared.loadContainer(
                    from: LocalOnlyDownloader(), using: TransformersTokenizerLoader(), configuration: configuration)
            } catch {
                throw AIError.loadFailed(String(describing: error))
            }
        }
    }

    /// CPU で動かす指定があれば、その中で実行する(GPU のない CI 用)
    private func onDevice(_ body: @Sendable () async throws -> Void) async throws {
        if useCPU {
            try await Device.withDefaultDevice(.cpu) { try await body() }
        } else {
            try await body()
        }
    }
}

/// 読み込んだモデルの置き場所(同時に2回読まないように)
private actor ContainerBox {
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private(set) var stats: MLXGenerationStats?

    var isLoaded: Bool { container != nil }

    func get(_ make: @escaping @Sendable () async throws -> ModelContainer) async throws -> ModelContainer {
        if let container { return container }
        if let loading { return try await loading.value }
        let task = Task { try await make() }
        loading = task
        do {
            let value = try await task.value
            container = value
            loading = nil
            return value
        } catch {
            loading = nil
            throw error
        }
    }

    func clear() {
        loading?.cancel()
        loading = nil
        container = nil
    }

    func setStats(_ value: MLXGenerationStats) {
        stats = value
    }
}

/// ネットからは取らない(モデルは端末の中のフォルダから読む)
struct LocalOnlyDownloader: MLXLMCommon.Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw AIError.unavailable("モデルはこの iPhone の中から読みます(ダウンロードは設定 › AI から)")
    }
}

/// swift-transformers のトークナイザ(tokenizer.json・chat_template.jinja)を読む
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream: upstream)
    }
}

/// swift-transformers のトークナイザを MLX の形に合わせる
struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
