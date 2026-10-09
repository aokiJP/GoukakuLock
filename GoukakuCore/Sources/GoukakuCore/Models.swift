import Foundation

/// ロックのかけ方
public enum LockMode: Codable, Equatable, Sendable {
    /// 朝からロック:サイクル開始と同時にロック。その日の必須コミットを全部達成すると次のサイクルまで解除。
    case morning
    /// 夕方からロック:lockStartMinute(0:00 からの分)までは猶予。それまでに達成していなければロック。
    /// 前のサイクルが未達成なら猶予なし(サイクル開始からロック = 持ち越し)。
    case evening(lockStartMinute: Int)
    /// 稼働型:常にロック。達成1回ごとに windowMinutes だけ解除される。
    case earn(windowMinutes: Int)

    public enum Kind: String, Codable, Sendable { case morning, evening, earn }

    public var kind: Kind {
        switch self {
        case .morning: return .morning
        case .evening: return .evening
        case .earn: return .earn
        }
    }
}

/// 日付切替とロックモード。DeviceActivity に登録するスケジュールの元になる。
public struct ScheduleConfig: Codable, Equatable, Sendable {
    /// 日付切替時刻(0:00 からの分)。0...360、30分刻み。既定 4:00。
    public var dayStartMinute: Int
    public var mode: LockMode

    public init(dayStartMinute: Int = 240, mode: LockMode = .morning) {
        self.dayStartMinute = dayStartMinute
        self.mode = mode
    }
}

/// ロックを実際にかけるか(見守りモードは記録だけ続ける)
public enum Enforcement: String, Codable, Sendable {
    case lock
    case monitorOnly
}

/// 達成の確認方法
public enum VerificationMethod: String, Codable, Sendable, CaseIterable {
    case selfReport   // 自己申告(一言メモ必須)
    case photo        // カメラで撮影した証拠写真
    case timer        // アプリ内タイマー(前面にある時間の累計)
    case appUsage     // 指定アプリの使用時間(DeviceActivity のしきい値)
    case health       // ヘルスケアのワークアウト・歩数
    case placeTimer   // 登録した場所でタイマー
    case referee      // 執行役の承認

    /// 厳しさの段階。上げる変更だけが「厳しくする変更」。同じ段階どうしの変更は「緩める変更」として扱う。
    public var strictness: Int {
        switch self {
        case .selfReport: return 0
        case .photo, .timer, .appUsage, .health: return 1
        case .placeTimer: return 2
        case .referee: return 3
        }
    }
}

/// エンジンが知る必要のあるコミット(習慣)の写し。本体アプリの SwiftData から作って共有する。
public struct HabitSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// 最小版(調子の悪い日の小さい目標)。nil なら最小版なし。
    public var minimumTitle: String?
    /// 予定する曜日(1=日 … 7=土)
    public var weekdays: Set<Int>
    /// 必須なら、これを達成しないとロックが外れない
    public var isRequired: Bool
    public var method: VerificationMethod
    /// タイマー・使用時間で判定するときの分数
    public var targetMinutes: Int?
    /// このサイクルから有効(含む)
    public var activeFrom: CycleID
    /// このサイクルから無効(含まない)。削除したコミットも 14 日は残して過去の判定に使う。
    public var activeUntil: CycleID?

    public init(id: UUID = UUID(), title: String, minimumTitle: String? = nil,
                weekdays: Set<Int> = Set(1...7), isRequired: Bool = true,
                method: VerificationMethod = .selfReport, targetMinutes: Int? = nil,
                activeFrom: CycleID, activeUntil: CycleID? = nil) {
        self.id = id
        self.title = title
        self.minimumTitle = minimumTitle
        self.weekdays = weekdays
        self.isRequired = isRequired
        self.method = method
        self.targetMinutes = targetMinutes
        self.activeFrom = activeFrom
        self.activeUntil = activeUntil
    }

    public func isScheduled(on cycle: CycleID, weekday: Int) -> Bool {
        guard cycle >= activeFrom else { return false }
        if let until = activeUntil, cycle >= until { return false }
        return weekdays.contains(weekday)
    }
}

