import Foundation

/// 端末の熱の状態(ProcessInfo.ThermalState と同じ段階)
public enum ThermalLevel: Int, Codable, Sendable, Comparable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .nominal: return "ふつう"
        case .fair: return "少し温かい"
        case .serious: return "熱い"
        case .critical: return "とても熱い"
        }
    }
}

/// Apple Intelligence(Foundation Models)の使える状態
public enum AppleIntelligenceState: String, Codable, Sendable {
    case available
    /// 端末が対応していない
    case deviceNotEligible
    /// 設定でオフ
    case notEnabled
    /// モデルの準備中(ダウンロード中など)
    case notReady
    /// iOS が古い(iOS 26 から)
    case unsupportedOS
    /// このビルドでは使えない(SDK が古いなど)
    case unavailable

    public var label: String {
        switch self {
        case .available: return "使える"
        case .deviceNotEligible: return "この iPhone は非対応"
        case .notEnabled: return "設定でオフ"
        case .notReady: return "準備中"
        case .unsupportedOS: return "iOS 26 以降で使える"
        case .unavailable: return "使えない"
        }
    }
}

/// いまの端末の様子。AIをどう動かすかを決める材料(すべて端末の中で調べる)
public struct DeviceProfile: Sendable, Equatable {
    /// 搭載メモリ
    public var physicalMemory: UInt64
    /// このアプリがあと使えるメモリ(os_proc_available_memory。わからなければ nil)
    public var availableMemory: UInt64?
    public var osMajor: Int
    public var osMinor: Int
    /// 機種の識別子(例:iPhone18,1)
    public var model: String
    public var isSimulator: Bool
    public var thermal: ThermalLevel
    public var lowPowerMode: Bool
    public var appleIntelligence: AppleIntelligenceState
    /// GPU が MLX に足りるか(Metal 3:A13 以降)
    public var supportsMLX: Bool

    public init(physicalMemory: UInt64, availableMemory: UInt64?, osMajor: Int, osMinor: Int, model: String,
                isSimulator: Bool, thermal: ThermalLevel, lowPowerMode: Bool,
                appleIntelligence: AppleIntelligenceState, supportsMLX: Bool = true) {
        self.physicalMemory = physicalMemory
        self.availableMemory = availableMemory
        self.osMajor = osMajor
        self.osMinor = osMinor
        self.model = model
        self.isSimulator = isSimulator
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.appleIntelligence = appleIntelligence
        self.supportsMLX = supportsMLX
    }

    public var physicalMemoryGB: Double { Double(physicalMemory) / 1_073_741_824 }

    /// アプリが使えるメモリの見込み。実測(availableMemory)があればそれ、なければ搭載メモリの半分弱
    public var memoryBudget: UInt64 {
        if let availableMemory { return availableMemory }
        return UInt64(Double(physicalMemory) * 0.45)
    }
}

/// 使うAIの指定(設定の「使うAI」)
public enum EnginePreference: Codable, Sendable, Equatable, Hashable {
    /// 端末に合わせて自動で選ぶ
    case automatic
    /// このモデルを使う(入っていて動くなら)
    case model(String)
    /// Apple Intelligence を使う
    case apple
    /// AIを使わない(体験帳だけ)
    case off

    public var rawValue: String {
        switch self {
        case .automatic: return "auto"
        case .model(let id): return "model:\(id)"
        case .apple: return "apple"
        case .off: return "off"
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "apple": self = .apple
        case "off": self = .off
        default:
            if rawValue.hasPrefix("model:") {
                self = .model(String(rawValue.dropFirst("model:".count)))
            } else {
                self = .automatic
            }
        }
    }
}

/// 選んだAI
public enum EngineChoice: Sendable, Equatable {
    case mlx(InstalledModel)
    case apple
    case rules

    public var kind: String {
        switch self {
        case .mlx: return "mlx"
        case .apple: return "apple"
        case .rules: return "rules"
        }
    }
}

