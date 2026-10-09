import SwiftUI
import GoukakuAI

/// 育ち:体験の地図(8つの区画)と、相棒がこの人をどれだけ知っているか。
/// あなたが体験するほど地図が埋まり、覚えてもらうほど相棒の提案があなたに合っていく。
/// 他の人との比較や、連続の記録はない
struct GrowthView: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionModel.self) private var companion
    @State private var newNote = ""
    @State private var confirmForget = false

    var body: some View {
        let growth = companion.growth
        List {
            Section {
                mapGrid(growth)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text("体験の地図")
            } footer: {
                if let next = growth.unexplored.first {
                    Text("まだの区画:\(growth.unexplored.map(\.label).joined(separator: "・"))。次は「\(next.label)」の体験も、気が向いたらどうぞ。")
                } else {
                    Text("8つの区画すべてで体験しました。")
                }
            }

            insightSection

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("相棒の理解")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text(growth.level.label)
                            .font(Theme.heading(.title3))
                            .foregroundStyle(Theme.pencil)
                    }
                    ProgressView(value: growth.progressToNext)
                        .tint(Theme.pencil)
                    if let left = growth.pointsToNext, let next = growth.level.next {
                        Text("「\(next.label)」まで、あと \(left)。覚えてもらう・体験する・いいね/ちがうで育ちます。")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 4)
                InfoRow(title: "やってみた体験", value: "\(growth.totalExperiences)")
                InfoRow(title: "一緒に過ごした日", value: "\(growth.daysTogether)日")
                InfoRow(title: "いいね/ちがう", value: "\(growth.liked) / \(growth.disliked)")
            } header: {
                Text("相棒")
            }

            Section {
                HStack {
                    TextField("例:英語を勉強している・散歩が好き", text: $newNote)
                    Button("覚えてもらう") {
                        companion.rememberIntroduction(newNote)
                        newNote = ""
                    }
                    .disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(Theme.pencil)
                }
                let notes = companion.notes
                if notes.isEmpty {
                    Text("まだ何も覚えていません。好きなこと・やってみたいことを書くと、提案があなたに合っていきます。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(notes) { note in
                    HStack {
                        Image(systemName: note.fromAI ? "pencil.line" : "person")
                            .foregroundStyle(Theme.pencil)
                            .frame(width: 22)
                        Text(note.text)
                        Spacer()
                        Text(note.fromAI ? "相棒のメモ" : "あなた")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { companion.forget(notes[i]) }
                }
            } header: {
                Text("相棒が知っているあなた")
            } footer: {
                Text("ここにあることだけを、相棒は覚えています。左にスワイプで忘れさせられます。どこにも送りません。")
            }

            if !companion.notes.isEmpty {
                Section {
                    Button("すべて忘れてもらう", role: .destructive) { confirmForget = true }
                }
            }
        }
        .navigationTitle("育ち")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("相棒が覚えていることを、すべて忘れてもらいますか?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("すべて忘れる", role: .destructive) { companion.forgetAll() }
        }
    }

    /// 相棒の気づき:やってみた体験の記録から、相棒が気づいたこと(本人が頼んだときだけ書く)
    @ViewBuilder
    private var insightSection: some View {
        let settings = model.settings
        let count = companion.experienceLogs.count
        Section {
            if companion.isThinkingInsight {
                PencilNote(text: companion.insightPreview, caption: "相棒の気づき", writing: true)
            } else if !settings.companionInsight.isEmpty {
                PencilNote(text: settings.companionInsight,
                           caption: "相棒の気づき" + (settings.companionInsightAt.map { "(\(Fmt.clock($0)))" } ?? "")
                               + (settings.companionInsightFromAI ? "" : "・体験帳"))
            }
            if count >= CompanionModel.insightMinimum {
                Button {
                    companion.refreshInsight()
                } label: {
                    Label(settings.companionInsight.isEmpty ? "相棒の気づきを聞く" : "いまの記録で、もう一度聞く",
                          systemImage: "lightbulb")
                }
                .tint(Theme.pencil)
                .disabled(companion.isThinkingInsight)
            } else {
                Text("やってみた体験が\(CompanionModel.insightMinimum)つたまると、相棒が記録から気づいたことを書きます(あと\(CompanionModel.insightMinimum - count)つ)。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text("相棒の気づき")
        } footer: {
            Text("気づきは、あなたが頼んだときだけ、相棒が自分の言葉で書きます。")
        }
    }

    private func mapGrid(_ growth: GrowthSnapshot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(ExperienceCategory.allCases, id: \.self) { category in
                let count = growth.counts[category] ?? 0
                VStack(spacing: 6) {
                    ZStack {
                        if count == 0 {
                            Circle()
                                .strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        } else {
                            Circle().fill(Theme.pencil.opacity(min(0.95, 0.35 + Double(count) * 0.12)))
                        }
                        Image(systemName: category.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(count == 0 ? Theme.muted : Theme.paper)
                    }
                    .frame(width: 48, height: 48)
                    Text(category.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(count == 0 ? category.blurb : "\(count)回")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
