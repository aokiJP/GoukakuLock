import SwiftUI
import GoukakuCore
import GoukakuAI

/// ホームの「相棒から」:今日のコミットを、やらされる作業ではなく、ちょっと楽しみな体験にする工夫を聞ける。
/// コミットがない日・終わった日は、体験タブへの入口になる
struct CompanionHomeCard: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionModel.self) private var companion
    @Environment(AIRuntime.self) private var runtime
    @Environment(NotificationRouter.self) private var router

    var body: some View {
        let today = model.today
        let target = today?.pendingRequired.first ?? today.flatMap { day in
            (day.required + day.optional).first { !day.isDone($0.id) }
        }
        RuledBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("相棒から", systemImage: "pencil.line")
                        .font(Theme.heading(.headline))
                        .foregroundStyle(Theme.pencil)
                    Spacer()
                    Text(runtime.engineInfo.name)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if let habit = target, !(today?.isDone(habit.id) ?? false) {
                    reframeBlock(habit)
                } else {
                    Text(companion.planned.isEmpty
                         ? "今日のコミットはおしまい。残りの時間で、どんな体験をしてみる?"
                         : "「やってみる」に\(companion.planned.count)つ入っています。気が向いたものからどうぞ。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    router.tab = .experience
                } label: {
                    Label("体験タブで、ほかの体験を見つける", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.pencil)
            }
        }
    }

    @ViewBuilder
    private func reframeBlock(_ habit: HabitSnapshot) -> some View {
        let ideas = companion.reframes[habit.id] ?? []
        Text("「\(habit.title)」を、ちょっと楽しみな体験にするなら:")
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(ideas) { idea in
            PencilNote(text: idea.title + (idea.line.isEmpty ? "" : "\n" + idea.line)
                       + (idea.firstStep.isEmpty ? "" : "\n→ " + idea.firstStep))
        }
        if companion.reframing == habit.id {
            PencilNote(text: "", writing: true)
        } else {
            Button {
                companion.reframe(habit)
            } label: {
                Label(ideas.isEmpty ? "体験にする工夫を聞く" : "ほかの工夫も聞く", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .tint(Theme.pencil)
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("companion.reframe")
        }
    }
}
