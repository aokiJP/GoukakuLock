import SwiftUI
import GoukakuAI

/// やってみた体験を記録する。書くのは一言でも、書かなくてもいい(体験は義務ではないので)。
/// 記録すると、相棒が書いたことの具体的なところにふれて返事をし、問いを1つ添える
struct ExperienceLogSheet: View {
    @Environment(CompanionModel.self) private var companion
    @Environment(\.dismiss) private var dismiss
    let target: LogTarget
    @State private var note = ""
    @State private var feeling: Feeling?
    @State private var saved: ExperienceLog?
    @FocusState private var focused: Bool

    private var idea: ExperienceIdea {
        switch target {
        case .idea(let idea): return idea
        }
    }

    var body: some View {
        Group {
            if let saved {
                done(saved)
            } else {
                form
            }
        }
        .navigationTitle("やってみた")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    CategoryStamp(category: idea.category)
                    Text(idea.title)
                        .font(Theme.heading(.title3))
                        .foregroundStyle(Theme.ink)
                }
            }
            Section {
                TextField("例:空の色がオレンジから紫に変わった", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
            } header: {
                Text("どうだった?(一言でも、書かなくても)")
            }
            Section("気持ち") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Feeling.allCases, id: \.self) { f in
                        ChoiceChip(title: f.label, symbol: f.symbol, selected: feeling == f) {
                            feeling = feeling == f ? nil : f
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("記録する") {
                focused = false
                let log = companion.logExperience(idea: idea, title: idea.title, note: note, feeling: feeling,
                                                  category: idea.category)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { saved = log }
            }
            .buttonStyle(SealButtonStyle())
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sensoryFeedback(.selection, trigger: feeling)
    }

    private func done(_ log: ExperienceLog) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    CategoryStamp(category: log.category, filled: true, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("体験の地図に、ひとつ増えました")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                        Text(log.title)
                            .font(Theme.heading(.title3))
                            .foregroundStyle(Theme.ink)
                    }
                }
                if let reply = log.reply {
                    PencilNote(text: reply, caption: log.replyFromAI ? "相棒(\(log.engineName ?? "AI"))" : "相棒")
                    if let question = log.question {
                        PencilNote(text: question, caption: "問い")
                    }
                } else {
                    PencilNote(text: companion.reflectionPreview, caption: "相棒", writing: true)
                }
                if let candidate = log.noteCandidate {
                    NoteCandidateRow(text: candidate,
                                     onAccept: { withAnimation { companion.acceptNote(from: log) } },
                                     onDecline: { withAnimation { companion.declineNote(from: log) } })
                }
                Button("閉じる") { dismiss() }
                    .buttonStyle(SealButtonStyle())
                    .padding(.top, 8)
            }
            .padding()
        }
        .background(Theme.paper)
        .sensoryFeedback(.success, trigger: log.id)
    }
}
