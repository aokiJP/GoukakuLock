import SwiftUI
import GoukakuAI

// 相棒AIの見た目の部品。
// 相棒の言葉は「鉛筆の書き込み」(藍色・左に余白の線)で書き、採点の赤ペン(朱)とは分ける。
// AIは体験を誘うだけで、丸もバツもつけない。

/// 相棒の書き込み(余白の鉛筆メモ)
struct PencilNote: View {
    var text: String
    var caption: String?
    var writing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.pencil.opacity(0.45))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                if let caption {
                    Label(caption, systemImage: "pencil.line")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.pencil.opacity(0.8))
                }
                Text(text.isEmpty && writing ? "…" : text)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Theme.pencil)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if writing {
                    WritingDots()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// 書いている途中の印(鉛筆の点)
struct WritingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.pencil.opacity(reduceMotion || i == step ? 0.8 : 0.25))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .accessibilityLabel("書いています")
    }
}

/// いま使っているAI(押すと AI の設定へ)
struct EngineBadge: View {
    @Environment(AIRuntime.self) private var runtime

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(runtime.statusLine)
                .lineLimit(1)
            if runtime.phase == .loading {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(runtime.usesAI ? Theme.pencil : Theme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.paperSunken))
        .overlay(Capsule().strokeBorder(Theme.rule))
    }

    private var icon: String {
        switch runtime.engineInfo.kind {
        case .mlx: return "cpu"
        case .apple: return "apple.logo"
        case .rules: return "book.closed"
        }
    }
}

/// 体験の種類の印(小さな丸に記号)
struct CategoryStamp: View {
    var category: ExperienceCategory
    var filled = false
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(filled ? Theme.pencil : Theme.paper)
            Circle().strokeBorder(Theme.pencil.opacity(filled ? 0 : 0.5), lineWidth: 1.2)
            Image(systemName: category.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(filled ? Theme.paper : Theme.pencil)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 選ぶチップ(いまの自分・気持ち)
struct ChoiceChip: View {
    var title: String
    var symbol: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .background(Capsule().fill(selected ? Theme.pencil : Theme.paperSunken))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.rule))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// いまの自分(使える時間・場所・調子)
struct ContextChips: View {
    @Environment(CompanionModel.self) private var companion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("使える時間") {
                ForEach(TimeBudget.allCases, id: \.self) { b in
                    ChoiceChip(title: b.label, symbol: nil, selected: companion.budget == b) { companion.budget = b }
                }
            }
            row("いる場所") {
                ForEach(Place.allCases, id: \.self) { p in
                    ChoiceChip(title: p.label, symbol: nil, selected: companion.place == p) { companion.place = p }
                }
            }
            row("いまの調子") {
                ForEach(Mood.allCases, id: \.self) { m in
                    ChoiceChip(title: m.label, symbol: nil, selected: companion.mood == m) { companion.mood = m }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: "\(companion.budget)\(companion.place)\(companion.mood)")
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }
}

/// 体験のカード(提案・やってみる・いつか)
struct ExperienceCard<Actions: View>: View {
    var idea: ExperienceIdea
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CategoryStamp(category: idea.category, filled: idea.status == .done)
                VStack(alignment: .leading, spacing: 4) {
                    Text(idea.title)
                        .font(Theme.heading(.headline))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !idea.line.isEmpty {
                        Text(idea.line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if !idea.firstStep.isEmpty {
                Label {
                    Text("はじめ方:\(idea.firstStep)")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Text(idea.category.label)
                if idea.kind != .someday { Text(idea.duration.label) }
                Text(idea.isFromAI ? "相棒" : (idea.originRaw == "user" ? "自分で" : "体験帳"))
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            actions
        }
        .padding(14)
        .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule))
        .accessibilityElement(children: .contain)
    }
}

/// いいね・ちがう(提案がこの人に合っていくための手ごたえ)
struct FeedbackButtons: View {
    var idea: ExperienceIdea
    var onFeedback: (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { onFeedback(true) } label: {
                Image(systemName: idea.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .accessibilityLabel("いいね")
            Button { onFeedback(false) } label: {
                Image(systemName: idea.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .accessibilityLabel("ちがう")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.pencil)
        .sensoryFeedback(.selection, trigger: idea.feedbackRaw)
    }
}

/// 生成中のカード(書いている名前が見える)
struct WritingCard: View {
    var preview: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .strokeBorder(Theme.pencil.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(preview.isEmpty ? "考えています" : preview)
                    .font(Theme.heading(.headline))
                    .foregroundStyle(Theme.pencil.opacity(preview.isEmpty ? 0.6 : 1))
                    .contentTransition(.opacity)
                WritingDots()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.pencil.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// 見出し(体験タブの各まとまり)
struct SectionHeading: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.heading(.headline))
                .foregroundStyle(Theme.ink)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 覚えるかどうかを本人が決める(AIのメモ)
struct NoteCandidateRow: View {
    var text: String
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("相棒が覚えておきたいこと:「\(text)」", systemImage: "bookmark")
                .font(.footnote)
                .foregroundStyle(Theme.pencil)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("覚えてもらう", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.pencil)
                Button("覚えない", action: onDecline)
                    .buttonStyle(.bordered)
                    .tint(Theme.muted)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .background(Theme.pencil.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
