import Foundation

/// 時刻と期間の書き方(本体・ウィジェット・Siri で同じ言い方にする)
public enum ClockText {
    public static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "ja_JP")
        return cal
    }

    /// 0:00 からの分 → "4:00"
    public static func hm(minuteOfDay minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// 時刻 → "21:00"
    public static func hm(_ date: Date, calendar: Calendar = ClockText.calendar()) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }

    /// 「今日 21:00」「明日 4:00」「昨日 9:00」「10/12 4:00」
    public static func relative(_ date: Date, now: Date, calendar: Calendar = ClockText.calendar()) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今日 \(hm(date, calendar: calendar))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明日 \(hm(date, calendar: calendar))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨日 \(hm(date, calendar: calendar))"
        }
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0) \(hm(date, calendar: calendar))"
    }

    /// 分 → "2時間" "1時間30分" "45分"
    public static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)時間\(m)分" }
        return h > 0 ? "\(h)時間" : "\(m)分"
    }

    /// 長い名前を詰める("英単語20個を覚えて…")
    public static func short(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(max(1, limit - 1))) + "…"
    }
}
