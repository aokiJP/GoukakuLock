import SwiftUI
import GoukakuAI

/// 体験タブ:相棒AIと、人生の中でどんな体験ができるかを一緒に見つける。
/// 提案は義務ではなく体験として。決めるのは本人。AIの言葉はしばらない
struct CompanionView: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionModel.self) private var companion
    @Environment(AIRuntime.self) private var runtime
    @State private var logging: LogTarget?
    @State private var addingOwn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    discoverSection
                    plannedSection
                    recentSection
                    moreSection
                    privacyNote
                }
                .padding()
            }
            .background(Theme.paper)
            .navigationTitle("体験")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label("AI", systemImage: "cpu")
                    }
                }
            }
            .sheet(item: $logging) { target in
                NavigationStack {
                    ExperienceLogSheet(target: target)
                }
            }
            .sheet(isPresented: $addingOwn) {
                NavigationStack {
                    OwnIdeaSheet()
                }
                .presentationDetents([.medium])
            }
            .task {
                await runtime.importInbox()
            }
        }
    }

    // MARK: 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                AISettingsView()
            } label: {
                EngineBadge()
            }
            .buttonStyle(.plain)
            Text("人生の中で、どんな体験ができるだろう。")
                .font(Theme.heading(.title3))
                .foregroundStyle(Theme.ink)
            Text("相棒が、今のあなたに合いそうな体験を誘います。やるかどうかは、あなたが決めます。")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 見つける

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContextChips()
            if companion.isSuggesting {
                Button {
                    companion.cancelSuggest()
                } label: {
                    Label("考えるのをやめる", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.muted)
            } else {
                Button {
                    companion.suggest()
                } label: {
                    Label(companion.batch.isEmpty ? "体験を3つ見つける" : "ほかの体験を見つける", systemImage: "sparkles")
                }
                .buttonStyle(SealButtonStyle())
                .accessibilityIdentifier("companion.suggest")
            }
            if let notice = companion.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(companion.batch.filter { $0.status == .suggested }) { idea in
                ExperienceCard(idea: idea) {
                    HStack(spacing: 10) {
                        Button("やってみる") { withAnimation { companion.plan(idea) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.seal)
                        Button("いつか") { withAnimation { companion.keepForSomeday(idea) } }
                            .buttonStyle(.bordered)
                            .tint(Theme.pencil)
                        Spacer()
                        FeedbackButtons(idea: idea) { liked in companion.feedback(idea, liked: liked) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if companion.isSuggesting {
                WritingCard(preview: companion.suggestionPreview)
            }
        }
        .animation(.easeOut(duration: 0.25), value: companion.batch.map(\.id))
    }

    // MARK: やってみる

    @ViewBuilder private var plannedSection: some View {
        let planned = companion.planned
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "やってみる", detail: planned.isEmpty ? "気になった体験を「やってみる」に入れておけます。" : nil)
                Spacer()
                Button {
                    addingOwn = true
                } label: {
                    Label("自分で書く", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.pencil)
            }
            ForEach(planned) { idea in
                ExperienceCard(idea: idea) {
                    HStack(spacing: 10) {
                        Button {
                            logging = .idea(idea)
                        } label: {
                            Label("やってみた", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.seal)
                        Button("しまう") { withAnimation { companion.dismiss(idea) } }
                            .buttonStyle(.bordered)
                            .tint(Theme.muted)
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    // MARK: やってみた体験と、相棒の返事

    @ViewBuilder private var recentSection: some View {
        let logs = companion.logs.filter { $0.source == .experience }.prefix(3)
        if !logs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "やってみた体験")
                ForEach(Array(logs)) { log in
                    LogEntryView(log: log)
                }
                NavigationLink {
                    ExperienceHistoryView()
                } label: {
                    Label("すべての体験", systemImage: "list.bullet")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.pencil)
            }
        }
    }

    // MARK: もっと

    private var moreSection: some View {
        VStack(spacing: 10) {
            NavigationLink {
                CompanionChatView()
            } label: {
                MoreRow(symbol: "bubble.left.and.text.bubble.right", title: "相棒と話す",
                        detail: runtime.usesAI ? "どんな体験をしてみたいか、話しながら考える" : "AIのモデルを入れると話せます")
            }
            NavigationLink {
                SomedayView()
            } label: {
                MoreRow(symbol: "map", title: "いつかの体験",
                        detail: companion.someday.isEmpty ? "人生のどこかで味わってみたいことを集める" : "\(companion.someday.count)つとってあります")
            }
            NavigationLink {
                GrowthView()
            } label: {
                let growth = companion.growth
                MoreRow(symbol: "leaf.arrow.triangle.circlepath", title: "育ち",
                        detail: "体験の地図 \(growth.explored)/8・相棒の理解「\(growth.level.label)」")
            }
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        Text("相棒はこの iPhone の中だけで動きます。書いたことはどこにも送りません。")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}

/// 記録する体験(提案から・自分で)
enum LogTarget: Identifiable {
    case idea(ExperienceIdea)

    var id: UUID {
        switch self {
        case .idea(let idea): return idea.id
        }
    }
}

/// 「もっと」の1行
struct MoreRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.pencil)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .padding(14)
        .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule))
    }
}

/// やってみた体験1つと、相棒の返事
struct LogEntryView: View {
    @Environment(CompanionModel.self) private var companion
    var log: ExperienceLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                CategoryStamp(category: log.category, filled: true, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Text(Fmt.clock(log.at))
                        if let feeling = log.feeling { Text(feeling.label) }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }
            }
            if !log.note.isEmpty {
                Text(log.note)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = log.reply {
                PencilNote(text: reply + (log.question.map { "\n\($0)" } ?? ""),
                           caption: log.replyFromAI ? "相棒(\(log.engineName ?? "AI"))" : "相棒")
            } else if companion.reflecting == log.id {
                PencilNote(text: companion.reflectionPreview, caption: "相棒", writing: true)
            }
            if let candidate = log.noteCandidate {
                NoteCandidateRow(text: candidate,
                                 onAccept: { withAnimation { companion.acceptNote(from: log) } },
                                 onDecline: { withAnimation { companion.declineNote(from: log) } })
            }
        }
        .padding(14)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule))
    }
}

/// やってみた体験の一覧
struct ExperienceHistoryView: View {
    @Environment(CompanionModel.self) private var companion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                let logs = companion.logs
                if logs.isEmpty {
                    Text("まだ体験の記録はありません。").foregroundStyle(Theme.muted)
                }
                ForEach(logs) { log in
                    LogEntryView(log: log)
                }
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("すべての体験")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 自分で考えた体験を「やってみる」に入れる
struct OwnIdeaSheet: View {
    @Environment(CompanionModel.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category: ExperienceCategory = .first

    var body: some View {
        Form {
            Section {
                TextField("例:屋上で夕焼けを見る", text: $title, axis: .vertical)
            } header: {
                Text("やってみたい体験")
            }
            Section("種類") {
                Picker("種類", selection: $category) {
                    ForEach(ExperienceCategory.allCases, id: \.self) { c in
                        Label(c.label, systemImage: c.symbol).tag(c)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("自分で書く")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("入れる") {
                    companion.addOwnIdea(title: title.trimmingCharacters(in: .whitespacesAndNewlines), category: category)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
