import Foundation
import SwiftData
import GoukakuCore

// 本体だけが使う SwiftData のモデル(仕様書 第15.3節)。
// 判定に必要なものは state.json(SharedState)にあり、ここは履歴・詳細・設定を持つ。
// 列挙型は変更に強いよう、生の文字列で保存する。

/// コミット(習慣)の詳細。state.json の HabitSnapshot はここから作る写し。
@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var title: String
    /// 自分用の合格ライン
    var criteriaNote: String
    /// 最小版。空なら最小版なし
    var minimumTitle: String
    /// 予定する曜日(1=日 … 7=土)
    var weekdays: [Int]
    var isRequired: Bool
    var methodRaw: String
    var targetMinutes: Int?
    var activeFromRaw: String
    var activeUntilRaw: String?
    var sortOrder: Int
    /// 本当の目標(資格・試験日など)のメモ
    var goalNote: String
    var goalDate: Date?
    var createdAt: Date
    /// タイマー:離れたら0からやり直す(厳格モード)
    var strictTimer: Bool = false
    /// タイマー・最小版の分数
    var minimumMinutes: Int = 5

    init(id: UUID = UUID(), title: String, criteriaNote: String = "", minimumTitle: String = "",
         weekdays: [Int] = Array(1...7), isRequired: Bool = true,
         method: VerificationMethod = .selfReport, targetMinutes: Int? = nil,
         activeFrom: CycleID, activeUntil: CycleID? = nil, sortOrder: Int = 0,
         goalNote: String = "", goalDate: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.criteriaNote = criteriaNote
        self.minimumTitle = minimumTitle
        self.weekdays = weekdays
        self.isRequired = isRequired
        self.methodRaw = method.rawValue
        self.targetMinutes = targetMinutes
        self.activeFromRaw = activeFrom.description
        self.activeUntilRaw = activeUntil?.description
        self.sortOrder = sortOrder
        self.goalNote = goalNote
        self.goalDate = goalDate
        self.createdAt = createdAt
    }

    var method: VerificationMethod { VerificationMethod(rawValue: methodRaw) ?? .selfReport }
    var activeFrom: CycleID? { CycleID(activeFromRaw) }
    var activeUntil: CycleID? { activeUntilRaw.flatMap(CycleID.init) }

    var snapshot: HabitSnapshot {
        HabitSnapshot(id: id, title: title,
                      minimumTitle: minimumTitle.isEmpty ? nil : minimumTitle,
                      weekdays: Set(weekdays), isRequired: isRequired, method: method,
                      targetMinutes: targetMinutes,
                      activeFrom: activeFrom ?? CycleID(year: 2000, month: 1, day: 1),
                      activeUntil: activeUntil)
    }

    /// 終了済み(削除して、もう有効なサイクルが来ない)か
    func hasEnded(asOf cycle: CycleID) -> Bool {
        guard let until = activeUntil else { return false }
        return cycle >= until
    }
}

/// チェックイン1回分の記録(一言メモなど)。achievementID は state.json の Achievement.id と同じ。
@Model
final class CheckIn {
    @Attribute(.unique) var achievementID: UUID
    var cycleRaw: String
    var habitID: UUID
    /// 記録した時点のコミット名
    var habitTitle: String
    var kindRaw: String
    var methodRaw: String
    var note: String
    var at: Date
    var undoneAt: Date?
    /// 証拠写真のファイル名(Application Support/evidence/)
    var evidenceFileName: String? = nil
    /// タイマーで数えた秒
    var timerSeconds: Int? = nil

    init(achievement: Achievement, habitTitle: String, method: VerificationMethod, note: String) {
        self.achievementID = achievement.id
        self.cycleRaw = achievement.cycle.description
        self.habitID = achievement.habitID
        self.habitTitle = habitTitle
        self.kindRaw = achievement.kind.rawValue
        self.methodRaw = method.rawValue
        self.note = note
        self.at = achievement.at
        self.undoneAt = nil
    }

    var isMinimum: Bool { kindRaw == Achievement.Kind.minimum.rawValue }
}

/// 終わったサイクルの結果(確定したら書き換えない。却下などは別の記録で表す)
@Model
final class CycleRecord {
    @Attribute(.unique) var cycleRaw: String
    var outcomeRaw: String
    var finalizedAt: Date
    var emergencyCount: Int

    init(cycle: CycleID, outcome: CycleOutcome, finalizedAt: Date, emergencyCount: Int) {
        self.cycleRaw = cycle.description
        self.outcomeRaw = outcome.rawValue
        self.finalizedAt = finalizedAt
        self.emergencyCount = emergencyCount
    }

    var cycle: CycleID? { CycleID(cycleRaw) }
    var outcome: CycleOutcome { CycleOutcome(rawValue: outcomeRaw) ?? .missed }
}

/// 回避ログを含む出来事の記録(追記のみ)
@Model
final class EventLog {
    var at: Date
    var kind: String
    var detail: String

    init(at: Date, kind: String, detail: String) {
        self.at = at
        self.kind = kind
        self.detail = detail
    }
}

/// 翌サイクルから効く設定変更の待ち行列(仕様書 第7.5節)
@Model
final class PendingChange {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var effectiveCycleRaw: String
    var summary: String
    var payload: Data
    /// waiting / applied / cancelled
    var statusRaw: String
    var resolvedAt: Date?

