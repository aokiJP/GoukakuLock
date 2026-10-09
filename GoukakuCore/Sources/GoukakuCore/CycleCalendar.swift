import Foundation

/// 「日付切替時刻(dayStart)」を境に 1日 = 1サイクル として数える暦。
/// 夏時間のある地域でも壊れないよう、固定秒数のずらしではなく暦の計算で求める。
public struct CycleCalendar: Sendable {
    public let calendar: Calendar
    /// 0:00 からの分。0...360(0:00〜6:00)、30分刻み(検証は SchedulePlanner.isValidDayStart)
    public let dayStartMinute: Int

    public init(dayStartMinute: Int, timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
        self.dayStartMinute = dayStartMinute
    }

    /// サイクルの開始時刻(その日付の dayStart)
    public func start(of cycle: CycleID) -> Date {
        let comps = DateComponents(year: cycle.year, month: cycle.month, day: cycle.day,
                                   hour: dayStartMinute / 60, minute: dayStartMinute % 60)
        return calendar.date(from: comps)!
    }

    /// サイクルの終了時刻(= 次のサイクルの開始時刻。この時刻は次のサイクルに属する)
    public func end(of cycle: CycleID) -> Date {
        start(of: self.cycle(cycle, offsetBy: 1))
    }

    /// date を含むサイクル
    public func cycle(containing date: Date) -> CycleID {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let sameDay = CycleID(year: c.year!, month: c.month!, day: c.day!)
        return date >= start(of: sameDay) ? sameDay : cycle(sameDay, offsetBy: -1)
    }

    /// days 日後(負なら前)のサイクル
    public func cycle(_ cycle: CycleID, offsetBy days: Int) -> CycleID {
        let moved = calendar.date(byAdding: .day, value: days, to: noon(of: cycle))!
        let c = calendar.dateComponents([.year, .month, .day], from: moved)
        return CycleID(year: c.year!, month: c.month!, day: c.day!)
    }

    /// サイクルの曜日(Calendar.weekday と同じ:1=日 … 7=土)
    public func weekday(of cycle: CycleID) -> Int {
        calendar.component(.weekday, from: noon(of: cycle))
    }

    /// サイクルを含む週の月曜日のサイクル(休養日・最小版の週上限の集計に使う)
    public func weekStart(of cycle: CycleID) -> CycleID {
        let offset = (weekday(of: cycle) + 5) % 7   // 月→0, 火→1, … 日→6
        return self.cycle(cycle, offsetBy: -offset)
    }

    /// 「時:分」(0:00 からの分)が、そのサイクルの中で来る時刻。
    /// dayStart より前の時刻は翌日付(日付切替の前)として扱う。
    public func date(minuteOfDay: Int, in cycle: CycleID) -> Date {
        let day = minuteOfDay >= dayStartMinute ? cycle : self.cycle(cycle, offsetBy: 1)
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                  hour: minuteOfDay / 60, minute: minuteOfDay % 60))!
    }

    private func noon(of cycle: CycleID) -> Date {
        calendar.date(from: DateComponents(year: cycle.year, month: cycle.month, day: cycle.day, hour: 12))!
    }
}