/// 達成の記録(チェックイン1回分)
public struct Achievement: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case full      // 本来の目標
        case minimum   // 最小版
    }

    public enum Status: String, Codable, Sendable {
        case confirmed         // 確定
        case pendingReview     // 事後承認待ち(提出の時点で解除する。却下されたら未達成に戻る)
        case awaitingApproval  // 同期承認待ち(承認されるまで解除しない)
        case rejected          // 執行役が却下
        case undone            // 本人が取り消し

        /// ロック解除・ストリークに数えるか
        public var counts: Bool { self == .confirmed || self == .pendingReview }
    }

    public enum Source: String, Codable, Sendable {
        case app       // 本体アプリ
        case monitor   // DeviceActivityMonitor 拡張(使用時間の自動判定)
    }

    public var id: UUID
    public var cycle: CycleID
    public var habitID: UUID
    public var kind: Kind
    public var status: Status
    public var source: Source
    public var at: Date
    /// 稼働型でこの達成が生む解除枠(分)。日次モードでは nil。
    public var grantsMinutes: Int?

    public init(id: UUID = UUID(), cycle: CycleID, habitID: UUID, kind: Kind = .full,
                status: Status = .confirmed, source: Source = .app, at: Date, grantsMinutes: Int? = nil) {
        self.id = id
        self.cycle = cycle
        self.habitID = habitID
        self.kind = kind
        self.status = status
        self.source = source
        self.at = at
        self.grantsMinutes = grantsMinutes
    }
}

/// 緊急解除(申請から 15 分待って 2 時間だけ解除)
public struct EmergencyWindow: Codable, Equatable, Sendable {
    public var requestedAt: Date
    public var startsAt: Date
    public var endsAt: Date
    public var cancelledAt: Date?

    public init(requestedAt: Date, startsAt: Date, endsAt: Date, cancelledAt: Date? = nil) {
        self.requestedAt = requestedAt
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.cancelledAt = cancelledAt
    }

    public func isPending(at now: Date) -> Bool {
        cancelledAt == nil && requestedAt <= now && now < startsAt
    }

    public func isActive(at now: Date) -> Bool {
        cancelledAt == nil && startsAt <= now && now < endsAt
    }
}

/// 一時停止の期間
public struct PausePeriod: Codable, Equatable, Sendable {
    public var start: Date
    /// nil なら継続中(再開まで)
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && (end.map { date < $0 } ?? true)
    }

    /// [from, to) と重なるか
    public func overlaps(_ from: Date, _ to: Date) -> Bool {
        start < to && (end.map { $0 > from } ?? true)
    }
}

/// ロック中に一緒にかける設定
public struct LockOptions: Codable, Equatable, Sendable {
    public var denyInAppPurchases: Bool

    public init(denyInAppPurchases: Bool = true) {
        self.denyInAppPurchases = denyInAppPurchases
    }
}

/// 本体アプリだけが書き、拡張・ウィジェットは読むだけの共有状態(App Group の state.json)。
/// ロックの判定に必要なものはすべてここにあり、ここ以外は見ない。
public struct SharedState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var schedule: ScheduleConfig
    public var enforcement: Enforcement
    /// enforcement を最後に切り替えた時刻(持ち越し判定に使う)
    public var enforcementChangedAt: Date
    /// 最初のサイクル。これより前はロックしない
    public var activeSince: CycleID
    public var habits: [HabitSnapshot]
    /// 直近 14 サイクル分(それより古いものは本体が SwiftData に移して削る)
    public var achievements: [Achievement]
    public var restDays: Set<CycleID>
    public var emergency: EmergencyWindow?
    public var pauses: [PausePeriod]
    public var options: LockOptions
    public var updatedAt: Date

    public init(version: Int = SharedState.currentVersion,
                schedule: ScheduleConfig = ScheduleConfig(),
                enforcement: Enforcement = .lock,
                enforcementChangedAt: Date,
                activeSince: CycleID,
                habits: [HabitSnapshot] = [],
                achievements: [Achievement] = [],
                restDays: Set<CycleID> = [],
                emergency: EmergencyWindow? = nil,
                pauses: [PausePeriod] = [],
                options: LockOptions = LockOptions(),
                updatedAt: Date) {
        self.version = version
        self.schedule = schedule
        self.enforcement = enforcement
        self.enforcementChangedAt = enforcementChangedAt
        self.activeSince = activeSince
        self.habits = habits
        self.achievements = achievements
        self.restDays = restDays
        self.emergency = emergency
        self.pauses = pauses
        self.options = options
        self.updatedAt = updatedAt
    }
}
