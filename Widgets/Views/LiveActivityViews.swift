import SwiftUI
import GoukakuCore
import GoukakuShared

/// Live Activity の言い方と色(ロック画面・Dynamic Island・アプリ内の見本で共通)
enum LiveActivityStyle {
    typealias State = GoukakuActivityAttributes.ContentState

    static func seal(_ state: State) -> String {
        switch state.kind {
        case .emergency: return "急"
        case .focus: return "集"
        case .earn: return "解"
        }
    }

    static func color(_ state: State) -> Color {
        state.kind == .emergency ? Theme.amber : Theme.seal
    }

    static func title(_ state: State) -> String {
        switch state.kind {
        case .emergency: return "緊急解除"
        case .focus: return state.title
        case .earn: return "解除中"
        }
    }

    static func subtitle(_ state: State, now: Date = Date()) -> String {
        let cal = ClockText.calendar()
        switch state.kind {
        case .emergency:
            let range = "\(ClockText.hm(state.startsAt, calendar: cal))〜\(ClockText.hm(state.endsAt, calendar: cal))"
            return now < state.startsAt ? "\(range) に解除(待機中)" : "\(range) 解除中"
        case .focus:
            return state.pausedRemaining == nil ? "集中タイマー" : "一時停止中:アプリに戻ると再開"
        case .earn:
            return "\(ClockText.hm(state.endsAt, calendar: cal)) まで使えます"
        }
    }

    static func url(_ state: State) -> URL {
        switch state.kind {
        case .emergency: return DeepLink.emergency
        case .focus: return DeepLink.timer
        case .earn: return DeepLink.home
        }
    }
}

/// 残り時間(一時停止中は止まった値)
struct LiveActivityTimerText: View {
    var state: GoukakuActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedRemaining {
            let seconds = Int(paused.rounded(.up))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
        } else if state.kind == .emergency && Date() < state.startsAt {
            Text(timerInterval: Date()...state.startsAt, countsDown: true)
        } else if state.startsAt <= state.endsAt {
            Text(timerInterval: state.startsAt...state.endsAt, countsDown: true)
        } else {
            Text("0:00")
        }
    }
}

/// ロック画面・通知の位置に出る Live Activity
struct LiveActivityContentView: View {
    var state: GoukakuActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            SealView(text: LiveActivityStyle.seal(state), color: LiveActivityStyle.color(state), filled: false, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(LiveActivityStyle.title(state))
                    .font(Theme.heading(.headline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LiveActivityStyle.subtitle(state))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            LiveActivityTimerText(state: state)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(LiveActivityStyle.color(state))
                .multilineTextAlignment(.trailing)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(16)
    }
}