    init(id: UUID = UUID(), createdAt: Date, effectiveCycle: CycleID, summary: String, payload: Data) {
        self.id = id
        self.createdAt = createdAt
        self.effectiveCycleRaw = effectiveCycle.description
        self.summary = summary
        self.payload = payload
        self.statusRaw = "waiting"
        self.resolvedAt = nil
    }

    var effectiveCycle: CycleID? { CycleID(effectiveCycleRaw) }
    var isWaiting: Bool { statusRaw == "waiting" }
}

/// 緊急解除の記録(回数は「解除が始まった回数」で数える)
@Model
final class EmergencyRecord {
    var requestedAt: Date
    var startsAt: Date
    var endsAt: Date
    var cancelledAt: Date?

    init(window: EmergencyWindow) {
        self.requestedAt = window.requestedAt
        self.startsAt = window.startsAt
        self.endsAt = window.endsAt
        self.cancelledAt = window.cancelledAt
    }

    /// 解除が始まったか(待機中に取り消したものは数えない)
    func didStart(asOf now: Date) -> Bool {
        guard startsAt <= now else { return false }
        if let cancelledAt { return cancelledAt > startsAt }
        return true
    }
}

/// 本体アプリの設定(1件だけ)
@Model
final class AppSettings {
    /// リマインドの時刻(0:00 からの分)
    var reminderMinutes: [Int]
    var quietStartMinute: Int
    var quietEndMinute: Int
    /// 最小版を使える回数(週)
    var minimumWeeklyQuota: Int
    /// 休養日を置ける日数(週)
    var restWeeklyQuota: Int
    var lastFinalizedCycleRaw: String?
    /// 時刻改ざん検知の基準(ClockAnchor の JSON)
    var clockAnchorData: Data?
    /// 前回 DeviceActivity に登録した内容の指紋(変わっていなければ登録し直さない)
    var registrationFingerprint: String?
    /// targets.json を書き換えるたびに増やす(指紋に使う)
    var targetsRevision: Int
    /// 最後に確かめたとき Screen Time の許可があったか(外れた瞬間だけ記録するため)
    var lastAuthApproved: Bool
    var onboardingCompletedAt: Date?
    /// デバッグ用:緊急解除を短くする(待機1分・解除15分)
    var debugShortEmergency: Bool
    /// はなまるを出した最後のサイクル(同じ日に二度出さない)
    var lastCelebratedCycleRaw: String? = nil
    /// 「一段上げる」の提案を閉じた日
    var rampDismissedAt: Date? = nil
    /// 使用時間で判定するアプリの選び直しのたびに増やす(区間の登録し直しの指紋に使う)
    var usageRevision: Int = 0
    /// 相棒AI:いまの自分(使える時間|場所|調子)
    var companionContextRaw: String = ""
    /// 相棒AI:はじめて会った日(育ちの「一緒に過ごした日数」)
    var companionStartedAt: Date? = nil
    /// 相棒AI:チェックインのあとにひとこと返す
    var companionReflectAfterCheckIn: Bool = true
    /// 相棒AI:体験の記録から相棒が気づいたこと(育ちの画面)と、その日時・AIが書いたか
    var companionInsight: String = ""
    var companionInsightAt: Date? = nil
    var companionInsightFromAI: Bool = false

    init() {
        self.reminderMinutes = [12 * 60, 20 * 60]
        self.quietStartMinute = 23 * 60
        self.quietEndMinute = 7 * 60
        self.minimumWeeklyQuota = 2
        self.restWeeklyQuota = 1
        self.lastFinalizedCycleRaw = nil
        self.clockAnchorData = nil
        self.registrationFingerprint = nil
        self.targetsRevision = 0
        self.lastAuthApproved = true
        self.onboardingCompletedAt = nil
        self.debugShortEmergency = false
    }

    var reminderSettings: ReminderSettings {
        ReminderSettings(minutesOfDay: reminderMinutes.sorted(), quietStartMinute: quietStartMinute,
                         quietEndMinute: quietEndMinute, maxPerDay: 4)
    }

    var lastFinalizedCycle: CycleID? {
        get { lastFinalizedCycleRaw.flatMap(CycleID.init) }
        set { lastFinalizedCycleRaw = newValue?.description }
    }
}

/// 週に1回のふり返り(仕様書 第8章:3つだけ聞く)
@Model
final class WeeklyReview {
    /// ふり返った週(月曜のサイクル)
    @Attribute(.unique) var weekStartRaw: String
    var worked: String
    /// easy / right / hard
    var difficulty: String
    var change: String
    var createdAt: Date

    init(weekStart: CycleID, worked: String, difficulty: String, change: String, createdAt: Date = Date()) {
        self.weekStartRaw = weekStart.description
        self.worked = worked
        self.difficulty = difficulty
        self.change = change
        self.createdAt = createdAt
    }
}

enum Persistence {
    /// Schema は Sendable でないので、共有の static let にせず毎回作る
    static var schema: Schema {
        Schema([
            Habit.self, CheckIn.self, CycleRecord.self, EventLog.self,
            PendingChange.self, EmergencyRecord.self, AppSettings.self, WeeklyReview.self,
            ExperienceIdea.self, ExperienceLog.self, CompanionNote.self, CompanionMessage.self,
        ])
    }

    @MainActor
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            // 保存先が開けないときは、せめて起動できるようメモリ上で動かす(画面の警告で知らせる)
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }
}
