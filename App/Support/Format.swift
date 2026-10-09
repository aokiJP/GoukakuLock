import Foundation
import GoukakuCore

/// 時刻・期間・日付の書き方
enum Fmt {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.locale = Locale(identifier: "ja_JP")
        return cal
    }

    /// 0:00 からの分 → "4:00"
    static func hm(minuteOfDay minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// 時刻 → "21:00"
    static func hm(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }

    /// 「今日 21:00」「明日 4:00」「10/12 4:00」
    static func clock(_ date: Date, now: Date = Date()) -> String {
        let cal = calendar
        if cal.isDate(date, inSameDayAs: now) { return "今日 \(hm(date))" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "明日 \(hm(date))"
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) {
            return "昨日 \(hm(date))"
        }
        let c = cal.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0) \(hm(date))"
    }

    /// 分 → "2時間" "1時間30分" "45分"
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)時間\(m)分" }
        return h > 0 ? "\(h)時間" : "\(m)分"
    }

    /// 秒 → "1:42"(時:分)。1時間未満は "42分"
    static func remaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)) / 60)
        if total < 60 { return "\(total)分" }
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]   // Calendar.weekday 1...7
    /// 表示の並び(月曜はじまり)
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    /// サイクル → "10月9日(木)"
    static func cycle(_ cycle: CycleID, dayStartMinute: Int) -> String {
        let cal = CycleCalendar(dayStartMinute: dayStartMinute)
        let wd = cal.weekday(of: cycle)
        return "\(cycle.month)月\(cycle.day)日(\(weekdaySymbols[wd - 1]))"
    }

    /// 曜日の集合 → "毎日" "平日" "月・水・金"
    static func weekdays(_ days: Set<Int>) -> String {
        if days.count == 7 { return "毎日" }
        if days == Set([2, 3, 4, 5, 6]) { return "平日" }
        if days == Set([1, 7]) { return "土日" }
        if days.isEmpty { return "なし" }
        return weekdayOrder.filter { days.contains($0) }.map { weekdaySymbols[$0 - 1] }.joined(separator: "・")
    }

    static func dateTime(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0) \(hm(date))"
    }
}

extension CycleOutcome {
    var label: String {
        switch self {
        case .notStarted: return "開始前"
        case .rest: return "休養日"
        case .noCommit: return "予定なし"
        case .achieved: return "達成"
        case .minimum: return "最小版で達成"
        case .pendingReview: return "達成(承認待ち)"
        case .paused: return "一時停止"
        case .inProgress: return "進行中"
        case .missed: return "未達成"
        }
    }

    var mark: OutcomeMark {
        switch self {
        case .achieved, .pendingReview: return .maru
        case .minimum: return .sankaku
        case .missed: return .batsu
        case .rest: return .rest
        case .paused: return .paused
        case .noCommit: return .none
        case .inProgress: return .pending
        case .notStarted: return .blank
        }
    }
}

extension Acceptance.RejectReason {
    var message: String {
        switch self {
        case .lockedNow:
            return "ロック中は、ゆるめる変更を受け付けません。今日のコミットを達成したあとなら、明日から反映されます。"
        case .requiresPause:
            return "日付切替の時刻は、一時停止中だけ変えられます(区切りが動くと記録の意味が変わるため)。"
        case .notInFuture:
            return "休養日は明日以降にだけ置けます(当日の言い訳には使えません)。"
        case .quotaExceeded:
            return "その週の休養日の上限に達しています。"
        }
    }
}