/// 生成の調整(端末の様子に合わせて、長さと文脈の量を変える)
public struct GenerationTuning: Sendable, Equatable {
    /// 生成するトークン数にかける倍率(熱い・低電力なら短く)
    public var lengthScale: Double
    /// プロンプトに入れる「最近の体験」「覚えていること」の数
    public var contextItems: Int
    /// 会話の履歴を何往復まで入れるか
    public var chatTurns: Int
    /// 提案に「思いつきのきっかけ」の言葉を添えるか(小さいモデルはその言葉に引っぱられて話がそれるので添えない)
    public var useHints: Bool
    /// 提案の1回目の温度(小さいモデルは低めにして、話の筋を保ちやすくする)
    public var suggestionTemperature: Double
    /// 会話・手紙・気づきの温度と top-p(モデルを作った人のおすすめ。小さいモデルほど低くして、話の筋とくり返しを抑える)
    public var chatTemperature: Double
    public var chatTopP: Double

    public init(lengthScale: Double = 1, contextItems: Int = 6, chatTurns: Int = 10,
                useHints: Bool = true, suggestionTemperature: Double = 0.85,
                chatTemperature: Double = 0.8, chatTopP: Double = 0.95) {
        self.lengthScale = lengthScale
        self.contextItems = contextItems
        self.chatTurns = chatTurns
        self.useHints = useHints
        self.suggestionTemperature = suggestionTemperature
        self.chatTemperature = chatTemperature
        self.chatTopP = chatTopP
    }

    public func tokens(_ base: Int) -> Int { max(48, Int((Double(base) * lengthScale).rounded())) }
}

/// AIの選び方の結果と、その理由(設定の画面にそのまま出す)
public struct RouteDecision: Sendable, Equatable {
    public var choice: EngineChoice
    public var tuning: GenerationTuning
    /// 選んだ理由(日本語)
    public var reasons: [String]
    /// 選ばなかったモデルとその理由
    public var skipped: [Skipped]

    public struct Skipped: Sendable, Equatable {
        public var name: String
        public var reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public init(choice: EngineChoice, tuning: GenerationTuning, reasons: [String], skipped: [Skipped]) {
        self.choice = choice
        self.tuning = tuning
        self.reasons = reasons
        self.skipped = skipped
    }
}

/// 端末の様子と入っているモデルから、使うAIを決める(完全環境適応の芯)。
/// 順番:指定 → 端末に入っているモデル(動く中で日本語が一番自然なもの)→ Apple Intelligence → 体験帳
public enum EngineRouter {
    /// モデルを読むときに、見込みのメモリに対して残しておく割合
    static let headroom = 0.9

