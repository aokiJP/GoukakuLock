import SwiftUI
import WidgetKit
import GoukakuCore
import GoukakuShared

/// state.json(本体だけが書く)と widget.json を読み、判定が変わる時刻ごとにコマを並べる(仕様書 第9.1節)
struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        .sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        if context.isPreview {
            completion(Self.entries(limit: 1).first ?? .sample())
        } else {
            completion(Self.entries(limit: 1).first ?? .empty())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entries = Self.entries(limit: 24)
        if entries.isEmpty {
            completion(Timeline(entries: [.empty()], policy: .after(Date().addingTimeInterval(3600))))
        } else {
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// 判定が変わる時刻(nextCheck)ちょうどにコマを置く。最大24時間ぶん
    static func entries(limit: Int, now: Date = Date()) -> [StatusEntry] {
        guard let directory = AppGroup.containerURL else { return [] }
        let store = SharedStateStore(directory: directory)
        guard let state = try? store.load() else { return [] }
        let extra = store.pendingAchievements()
        let snapshot = WidgetSnapshot.load(from: directory) ?? WidgetSnapshot()
        var result: [StatusEntry] = []
        var time = now
        let end = now.addingTimeInterval(24 * 3600)
        while result.count < limit && time < end {
            let summary = StatusSummary.make(state: state, extra: extra, now: time)
            result.append(StatusEntry(date: time, summary: summary, snapshot: snapshot))
            guard let next = summary.nextCheck, next > time else { break }
            time = next.addingTimeInterval(1)
        }
        return result
    }
}

struct StatusWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatusEntry

    var body: some View {
        StatusWidgetView(entry: entry, family: family)
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.status, provider: StatusProvider()) { entry in
            StatusWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { Theme.paper }
                .widgetURL(entry.summary?.pending.isEmpty == false ? DeepLink.checkIn : DeepLink.home)
        }
        .configurationDisplayName("合格ロック")
        .description("今日の状態と、次に変わるまでの時間。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
