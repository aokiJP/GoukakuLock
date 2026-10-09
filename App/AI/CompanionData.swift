import Foundation
import SwiftData
import GoukakuAI

// 相棒AIまわりの SwiftData のモデル。すべてこの iPhone の中だけに置く(どこにも送らない)。
// 列挙型は変更に強いよう、生の文字列で保存する(既存のモデルと同じ方針)。

/// 体験の候補(AIか体験帳が出したもの・本人が書いたもの)
@Model
final class ExperienceIdea {
    enum Status: String {
        case suggested   // 出しただけ
        case planned     // 「やってみる」に入れた
        case someday     // 「いつか」にとっておいた
        case done        // やってみた
        case dismissed   // しまった
    }

    enum Kind: String {
        case today       // 今日の体験
        case someday     // いつかの体験
        case reframe     // コミットを体験にする工夫
    }

    @Attribute(.unique) var id: UUID
    var title: String
    var line: String
    var firstStep: String
    var minutes: Int
    var categoryRaw: String
    /// ai / library / user
    var originRaw: String
    /// 出したAIの名前(体験帳なら「体験帳」)
    var engineName: String
    var statusRaw: String
    /// liked / disliked
    var feedbackRaw: String?
    var kindRaw: String
    var createdAt: Date
    var plannedAt: Date?
    var doneAt: Date?
    /// 工夫のもとになったコミットの名前
    var commitTitle: String?

    init(draft: ExperienceDraft, engineName: String, kind: Kind, status: Status = .suggested,
         commitTitle: String? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.title = draft.title
        self.line = draft.line
        self.firstStep = draft.firstStep
        self.minutes = draft.duration.rawValue
        self.categoryRaw = draft.category.rawValue
        switch draft.origin {
        case .ai: self.originRaw = "ai"
        case .library: self.originRaw = "library"
        case .user: self.originRaw = "user"
        }
        self.engineName = engineName
        self.statusRaw = status.rawValue
        self.feedbackRaw = nil
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.commitTitle = commitTitle
    }

    var category: ExperienceCategory { ExperienceCategory(rawValue: categoryRaw) ?? .first }
    var duration: DurationBucket { DurationBucket(rawValue: minutes) ?? .nearest(minutes: minutes) }
    var status: Status {
        get { Status(rawValue: statusRaw) ?? .suggested }
        set { statusRaw = newValue.rawValue }
    }
    var kind: Kind { Kind(rawValue: kindRaw) ?? .today }
    var isFromAI: Bool { originRaw == "ai" }
    var liked: Bool { feedbackRaw == "liked" }
    var disliked: Bool { feedbackRaw == "disliked" }
}

/// やってみた体験の記録(と、相棒からの返事)
@Model
final class ExperienceLog {
    enum Source: String {
        case experience   // 体験タブから
        case checkIn      // コミットのチェックインから
    }

    @Attribute(.unique) var id: UUID
    var ideaID: UUID?
    var title: String
    var note: String
    var feelingRaw: String?
    var categoryRaw: String
    var at: Date
    var reply: String?
    var question: String?
    var replyFromAI: Bool
    var engineName: String?
    var sourceRaw: String
    var achievementID: UUID?
    /// AIが「覚えておきたい」と言ったこと(本人が決めるまで保留)
    var noteCandidate: String?

    init(title: String, note: String, feeling: Feeling?, category: ExperienceCategory, source: Source,
         ideaID: UUID? = nil, achievementID: UUID? = nil, at: Date = Date()) {
        self.id = UUID()
        self.ideaID = ideaID
        self.title = title
        self.note = note
        self.feelingRaw = feeling?.rawValue
        self.categoryRaw = category.rawValue
        self.at = at
        self.reply = nil
        self.question = nil
        self.replyFromAI = false
        self.engineName = nil
        self.sourceRaw = source.rawValue
        self.achievementID = achievementID
        self.noteCandidate = nil
    }

    var category: ExperienceCategory { ExperienceCategory(rawValue: categoryRaw) ?? .first }
    var feeling: Feeling? { feelingRaw.flatMap(Feeling.init(rawValue:)) }
    var source: Source { Source(rawValue: sourceRaw) ?? .experience }
}

/// 相棒が覚えていること(本人が書いたこと・AIのメモを本人が「覚える」にしたこと)
@Model
final class CompanionNote {
    @Attribute(.unique) var id: UUID
    var text: String
    /// user / ai
    var sourceRaw: String
    var createdAt: Date

    init(text: String, fromAI: Bool, createdAt: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.sourceRaw = fromAI ? "ai" : "user"
        self.createdAt = createdAt
    }

    var fromAI: Bool { sourceRaw == "ai" }
}

/// 相棒との会話
@Model
final class CompanionMessage {
    @Attribute(.unique) var id: UUID
    /// user / assistant
    var roleRaw: String
    var text: String
    var at: Date
    var engineName: String?

    init(role: ChatTurn.Role, text: String, engineName: String?, at: Date = Date()) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.at = at
        self.engineName = engineName
    }

    var role: ChatTurn.Role { ChatTurn.Role(rawValue: roleRaw) ?? .user }
}
