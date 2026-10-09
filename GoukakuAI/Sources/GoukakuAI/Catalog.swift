import Foundation

/// 使えるモデルの1件(リポジトリの AI/models.json と同じ形)。
/// CI はこれを読んで「モデルごとの IPA」を作り、アプリはこれを読んでダウンロードや説明に使う。
public struct ModelSpec: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// 画面に出す名前(例:Gemma 4 E2B)
    public var name: String
    /// 一言の説明(日本語)
    public var summary: String
    /// config.json の model_type(MLX がどの実装で読むか)
    public var family: String
    /// Hugging Face のリポジトリ(MLX 形式・4bit)
    public var repo: String
    /// 固定するリビジョン(コミット)。同じ中身を毎回取るため
    public var revision: String
    /// 取ってくるファイル
    public var files: [String]
    /// 取り除くテンソルの名前の頭(画像・音声の部分。文章だけ使うので要らない)
    public var stripPrefixes: [String]
    /// ダウンロードする大きさ(バイト)
    public var downloadBytes: Int64
    /// 入れたあとの大きさ(バイト。取り除いたあと)
    public var installedBytes: Int64
    /// 動かすのに要るメモリのめやす(バイト。重み+文脈+ゆとり)
    public var runtimeBytes: Int64
    /// おすすめの端末メモリ(GB)
    public var recommendedRAMGB: Double
    /// 日本語の自然さ(1〜5。手元で試した印象)
    public var japanese: Int
    /// 速さ(1〜5)
    public var speed: Int
    /// 速さの説明(例:iPhone 17 Pro で毎秒約50トークン)
    public var speedNote: String
    public var license: String
    public var licenseURL: String
    /// 生成を止める追加のトークン
    public var extraEOSTokens: [String]
    /// チャットテンプレートに渡す値(例:enable_thinking = false)
    public var templateFlags: [String: Bool]
    /// 同じ言葉のくり返しをおさえる強さ(小さなモデル向け。なければ使わない)
    public var repetitionPenalty: Double?
    /// このモデルを同梱した IPA を作るか
    public var ipa: Bool

    public init(id: String, name: String, summary: String, family: String, repo: String, revision: String,
                files: [String], stripPrefixes: [String], downloadBytes: Int64, installedBytes: Int64,
                runtimeBytes: Int64, recommendedRAMGB: Double, japanese: Int, speed: Int, speedNote: String,
                license: String, licenseURL: String, extraEOSTokens: [String] = [],
                templateFlags: [String: Bool] = [:], repetitionPenalty: Double? = nil, ipa: Bool = true) {
        self.id = id
        self.name = name
        self.summary = summary
        self.family = family
        self.repo = repo
        self.revision = revision
        self.files = files
        self.stripPrefixes = stripPrefixes
        self.downloadBytes = downloadBytes
        self.installedBytes = installedBytes
        self.runtimeBytes = runtimeBytes
        self.recommendedRAMGB = recommendedRAMGB
        self.japanese = japanese
        self.speed = speed
        self.speedNote = speedNote
        self.license = license
        self.licenseURL = licenseURL
        self.extraEOSTokens = extraEOSTokens
        self.templateFlags = templateFlags
        self.repetitionPenalty = repetitionPenalty
        self.ipa = ipa
    }

    /// Hugging Face のダウンロード URL
    public func url(for file: String) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")
    }

    /// テンソルを残すか(stripPrefixes に当たるものは捨てる)
    public func keepsTensor(named name: String) -> Bool {
        !stripPrefixes.contains { name.hasPrefix($0) }
    }
}

/// モデルの目録(AI/models.json)
public struct ModelCatalog: Codable, Sendable, Equatable {
    public var version: Int
    public var models: [ModelSpec]

    public init(version: Int = 1, models: [ModelSpec]) {
        self.version = version
        self.models = models
    }

    public static func decode(_ data: Data) throws -> ModelCatalog {
        try JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    public func spec(id: String) -> ModelSpec? { models.first { $0.id == id } }
}

/// 端末に入っているモデルの印(モデルのフォルダの goukaku-model.json)
public struct ModelManifest: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// IPA に同梱
        case bundled
        /// アプリの中でダウンロード
        case downloaded
        /// ファイル App・Finder から取り込み
        case imported
        /// IPA に同梱されていたものを、アプリの外にも残したもの(APFS のクローンなので容量は増えない。
        /// あとで AIなし版を上書きでインストールしても消えない)
        case kept
    }

    public static let fileName = "goukaku-model.json"

    public var id: String
    public var name: String
    public var family: String
    public var source: Source
    public var repo: String?
    public var revision: String?
    public var installedAt: Date?
    /// 重みなどの合計(バイト)
    public var bytes: Int64

    /// goukaku-model.json を読む(日付は ISO 8601。CI の scripts/fetch-model.py と同じ形)
    public static func decode(_ data: Data) throws -> ModelManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ModelManifest.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public init(id: String, name: String, family: String, source: Source, repo: String? = nil,
                revision: String? = nil, installedAt: Date? = nil, bytes: Int64) {
        self.id = id
        self.name = name
        self.family = family
        self.source = source
        self.repo = repo
        self.revision = revision
        self.installedAt = installedAt
        self.bytes = bytes
    }
}

/// 端末に入っているモデル1つ
public struct InstalledModel: Sendable, Equatable, Identifiable {
    public var manifest: ModelManifest
    public var directory: URL
    /// 目録にある既知のモデルなら、その説明
    public var spec: ModelSpec?

    public init(manifest: ModelManifest, directory: URL, spec: ModelSpec?) {
        self.manifest = manifest
        self.directory = directory
        self.spec = spec
    }

    public var id: String { manifest.id }
    public var name: String { spec?.name ?? manifest.name }

    /// 動かすのに要るメモリのめやす。目録になければ重みの大きさから見積もる
    public var runtimeBytes: Int64 {
        if let spec { return spec.runtimeBytes }
        return Int64(Double(manifest.bytes) * 1.25) + 450 * 1_048_576
    }

    /// 日本語の自然さ(わからなければ真ん中)
    public var japanese: Int { spec?.japanese ?? 3 }
}

/// config.json の中から、MLX がこのモデルを読めるかの手がかりを取る
public enum ModelConfigProbe {
    /// MLX(mlx-swift-lm)の LLM として読める model_type
    public static let supportedFamilies: Set<String> = [
        "qwen3_5", "qwen3_5_text", "qwen3", "qwen2", "gemma4", "gemma4_text", "gemma3", "gemma3_text",
        "gemma3n", "gemma2", "gemma", "lfm2", "llama", "mistral", "phi3", "smollm3", "granite",
    ]

    /// config.json(または入れ子の text_config)から model_type を読む
    public static func family(fromConfig data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["model_type"] as? String
    }

    public static func isSupported(family: String) -> Bool {
        supportedFamilies.contains(family)
    }
}
