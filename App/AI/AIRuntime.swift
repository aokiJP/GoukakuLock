import Foundation
import Observation
import UIKit
import GoukakuAI
import GoukakuAIMLX

/// 相棒AIの「どのAIを、どう動かすか」を受け持つ(完全環境適応)。
/// 端末の様子(メモリ・iOS・熱・低電力モード・Apple Intelligence)と、入っているモデルから
/// 使うAIを決め、様子が変わるたびに選び直す。MLX のモデルは使うときに読み込み、
/// 裏に回ったときやメモリの警告で手放す。読み込み中にアプリが終了したモデルは、次から避ける。
@MainActor @Observable
final class AIRuntime {
    static let shared = AIRuntime()

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var catalog: ModelCatalog
    private(set) var installed: [InstalledModel] = []
    private(set) var profile: DeviceProfile
    private(set) var decision: RouteDecision
    private(set) var phase: Phase = .idle
    /// 最後に測った生成の速さ(毎秒のトークン数。MLX のときだけ)
    private(set) var lastTokensPerSecond: Double?
    /// 取り込みの結果などの知らせ
    var message: String?
    let downloader = ModelDownloader()

    var preference: EnginePreference = .automatic {
        didSet {
            guard preference != oldValue else { return }
            UserDefaults.standard.set(preference.rawValue, forKey: Keys.preference)
            refresh()
        }
    }

    var allowCellular: Bool = UserDefaults.standard.bool(forKey: Keys.cellular) {
        didSet { UserDefaults.standard.set(allowCellular, forKey: Keys.cellular) }
    }

