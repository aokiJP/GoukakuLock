import SwiftUI
import WidgetKit
import ActivityKit
import GoukakuShared

/// 緊急解除・集中タイマー・稼働型の解除枠の残り時間(ロック画面と Dynamic Island)
struct GoukakuLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoukakuActivityAttributes.self) { context in
            LiveActivityContentView(state: context.state)
                .activityBackgroundTint(Theme.paper)
                .activitySystemActionForegroundColor(Theme.ink)
                .widgetURL(LiveActivityStyle.url(context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SealView(text: LiveActivityStyle.seal(context.state), color: LiveActivityStyle.color(context.state),
                             filled: false, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityTimerText(state: context.state)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(LiveActivityStyle.color(context.state))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(LiveActivityStyle.title(context.state))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(LiveActivityStyle.subtitle(context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Text(LiveActivityStyle.seal(context.state))
                    .font(.system(size: 14, weight: .heavy, design: .serif))
                    .foregroundStyle(LiveActivityStyle.color(context.state))
            } compactTrailing: {
                LiveActivityTimerText(state: context.state)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 58)
            } minimal: {
                Text(LiveActivityStyle.seal(context.state))
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .foregroundStyle(LiveActivityStyle.color(context.state))
            }
            .widgetURL(LiveActivityStyle.url(context.state))
            .keylineTint(LiveActivityStyle.color(context.state))
        }
    }
}