    public static func decide(profile: DeviceProfile, installed: [InstalledModel],
                              preference: EnginePreference) -> RouteDecision {
        var reasons: [String] = []
        var skipped: [RouteDecision.Skipped] = []
        var tuning = GenerationTuning()

        if profile.thermal >= .serious {
            tuning.lengthScale *= 0.7
            reasons.append("端末が\(profile.thermal.label)ので、返事を短めにしています")
        }
        if profile.lowPowerMode {
            tuning.lengthScale *= 0.8
            reasons.append("低電力モードなので、返事を短めにしています")
        }

        if preference == .off {
            reasons.insert("設定で「AIを使わない」にしているので、体験帳から選びます", at: 0)
            return RouteDecision(choice: .rules, tuning: tuning, reasons: reasons, skipped: skipped)
        }
        if profile.thermal == .critical {
            reasons.insert("端末がとても熱いので、冷めるまでAIを休ませ、体験帳から選びます", at: 0)
            return RouteDecision(choice: .rules, tuning: tuning, reasons: reasons, skipped: skipped)
        }

        // 動かせるモデル(メモリに収まるもの)
        var runnable: [InstalledModel] = []
        let budget = Double(profile.memoryBudget) * headroom
        for model in installed {
            if profile.isSimulator {
                skipped.append(.init(name: model.name, reason: "シミュレータでは MLX が動かない"))
                continue
            }
            if !profile.supportsMLX {
                skipped.append(.init(name: model.name, reason: "この iPhone の GPU では MLX が動かない(A13 以降が必要)"))
                continue
            }
            if Double(model.runtimeBytes) > budget {
                skipped.append(.init(name: model.name,
                                     reason: "メモリが足りない(要る見込み \(gb(model.runtimeBytes)) / 使える見込み \(gb(Int64(budget))))"))
                continue
            }
            runnable.append(model)
        }

        let appleReady = profile.appleIntelligence == .available

        // 指定があれば、まずそれ
        switch preference {
        case .model(let id):
            if let model = runnable.first(where: { $0.id == id }) {
                reasons.insert("設定で選んだ「\(model.name)」を、この iPhone の中で動かしています", at: 0)
                tuning.apply(for: model)
                return RouteDecision(choice: .mlx(model), tuning: tuning, reasons: reasons, skipped: skipped)
            }
            let name = installed.first(where: { $0.id == id })?.name ?? id
            reasons.append("選んだ「\(name)」は今は使えないので、ほかから選びました")
        case .apple:
            if appleReady {
                reasons.insert("設定で選んだ Apple Intelligence を使っています", at: 0)
                return RouteDecision(choice: .apple, tuning: tuning, reasons: reasons, skipped: skipped)
            }
            reasons.append("Apple Intelligence は今は使えない(\(profile.appleIntelligence.label))ので、ほかから選びました")
        case .automatic, .off:
            break
        }

        // 低電力モードで Apple Intelligence が使えるなら、電池にやさしい方を先に
        if profile.lowPowerMode && appleReady {
            reasons.insert("低電力モードなので、電池にやさしい Apple Intelligence を使っています", at: 0)
            return RouteDecision(choice: .apple, tuning: tuning, reasons: reasons, skipped: skipped)
        }

        if let best = pickBest(runnable, profile: profile) {
            reasons.insert("「\(best.name)」を、この iPhone の中だけで動かしています(通信なし)", at: 0)
            if runnable.count > 1 {
                reasons.append("入っているモデルのうち、動かせて日本語が一番自然なものを選びました")
            }
            tuning.apply(for: best)
            return RouteDecision(choice: .mlx(best), tuning: tuning, reasons: reasons, skipped: skipped)
        }

        if appleReady {
            reasons.insert("Apple Intelligence を使っています(この iPhone の中で動きます)", at: 0)
            return RouteDecision(choice: .apple, tuning: tuning, reasons: reasons, skipped: skipped)
        }

        if installed.isEmpty {
            reasons.insert("AIのモデルが入っていないので、体験帳から選んでいます。設定 › AI からモデルを入れられます", at: 0)
        } else {
            reasons.insert("入っているモデルを今は動かせないので、体験帳から選んでいます", at: 0)
        }
        return RouteDecision(choice: .rules, tuning: tuning, reasons: reasons, skipped: skipped)
    }

    /// 動かせるモデルの中から選ぶ:日本語の自然さ → 熱いときは軽いもの → 小さいもの
    static func pickBest(_ models: [InstalledModel], profile: DeviceProfile) -> InstalledModel? {
        models.max { a, b in
            if profile.thermal >= .serious, a.runtimeBytes != b.runtimeBytes {
                return a.runtimeBytes > b.runtimeBytes   // 熱いときは軽い方が上
            }
            if a.japanese != b.japanese { return a.japanese < b.japanese }
            return a.runtimeBytes > b.runtimeBytes
        }
    }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.1fGB", Double(bytes) / 1_073_741_824)
    }
}

extension GenerationTuning {
    /// モデルの大きさで、プロンプトに入れる量と会話を覚えている長さを変える(小さいモデルほど少なく。メモリと速さのため)。
    /// 話す中身はどのモデルでも同じようにしばらない
    public mutating func apply(for model: InstalledModel) {
        let gb = Double(model.runtimeBytes) / 1_073_741_824
        if gb < 1.2 {
            contextItems = 4
            chatTurns = 6
        } else if gb < 2.2 {
            contextItems = 5
            chatTurns = 8
        } else {
            contextItems = 6
            chatTurns = 10
        }
        // 小さいモデル(CI で LFM2.5・Qwen3.5 2B を見た)は、きっかけの言葉に引っぱられて話がそれやすいので
        // 言葉は添えず、温度も少し下げる(話の筋を保つための調整で、中身はしばらない)
        useHints = gb >= 2.2
        suggestionTemperature = gb >= 2.2 ? 0.85 : 0.7
        // 会話の温度:目録にモデルのおすすめがあればそれ(LFM2.5 は 0.3、Qwen3.5 は 0.7・top-p 0.8)、なければ大きさで
        chatTemperature = model.spec?.chatTemperature ?? (gb < 1.2 ? 0.4 : gb < 2.2 ? 0.7 : 0.8)
        chatTopP = model.spec?.chatTopP ?? (gb < 2.2 ? 0.8 : 0.95)
    }
}