    @ObservationIgnored private var engine: (any LanguageEngine)?
    @ObservationIgnored private var unloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let preference = "ai.preference"
        static let cellular = "ai.allowCellular"
        /// 読み込み中のモデル(アプリが落ちたら、次の起動で残っている)
        static let loading = "ai.loadingModel"
        /// 読み込みでアプリが終了したモデル
        static let crashed = "ai.crashedModels"
    }

    init() {
        catalog = ModelStore.loadCatalog()
        profile = DeviceProbe.current()
        decision = RouteDecision(choice: .rules, tuning: GenerationTuning(), reasons: [], skipped: [])
        preference = EnginePreference(rawValue: UserDefaults.standard.string(forKey: Keys.preference) ?? "auto")
        // 前回、読み込み中にアプリが終了していたら、そのモデルは避ける(落ち続けないように)
        if let crashed = UserDefaults.standard.string(forKey: Keys.loading) {
            var set = crashedModels
            set.insert(crashed)
            UserDefaults.standard.set(Array(set), forKey: Keys.crashed)
            UserDefaults.standard.removeObject(forKey: Keys.loading)
        }
        observe()
        refresh()
        // IPA に同梱のモデルを、アプリの外にも残す(APFS のクローンで容量は増えない)。
        // こうしておくと、あとで AIなし版を上書きでインストールしても、モデルが消えない
        let catalog = self.catalog
        Task.detached(priority: .utility) { [weak self] in
            guard ModelStore.keepBundledModels(catalog: catalog) else { return }
            await self?.refresh()
        }
    }

    // MARK: 状態

    /// いまの相棒の頭(AIか体験帳)
    var brain: CompanionBrain { CompanionBrain(engine: engine, tuning: decision.tuning) }

    var engineInfo: EngineInfo { engine?.info ?? .rules }

    var usesAI: Bool { engine != nil }

    /// 画面に出す一言(例:「Gemma 4 E2B・この iPhone の中で動作」)
    var statusLine: String {
        let info = engineInfo
        if info.id == SampleAIInfo.id { return "見本のAI(画面の確認用)" }
        switch info.kind {
        case .mlx, .apple: return "\(info.name)・この iPhone の中で動作"
        case .rules: return "体験帳(AIなし)"
        }
    }

    var crashedModels: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Keys.crashed) ?? [])
    }

    /// 目録のうち、まだ入っていないモデル
    var downloadable: [ModelSpec] {
        let have = Set(installed.map(\.id))
        return catalog.models.filter { !have.contains($0.id) }
    }

    // MARK: 選び直す

    /// 端末の様子とモデルを調べ直し、使うAIを決め直す
    func refresh() {
        profile = DeviceProbe.current()
        installed = ModelStore.scan(catalog: catalog)
        let crashed = crashedModels
        let usable = installed.filter { !crashed.contains($0.id) }
        var next = EngineRouter.decide(profile: profile, installed: usable, preference: preference)
        for model in installed where crashed.contains(model.id) {
            next.skipped.append(.init(name: model.name, reason: "前回、読み込み中にアプリが終了したので休ませています"))
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingScriptedAI") || UserDefaults.standard.bool(forKey: "debug.sampleAI") {
            next = RouteDecision(choice: .rules, tuning: GenerationTuning(),
                                 reasons: ["見本のAI(シミュレータでの画面確認用。Gemma 4 E2B の出力をもとにした決まった文を返す)"], skipped: [])
            if engine?.info.id != SampleAIInfo.id { engine = SampleAI.engine }
            decision = next
            phase = .ready
            return
        }
        #endif
        let changed = next.choice != decision.choice
        decision = next
        if changed || engine == nil && next.choice != .rules || engine?.info.id == SampleAIInfo.id {
            Task { await self.switchEngine() }
        }
    }

    /// 選んだAIに切りかえる(前の MLX モデルは手放す)
    private func switchEngine() async {
        if let old = engine as? MLXEngine { await old.unload() }
        engine = nil
        lastTokensPerSecond = nil
        phase = .idle
        switch decision.choice {
        case .mlx(let model):
            guard MLXEngine.isSupported else { return }
            engine = MLXEngine(model: model)
        case .apple:
            engine = AppleEngine()
            phase = .ready
        case .rules:
            phase = .ready
        }
    }

    /// AIを使う前に呼ぶ(MLX ならモデルを読み込む。失敗したら体験帳に切りかえる)
    func ensureReady() async {
        unloadTask?.cancel()
        guard let mlx = engine as? MLXEngine else { return }
        if await mlx.isLoaded() { phase = .ready; return }
        guard phase != .loading else {
            // ほかで読み込み中なら、終わるまで待つ(止められたら、待つのをやめる)
            while phase == .loading && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(150)) }
            return
        }
        phase = .loading
        // 読み込み中に落ちたら次の起動でわかるよう、印をつけておく
        UserDefaults.standard.set(mlx.info.id, forKey: Keys.loading)
        do {
            try await mlx.load()
            UserDefaults.standard.removeObject(forKey: Keys.loading)
            phase = .ready
        } catch {
            UserDefaults.standard.removeObject(forKey: Keys.loading)
            phase = .failed(error.localizedDescription)
            message = "「\(mlx.info.name)」を読み込めなかったので、ほかのAIに切りかえました"
            var set = crashedModels
            set.insert(mlx.info.id)
            UserDefaults.standard.set(Array(set), forKey: Keys.crashed)
            refresh()
        }
    }

    /// 生成のあとに速さを記録する
    func noteStats() async {
        guard let mlx = engine as? MLXEngine, let stats = await mlx.lastStats() else { return }
        lastTokensPerSecond = stats.tokensPerSecond
    }

    /// 休ませていたモデルを、もう一度使えるようにする
    func retry(_ model: InstalledModel) {
        var set = crashedModels
        set.remove(model.id)
        UserDefaults.standard.set(Array(set), forKey: Keys.crashed)
        refresh()
    }

    /// モデルを手放す(裏に回ったとき・メモリの警告)
    func unload() async {
        guard let mlx = engine as? MLXEngine else { return }
        await mlx.unload()
        if phase == .ready { phase = .idle }
    }

    // MARK: モデルの出し入れ

    func download(_ spec: ModelSpec) {
        downloader.start(spec, allowCellular: allowCellular) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let model):
                self.message = "「\(model.name)」を入れました。これからは通信なしで動きます"
                self.refresh()
            case .failure:
                break
            }
        }
    }

    func delete(_ model: InstalledModel) async {
        if engine?.info.id == model.id { await unload() }
        do {
            try ModelStore.delete(model)
            message = "「\(model.name)」を消しました"
        } catch {
            message = "消せませんでした:\(error.localizedDescription)"
        }
        if case .model(let id) = preference, id == model.id { preference = .automatic }
        refresh()
    }

    /// ファイル App で選んだフォルダを取り込む
    func importFolder(_ url: URL) async {
        let catalog = self.catalog
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let model = try await Task.detached(priority: .userInitiated) {
                try ModelStore.importFolder(url, catalog: catalog)
            }.value
            message = "「\(model.name)」を取り込みました"
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    /// 受け取り口(ファイル App の 合格ロック › AIModels)に置かれたモデルを取り込む
    func importInbox() async {
        let catalog = self.catalog
        let result = await Task.detached(priority: .utility) {
            ModelStore.importInbox(catalog: catalog)
        }.value
        if !result.imported.isEmpty {
            message = "「\(result.imported.joined(separator: "」「"))」を取り込みました"
            refresh()
        } else if let failure = result.failures.first {
            message = "取り込めませんでした:\(failure)"
        }
    }

    // MARK: 端末の様子の変化

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.unload() }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // しばらく戻らなければ手放す(裏でメモリを使い続けて終了させられないように)
                self.unloadTask?.cancel()
                self.unloadTask = Task {
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled else { return }
                    await self.unload()
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.unloadTask?.cancel()
                self.refresh()
                Task { await self.importInbox() }
            }
        })
    }
}
