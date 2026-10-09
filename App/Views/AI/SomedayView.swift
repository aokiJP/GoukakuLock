import SwiftUI
import GoukakuAI

/// いつかの体験:人生のどこかで味わってみたいことを、相棒と一緒に集める。
/// 「やらなきゃ」のリストではなく、思い出したときに開く地図のようなもの。期限はつけない
struct SomedayView: View {
    @Environment(CompanionModel.self) private var companion
    @State private var theme = ""
    @State private var committing: ExperienceIdea?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("人生のどこかで、味わってみたいこと。")
                        .font(Theme.heading(.title3))
                        .foregroundStyle(Theme.ink)
                    Text("大きくても小さくてもかまいません。期限はつけず、思い出したときに最初の一歩だけ。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    TextField("いま気になっていること(任意)例:旅・音楽・人", text: $theme)
                        .textFieldStyle(.roundedBorder)
                    if companion.isDreaming {
                        WritingCard(preview: companion.somedayPreview)
                    } else {
                        Button {
                            companion.dream(theme: theme)
                        } label: {
                            Label("いつかの体験を考える", systemImage: "map")
                        }
                        .buttonStyle(SealButtonStyle())
                    }
                    if let notice = companion.notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                ForEach(companion.somedayCandidates) { idea in
                    ExperienceCard(idea: idea) {
                        HStack(spacing: 10) {
                            Button("とっておく") { withAnimation { companion.keepForSomeday(idea) } }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.pencil)
                            Button("しまう") { withAnimation { companion.dismiss(idea) } }
                                .buttonStyle(.bordered)
                                .tint(Theme.muted)
                            Spacer()
                            FeedbackButtons(idea: idea) { liked in companion.feedback(idea, liked: liked) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                let kept = companion.someday
                if !kept.isEmpty {
                    SectionHeading(title: "とってある体験", detail: "最初の一歩だけ、今日やってみることもできます。")
                    ForEach(kept) { idea in
                        ExperienceCard(idea: idea) {
                            HStack(spacing: 10) {
                                Button("一歩目をやってみる") { withAnimation { companion.planFirstStep(of: idea) } }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.seal)
                                Menu {
                                    Button {
                                        committing = idea
                                    } label: {
                                        Label("コミットにして続ける", systemImage: "checkmark.seal")
                                    }
                                    Button(role: .destructive) {
                                        withAnimation { companion.dismiss(idea) }
                                    } label: {
                                        Label("しまう", systemImage: "archivebox")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .tint(Theme.pencil)
                                Spacer()
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("いつかの体験")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $committing) { idea in
            CommitEditView(draft: HabitDraft.from(experience: idea))
        }
    }
}

extension HabitDraft {
    /// 体験から、続けるコミットの下書きを作る(中身は本人が決めて保存する)
    static func from(experience idea: ExperienceIdea) -> HabitDraft {
        var draft = HabitDraft()
        draft.title = idea.firstStep.isEmpty ? idea.title : "\(idea.title)(\(idea.firstStep))"
        draft.minimumTitle = idea.firstStep.isEmpty ? "" : String(idea.firstStep.prefix(30))
        draft.goalNote = idea.title
        draft.isRequired = false   // 体験は義務ではないので、まずは任意(記録だけ)。必須にするかは本人が決める
        return draft
    }
}
