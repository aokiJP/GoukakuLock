import SwiftUI
import WidgetKit
import GoukakuCore
import GoukakuShared

/// ウィジェットの1コマ。本体のアプリでも見本として描けるよう、ウィジェット拡張と本体の両方に入れる。
struct StatusEntry: TimelineEntry, Sendable {
    var date: Date
    var summary: StatusSummary?
    var snapshot: WidgetSnapshot

    /// 見本(ウィジェットを選ぶ画面・アプリ内の見本)
    static func sample(date: Date = Date()) -> StatusEntry {
        let habit = StatusSummary.Item(id: UUID(), title: "英単語20個を覚えて、自作テストで7割", done: false, minimum: false, method: .selfReport)
        let summary = StatusSummary(seal: "未", tone: .locked, headline: "今日の「英単語20個を覚えて、自作テストで7割」がまだです",
                                    shortHeadline: "「英単語20個を覚え…」がまだ", detail: nil,
                                    countdownTo: date.addingTimeInterval(3 * 3600 + 25 * 60), countdownLabel: "切り替えまで",
                                    shouldLock: true, cycle: CycleID(year: 2026, month: 10, day: 9), required: [habit])
        return StatusEntry(date: date, summary: summary,
                           snapshot: WidgetSnapshot(streak: 12, total: 48, longest: 21,
                                                    recent: ["achieved", "achieved", "minimum", "achieved", "rest", "achieved", "inProgress"]))
    }

    static func empty(date: Date = Date()) -> StatusEntry {
        StatusEntry(date: date, summary: nil, snapshot: WidgetSnapshot())
    }
}

/// 種類(大きさ)ごとに出し分ける
struct StatusWidgetView: View {
    var entry: StatusEntry
    var family: WidgetFamily

    var body: some View {
        switch family {
        case .systemMedium: MediumStatusView(entry: entry)
        case .accessoryCircular: CircularStatusView(entry: entry)
        case .accessoryRectangular: RectangularStatusView(entry: entry)
        case .accessoryInline: InlineStatusView(entry: entry)
        default: SmallStatusView(entry: entry)
        }
    }
}

struct SmallStatusView: View {
    var entry: StatusEntry
    /// 直近7日の記号を出すか(中のウィジェットでは右側に出すので false)
    var showsRecent = true

    var body: some View {
        if let s = entry.summary {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    SealView(text: s.seal, color: s.tone.color, filled: s.tone.filled, size: 46)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("\(entry.snapshot.streak)")
                            .font(Theme.numeral(size: 28))
                            .foregroundStyle(Theme.ink)
                        Text("連続")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 2)
                if showsRecent && !entry.snapshot.recent.isEmpty {
                    RecentMarksRow(outcomes: entry.snapshot.recentOutcomes)
                        .padding(.bottom, 2)
                }
                Text(s.shortHeadline)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                CountdownLine(summary: s, date: entry.date)
            }
        } else {
            WidgetEmptyView()
        }
    }
}

struct MediumStatusView: View {
    var entry: StatusEntry

    var body: some View {
        if let s = entry.summary {
            HStack(alignment: .top, spacing: 14) {
                SmallStatusView(entry: entry, showsRecent: false)
                    .frame(maxWidth: 140)
                Rectangle().fill(Theme.rule).frame(width: 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日のコミット")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    if s.required.isEmpty {
                        Text("予定なし").font(.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(s.required.prefix(3)) { item in
                        HStack(spacing: 6) {
                            MarkView(outcome: item.done ? (item.minimum ? .sankaku : .maru) : .pending, size: 13)
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    RecentMarksRow(outcomes: entry.snapshot.recentOutcomes)
                }
            }
        } else {
            WidgetEmptyView()
        }
    }
}

struct RectangularStatusView: View {
    var entry: StatusEntry

    var body: some View {
        if let s = entry.summary {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: s.shouldLock ? "lock.fill" : "lock.open.fill")
                    Text(s.shortHeadline).lineLimit(1)
                }
                .font(.headline)
                .widgetAccentable()
                if let until = s.countdownTo, until > entry.date {
                    HStack(spacing: 3) {
                        Text(s.countdownLabel)
                        Text(timerInterval: entry.date...until, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
                Text("連続\(entry.snapshot.streak)日・今日 \(s.doneCount)/\(s.required.count)")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("合格ロック").font(.headline)
        }
    }
}

struct CircularStatusView: View {
    var entry: StatusEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let s = entry.summary {
                if s.required.isEmpty {
                    Text(String(s.seal.prefix(1)))
                        .font(.system(size: 20, weight: .heavy, design: .serif))
                } else {
                    Gauge(value: Double(s.doneCount), in: 0...Double(s.required.count)) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(String(s.seal.prefix(1)))
                            .font(.system(size: 18, weight: .heavy, design: .serif))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
                }
            } else {
                Image(systemName: "lock")
            }
        }
    }
}

struct InlineStatusView: View {
    var entry: StatusEntry

    var body: some View {
        if let s = entry.summary {
            Label(s.shortHeadline, systemImage: s.shouldLock ? "lock.fill" : "lock.open.fill")
        } else {
            Label("合格ロック", systemImage: "lock")
        }
    }
}

/// 残り時間の1行
struct CountdownLine: View {
    var summary: StatusSummary
    var date: Date

    var body: some View {
        if let until = summary.countdownTo, until > date {
            HStack(spacing: 3) {
                Text(summary.countdownLabel)
                Text(timerInterval: date...until, countsDown: true)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(summary.tone.color)
            .lineLimit(1)
        } else {
            Text(summary.tone == .achieved ? "今日はおわり" : " ")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// 直近7日の記号
struct RecentMarksRow: View {
    var outcomes: [CycleOutcome]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(outcomes.suffix(7).enumerated()), id: \.offset) { pair in
                MarkView(outcome: pair.element.mark, size: 11)
            }
        }
    }
}

struct WidgetEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SealView(text: "合格", color: Theme.seal, filled: true, size: 40)
            Spacer(minLength: 0)
            Text("はじめの設定をすると、ここに今日の状態が出ます")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
