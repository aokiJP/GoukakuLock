import SwiftUI
import UniformTypeIdentifiers
import GoukakuAI

/// 設定 › AI:どのAIが、なぜ選ばれているか。モデルの出し入れ(同梱・ダウンロード・ファイルから取り込み)
struct AISettingsView: View {
    @Environment(AIRuntime.self) private var runtime
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var deleting: InstalledModel?

    var body: some View {
        @Bindable var runtime = runtime
        Form {
            currentSection
            Section {
                Picker("使うAI", selection: $runtime.preference) {
                    Text("自動(この iPhone に合わせる)").tag(EnginePreference.automatic)
                    ForEach(runtime.installed) { m in
                        Text(m.name).tag(EnginePreference.model(m.id))
                    }
                    Text("Apple Intelligence").tag(EnginePreference.apple)
                    Text("AIを使わない(体験帳だけ)").tag(EnginePreference.off)
                }
            } footer: {
                Text("自動では、入っているモデルのうち「動かせて、日本語が一番自然なもの」→ Apple Intelligence → 体験帳 の順に選びます。熱いときや低電力モードでは、軽い方・電池にやさしい方に切りかえます。")
            }
            deviceSection
            installedSection
            downloadSection
            importSection
            Section {
                Toggle("チェックインのあとに、相棒がひとこと返す", isOn: Binding(
                    get: { model.settings.companionReflectAfterCheckIn },
                    set: {
                        model.settings.companionReflectAfterCheckIn = $0
                        model.save()
                    }
                ))
                NavigationLink("相棒が覚えていること") { GrowthView() }
            } header: {
                Text("相棒")
            } footer: {
                Text("AIはすべてこの iPhone の中で動き、書いたことはどこにも送りません。ネットにつなぐのは、モデルをダウンロードするときだけです(Hugging Face から公開のファイルを取るだけで、あなたのデータは送りません)。")
            }
        }
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await runtime.importFolder(url) }
            }
        }
        .confirmationDialog("このモデルを消しますか?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { m in
            Button("「\(m.name)」を消す", role: .destructive) {
                Task { await runtime.delete(m) }
            }
        } message: { m in
            Text("\(DeviceProbe.gb(m.manifest.bytes)) の空きができます。あとでまたダウンロードできます。")
        }
        .alert(runtime.message ?? "", isPresented: Binding(get: { runtime.message != nil }, set: { if !$0 { runtime.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .refreshable { runtime.refresh() }
        .onAppear { runtime.refresh() }
    }

    // MARK: いまのAI

    private var currentSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: runtime.engineInfo.kind == .apple ? "apple.logo" : (runtime.usesAI ? "cpu" : "book.closed"))
                    .font(.title2)
                    .foregroundStyle(Theme.pencil)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runtime.statusLine).font(.body.weight(.semibold))
                    switch runtime.phase {
                    case .loading:
                        Text("モデルを読み込んでいます…").font(.caption).foregroundStyle(Theme.muted)
                    case .failed(let why):
                        Text(why).font(.caption).foregroundStyle(Theme.seal)
                    default:
                        if let speed = runtime.lastTokensPerSecond {
                            Text(String(format: "前回の速さ:毎秒 %.0f トークン", speed)).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            ForEach(runtime.decision.reasons, id: \.self) { reason in
                Label(reason, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
            }
            ForEach(runtime.decision.skipped, id: \.name) { skip in
                Label("\(skip.name):\(skip.reason)", systemImage: "minus.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text("いまのAI")
        }
    }

    // MARK: この iPhone

    private var deviceSection: some View {
        let p = runtime.profile
        return Section {
            InfoRow(title: "メモリ", value: DeviceProbe.gb(p.physicalMemory))
            if let available = p.availableMemory {
                InfoRow(title: "アプリが使える見込み", value: DeviceProbe.gb(available))
            }
            InfoRow(title: "iOS", value: "\(p.osMajor).\(p.osMinor)")
            InfoRow(title: "機種", value: p.model)
            InfoRow(title: "熱", value: p.thermal.label)
            InfoRow(title: "低電力モード", value: p.lowPowerMode ? "オン" : "オフ")
            InfoRow(title: "Apple Intelligence", value: p.appleIntelligence.label)
        } header: {
            Text("この iPhone")
        } footer: {
            Text("大きなモデルを使うには、署名のときに App ID の「Increased Memory Limit」をオンにすると余裕ができます(README 参照)。")
        }
    }

    // MARK: 入っているモデル

    private var installedSection: some View {
        Section {
            if runtime.installed.isEmpty {
                Text("まだ入っていません。下からダウンロードするか、ファイルから取り込めます。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(runtime.installed) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.name).font(.body.weight(.semibold))
                        Spacer()
                        Text(sourceLabel(m.manifest.source))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    if let spec = m.spec {
                        Text(spec.summary).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Text("\(DeviceProbe.gb(m.manifest.bytes))・動かすのに約 \(DeviceProbe.gb(m.runtimeBytes))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    if m.manifest.source == .bundled {
                        Text(ModelStore.hasKeptCopy(of: m.id)
                             ? "アプリの外にも残してあります。AIなし版で上書きしても消えません(容量は増えません)"
                             : "AIなし版で上書きすると、アプリといっしょに消えます")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    if runtime.crashedModels.contains(m.id) {
                        Button("休ませているのをやめる(もう一度試す)") { runtime.retry(m) }
                            .font(.footnote)
                    }
                }
                .swipeActions {
                    if m.manifest.source != .bundled {
                        Button("消す", role: .destructive) { deleting = m }
                    }
                }
            }
        } header: {
            Text("入っているモデル")
        }
    }

    private func sourceLabel(_ source: ModelManifest.Source) -> String {
        switch source {
        case .bundled: return "IPA に同梱"
        case .downloaded: return "ダウンロード"
        case .imported: return "取り込み"
        case .kept: return "IPA から残したもの"
        }
    }

    // MARK: ダウンロード

    private var downloadSection: some View {
        @Bindable var runtime = runtime
        return Section {
            ForEach(runtime.downloadable) { spec in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(spec.name).font(.body.weight(.semibold))
                        Spacer()
                        Text(DeviceProbe.gb(spec.downloadBytes)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Text(spec.summary).font(.footnote).foregroundStyle(Theme.ink)
                    HStack(spacing: 10) {
                        Text("日本語 " + String(repeating: "●", count: spec.japanese) + String(repeating: "○", count: 5 - spec.japanese))
                        Text("速さ " + String(repeating: "●", count: spec.speed) + String(repeating: "○", count: 5 - spec.speed))
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.pencil)
                    Text("\(spec.speedNote)。おすすめはメモリ \(Int(spec.recommendedRAMGB))GB 以上。\(spec.license)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    downloadControl(spec)
                }
                .padding(.vertical, 4)
            }
            Toggle("モバイル通信でもダウンロードする", isOn: $runtime.allowCellular)
        } header: {
            Text("ダウンロードできるモデル")
        } footer: {
            Text("ダウンロードは初回だけです。入れたあとは通信なしで動きます。画像・音声の部分は取り除いて、文章に使う部分だけを入れます。アプリを上書きでインストールしても消えません。")
        }
    }

    @ViewBuilder
    private func downloadControl(_ spec: ModelSpec) -> some View {
        if let job = runtime.downloader.jobs[spec.id] {
            switch job.phase {
            case .downloading(let file):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: job.fraction).tint(Theme.pencil)
                    HStack {
                        Text("\(file)  \(DeviceProbe.gb(job.received)) / \(DeviceProbe.gb(job.total))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button("やめる") { runtime.downloader.cancel(spec.id) }.font(.caption)
                    }
                    Text("終わるまで、この画面を開いたままにしてください").font(.caption2).foregroundStyle(Theme.muted)
                }
            case .slimming:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("文章に使う部分だけにしています…").font(.caption).foregroundStyle(Theme.muted)
                }
            case .failed(let why):
                VStack(alignment: .leading, spacing: 4) {
                    Text(why).font(.caption).foregroundStyle(Theme.seal)
                    Button("もう一度") {
                        runtime.downloader.clearFailure(spec.id)
                        runtime.download(spec)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        } else {
            Button {
                runtime.download(spec)
            } label: {
                Label("ダウンロード", systemImage: "arrow.down.circle")
            }
            .font(.subheadline.weight(.semibold))
            .tint(Theme.pencil)
            if Double(runtime.profile.physicalMemory) / 1_073_741_824 + 0.5 < spec.recommendedRAMGB {
                Text("この iPhone のメモリ(\(DeviceProbe.gb(runtime.profile.physicalMemory)))では動かないかもしれません")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    // MARK: 取り込み

    private var importSection: some View {
        Section {
            Button {
                importing = true
            } label: {
                Label("ファイル App からフォルダを選んで取り込む", systemImage: "folder.badge.plus")
            }
            Button {
                Task { await runtime.importInbox() }
            } label: {
                Label("「合格ロック › AIModels」を確かめる", systemImage: "tray.and.arrow.down")
            }
        } header: {
            Text("取り込む")
        } footer: {
            Text("MLX 形式のモデルのフォルダ(config.json・tokenizer.json・*.safetensors)を取り込めます。Mac の Finder やファイル App で「この iPhone 内 › 合格ロック › AIModels」に置くと、開いたときに自動で取り込みます。")
        }
    }
}
