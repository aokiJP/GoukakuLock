import SwiftUI
import WidgetKit
import GoukakuCore
import GoukakuShared

extension AppModel {
    /// いまの状態で描いたウィジェットの見本
    func widgetPreviewEntry(now: Date = Date()) -> StatusEntry {
        guard let summary = statusSummary(now: now) else { return .sample(date: now) }
        let stats = stats()
        let snapshot = WidgetSnapshot(streak: stats.streak, total: stats.total, longest: stats.longest,
                                      emergencyThisWeek: emergencyCountThisWeek(),
                                      recent: recentOutcomes(days: 7).map { $0.outcome.rawValue })
        return StatusEntry(date: now, summary: summary, snapshot: snapshot)
    }
}

/// ウィジェットの見た目をアプリの中で描く(ウィジェットと同じビューを使う)
struct WidgetPreviewFrame: View {
    var entry: StatusEntry
    var family: WidgetFamily

    private var size: CGSize {
        switch family {
        case .systemMedium: return CGSize(width: 338, height: 158)
        case .accessoryRectangular: return CGSize(width: 172, height: 76)
        case .accessoryCircular: return CGSize(width: 76, height: 76)
        case .accessoryInline: return CGSize(width: 260, height: 26)
        default: return CGSize(width: 158, height: 158)
        }
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        StatusWidgetView(entry: entry, family: family)
            .padding(isAccessory ? 4 : 16)
            .frame(width: size.width, height: size.height)
            .foregroundStyle(isAccessory ? Color.white : Theme.ink)
            .environment(\.colorScheme, isAccessory ? .dark : .light)
            .background(
                RoundedRectangle(cornerRadius: isAccessory ? 14 : 22, style: .continuous)
                    .fill(isAccessory ? Color.black.opacity(0.75) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isAccessory ? 14 : 22, style: .continuous)
                    .strokeBorder(Theme.rule)
            )
            .accessibilityElement(children: .combine)
    }
}

/// 使いこなす:ウィジェット・ロック画面・コントロールセンター・通知・Siri から記録する方法
struct TipsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entry = model.widgetPreviewEntry()
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    WidgetPreviewFrame(entry: entry, family: .systemSmall)
                    WidgetPreviewFrame(entry: entry, family: .systemMedium)
                }
                .padding(.vertical, 6)
                Text("ホーム画面を長押し →「編集」→「ウィジェットを追加」→「合格ロック」。充電中に横向きにすると、StandBy でも大きく見えます。タップするとチェックイン画面が開きます。")
                    .font(.footnote)
            } header: {
                Text("ホーム画面・StandBy")
            }
            Section {
                HStack(spacing: 14) {
                    WidgetPreviewFrame(entry: entry, family: .accessoryCircular)
                    WidgetPreviewFrame(entry: entry, family: .accessoryRectangular)
                }
                .padding(.vertical, 6)
                Text("ロック画面を長押し →「カスタマイズ」→ ロック画面 → ウィジェットの欄に「合格ロック」を追加。")
                    .font(.footnote)
            } header: {
                Text("ロック画面")
            }
            Section {
                Label("ホーム画面で合格ロックのアイコンを長押し →「チェックイン」か「集中タイマー」。", systemImage: "hand.tap")
                    .font(.footnote)
            } header: {
                Text("アイコンから")
            }
            Section {
                Label("コントロールセンターを開いて「+」→「コントロールを追加」→「合格ロックでチェックイン」。アクションボタン(対応機種)にも割り当てられます。", systemImage: "switch.2")
                    .font(.footnote)
            } header: {
                Text("コントロールセンター")
            }
            Section {
                Label("リマインドやシールドの通知を長押し →「一言書いて記録」。5文字以上で、アプリを開かずに記録できます。", systemImage: "bell.badge")
                    .font(.footnote)
            } header: {
                Text("通知から")
            }
            Section {
                Label("「Hey Siri、合格ロックでチェックイン」→ やったことを話すと記録します。", systemImage: "waveform")
                Label("「Hey Siri、合格ロックの今日の状態」→ ロック中か、残りがいくつかを答えます。", systemImage: "questionmark.bubble")
                Label("ショートカット App の「オートメーション」と組み合わせれば、家に着いたら集中タイマーを開く、などもできます。", systemImage: "square.stack.3d.up")
            } header: {
                Text("Siri・ショートカット")
            }
            .font(.footnote)
            Section {
                LiveActivityContentView(state: .init(kind: .focus, title: "テキストを25分集中して進める",
                                                     startsAt: Date().addingTimeInterval(-300),
                                                     endsAt: Date().addingTimeInterval(1200)))
                    .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 18))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Text("緊急解除・集中タイマー・稼働型の解除枠のあいだは、残り時間がロック画面と Dynamic Island に出ます。")
                    .font(.footnote)
            } header: {
                Text("Dynamic Island・Live Activity")
            }
        }
        .navigationTitle("使いこなす")
        .navigationBarTitleDisplayMode(.inline)
    }
}
