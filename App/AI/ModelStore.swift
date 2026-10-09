import Foundation
import GoukakuAI

/// 端末に入っているモデルの置き場所と、取り込み・削除。
/// - 同梱:GoukakuLock.app/AIModels/<id>/(IPA に入っている。消せない)
/// - ダウンロード・取り込み:Application Support/AIModels/<id>/(上書きインストールでも消えない・iCloud にバックアップしない)
/// - 受け取り口:Documents/AIModels/(ファイル App・Finder から置くと、次に開いたときに取り込む)
enum ModelStore {
    static var bundledRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("AIModels", isDirectory: true)
    }

    static var installedRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("AIModels", isDirectory: true)
    }

    static var inboxRoot: URL {
        URL.documentsDirectory.appendingPathComponent("AIModels", isDirectory: true)
    }

    /// 目録を読む(アプリに同梱した AI/models.json)
    static func loadCatalog() -> ModelCatalog {
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? ModelCatalog.decode(data) else {
            return ModelCatalog(models: [])
        }
        return catalog
    }

    /// 入っているモデルをすべて探す(同梱が先)
    static func scan(catalog: ModelCatalog) -> [InstalledModel] {
        var found: [InstalledModel] = []
        var seen = Set<String>()
        for root in [bundledRoot, installedRoot].compactMap({ $0 }) {
            guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let model = read(dir, catalog: catalog), !seen.contains(model.id) else { continue }
                seen.insert(model.id)
                found.append(model)
            }
        }
        return found
    }

    /// フォルダの印(goukaku-model.json)を読む。印がなく config.json があれば、取り込んだモデルとして扱う
    static func read(_ dir: URL, catalog: ModelCatalog) -> InstalledModel? {
        let fm = FileManager.default
        let config = dir.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: config.path) else { return nil }
        if let data = try? Data(contentsOf: dir.appendingPathComponent(ModelManifest.fileName)),
           let manifest = try? ModelManifest.decode(data) {
            return InstalledModel(manifest: manifest, directory: dir, spec: catalog.spec(id: manifest.id))
        }
        return nil
    }

    // MARK: 取り込み

    enum ImportError: LocalizedError {
        case notAModel(String)
        case unsupported(String)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAModel(let why): return "モデルのフォルダではありません:\(why)"
            case .unsupported(let family): return "この形式(\(family))のモデルはまだ読めません"
            case .copyFailed(let why): return "コピーできませんでした:\(why)"
            }
        }
    }

    /// フォルダからモデルを取り込む(コピーして、要らない画像・音声の部分を取り除き、印を書く)。重いので裏で呼ぶ
    static func importFolder(_ source: URL, catalog: ModelCatalog, move: Bool = false) throws -> InstalledModel {
        let fm = FileManager.default
        let configURL = source.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL) else { throw ImportError.notAModel("config.json がない") }
        guard fm.fileExists(atPath: source.appendingPathComponent("tokenizer.json").path) else {
            throw ImportError.notAModel("tokenizer.json がない")
        }
        let files = (try? fm.contentsOfDirectory(atPath: source.path)) ?? []
        guard files.contains(where: { $0.hasSuffix(".safetensors") }) else {
            throw ImportError.notAModel("重み(.safetensors)がない。MLX 形式のモデルを選んでください")
        }
        let family = ModelConfigProbe.family(fromConfig: configData) ?? "?"
        guard ModelConfigProbe.isSupported(family: family) else { throw ImportError.unsupported(family) }

        // 目録のモデルなら、その id で入れる(印があればそれを使う)
        var known: ModelSpec?
        if let data = try? Data(contentsOf: source.appendingPathComponent(ModelManifest.fileName)),
           let manifest = try? ModelManifest.decode(data) {
            known = catalog.spec(id: manifest.id)
        }
        let id = known?.id ?? "imported-" + slug(source.lastPathComponent)
        let name = known?.name ?? source.lastPathComponent
        try fm.createDirectory(at: installedRoot, withIntermediateDirectories: true)
        let destination = installedRoot.appendingPathComponent(id, isDirectory: true)
        let staging = installedRoot.appendingPathComponent(".staging-\(id)", isDirectory: true)
        try? fm.removeItem(at: staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for file in files where !file.hasPrefix(".") {
                let from = source.appendingPathComponent(file)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: from.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                if move {
                    try fm.moveItem(at: from, to: staging.appendingPathComponent(file))
                } else {
                    try fm.copyItem(at: from, to: staging.appendingPathComponent(file))
                }
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw ImportError.copyFailed(error.localizedDescription)
        }
        // 画像・音声の部分を取り除く(目録にあればその指定、なければ形式から)
        let prefixes = known?.stripPrefixes ?? defaultStripPrefixes(family: family)
        if !prefixes.isEmpty {
            try SafetensorsSlimmer.slimDirectory(staging) { name in !prefixes.contains { name.hasPrefix($0) } }
        }
        let bytes = directorySize(staging)
        let manifest = ModelManifest(id: id, name: name, family: family, source: .imported, repo: known?.repo,
                                     revision: known?.revision, installedAt: Date(), bytes: bytes)
        try manifest.encoded().write(to: staging.appendingPathComponent(ModelManifest.fileName), options: .atomic)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
        excludeFromBackup(destination)
        return InstalledModel(manifest: manifest, directory: destination, spec: known)
    }

    /// 受け取り口(Documents/AIModels)に置かれたフォルダを取り込む。取り込んだものの名前と、失敗の理由を返す
    static func importInbox(catalog: ModelCatalog) -> (imported: [String], failures: [String]) {
        let fm = FileManager.default
        ensureInbox()
        guard let dirs = try? fm.contentsOfDirectory(at: inboxRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return ([], [])
        }
        var imported: [String] = []
        var failures: [String] = []
        for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) else { continue }
            do {
                let model = try importFolder(dir, catalog: catalog, move: true)
                try? fm.removeItem(at: dir)
                imported.append(model.name)
            } catch {
                failures.append("\(dir.lastPathComponent):\(error.localizedDescription)")
            }
        }
        return (imported, failures)
    }

    /// 受け取り口のフォルダを作り、置き方の説明を置く(ファイル App で見えるように)
    static func ensureInbox() {
        let fm = FileManager.default
        try? fm.createDirectory(at: inboxRoot, withIntermediateDirectories: true)
        let readme = inboxRoot.appendingPathComponent("ここにモデルのフォルダを置く.txt")
        guard !fm.fileExists(atPath: readme.path) else { return }
        let text = """
        このフォルダ(合格ロック › AIModels)に、MLX 形式のモデルのフォルダを置くと、
        次に合格ロックを開いたときに取り込みます。

        フォルダの中に要るもの:config.json・tokenizer.json・*.safetensors(・chat_template.jinja)
        例:Hugging Face の mlx-community にある 4bit のモデル

        取り込んだあとは、このフォルダから消えます(アプリの中に移ります)。
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }

    /// ダウンロード・取り込んだモデルを消す(同梱のモデルは消せない)
    static func delete(_ model: InstalledModel) throws {
        guard model.manifest.source != .bundled else { return }
        try FileManager.default.removeItem(at: model.directory)
    }

    /// 形式ごとの、文章に要らない部分
    static func defaultStripPrefixes(family: String) -> [String] {
        switch family {
        case "qwen3_5": return ["vision_tower."]
        case "gemma4", "gemma3n": return ["vision_tower.", "audio_tower.", "embed_vision.", "embed_audio."]
        default: return []
        }
    }

    static func directorySize(_ dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }

    static func slug(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-._")
        let s = name.lowercased().map { allowed.contains($0) ? $0 : "-" }
        let collapsed = String(s).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? String(UUID().uuidString.prefix(8)).lowercased() : String(collapsed.prefix(40))
    }

    /// 空いている保存容量
    static func freeSpace() -> Int64? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
