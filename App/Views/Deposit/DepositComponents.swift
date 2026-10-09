import SwiftUI
import GoukakuCore

/// 預け金の1日の印(返金した・返ってくる・戻らない・今日・これから)
struct DepositDayMarkView: View {
    var mark: DepositDayMark
    var size: CGFloat = 26

    var body: some View {
        Group {
            switch mark {
            case .returned:
                SealView(text: "返", color: Theme.seal, filled: true, size: size)
            case .returning:
                SealView(text: "返", color: Theme.seal, filled: false, size: size)
            case .kept:
                MarkView(outcome: .batsu, size: size * 0.8)
                    .frame(width: size, height: size)
            case .today:
                MarkView(outcome: .pending, size: size * 0.85)
                    .frame(width: size, height: size)
            case .upcoming:
                SlotMarkView(outcome: .blank, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    static func label(_ mark: DepositDayMark) -> String {
        switch mark {
        case .returned: return "返金した"
        case .returning: return "返ってくる"
        case .kept: return "戻らない"
        case .today: return "今日"
        case .upcoming: return "これから"
        }
    }
}

/// 7日分の帯(曜日と日付と印)
struct DepositStrip: View {
    var week: DepositWeek
    var marks: [DepositDayMark]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 4) {
                    Text(Self.weekday(day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(marks[safe: index] == .today ? Theme.seal : Theme.muted)
                    DepositDayMarkView(mark: marks[safe: index] ?? .upcoming)
                    Text(Fmt.monthDay(day.startsAt))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Fmt.monthDay(day.startsAt)) \(DepositDayMarkView.label(marks[safe: index] ?? .upcoming))")
            }
        }
    }

    static func weekday(_ day: DepositWeek.Day) -> String {
        guard let cycle = day.cycle else { return "" }
        let cal = CycleCalendar(dayStartMinute: 0)
        return Fmt.weekdaySymbols[cal.weekday(of: cycle) - 1]
    }
}

/// 額の内わけ(0 のものは出さない)
struct DepositBreakdownText: View {
    var breakdown: DepositBreakdown

    private struct Part: Identifiable {
        var id: String
        var amount: Int
        var color: Color
    }

    private var parts: [Part] {
        [
            Part(id: "返金した", amount: breakdown.returned, color: Theme.seal),
            Part(id: "返ってくる", amount: breakdown.returning, color: Theme.seal),
            Part(id: "戻らない", amount: breakdown.kept, color: Theme.ink),
            Part(id: "これから", amount: breakdown.open, color: Theme.muted),
        ].filter { $0.amount > 0 }
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 1) {
                    Text(part.id).font(.caption2).foregroundStyle(Theme.muted)
                    Text(Fmt.yen(part.amount)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(part.color)
                }
            }
        }
    }
}

/// ホームの「今週の預け金」(預けているときだけ)
struct DepositHomeCard: View {
    @Environment(DepositModel.self) private var deposit

    var body: some View {
        if let problem = deposit.renewalProblem, deposit.current == nil {
            NavigationLink {
                DepositView()
            } label: {
                RuledBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("預け金", systemImage: "creditcard")
                            .font(Theme.heading(.headline))
                            .foregroundStyle(Theme.ink)
                        Text(problem.reason).font(.footnote).foregroundStyle(Theme.amber)
                        Text("押すと、カードで預け直せます").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if let week = deposit.current {
            let marks = deposit.marks(for: week)
            let breakdown = deposit.breakdown(for: week)
            NavigationLink {
                DepositView()
            } label: {
                RuledBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(week.status == .upcoming ? "預け金(明日から)" : "今週の預け金", systemImage: "creditcard")
                                .font(Theme.heading(.headline))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if !week.livemode {
                                Text("テスト").font(.caption2.weight(.bold)).foregroundStyle(Theme.amber)
                            }
                            Text(Fmt.yen(week.total)).font(.headline.monospacedDigit()).foregroundStyle(Theme.ink)
                        }
                        DepositStrip(week: week, marks: marks)
                        DepositBreakdownText(breakdown: breakdown)
                        if let hint = Self.todayHint(marks: marks, daily: week.daily) {
                            Text(hint).font(.footnote).foregroundStyle(Theme.pencil)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deposit.home")
        }
    }

    static func todayHint(marks: [DepositDayMark], daily: Int) -> String? {
        if marks.contains(.today) {
            return "今日のコミットを達成すると、\(Fmt.yen(daily))が返ってきます"
        }
        if marks.contains(.returning) {
            return "達成した日の分は、取り消しの時間が過ぎるか日付が変わったら返金の手続きをします"
        }
        return nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
