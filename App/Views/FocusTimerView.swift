import SwiftUI
import UIKit
import GoukakuCore
import GoukakuShared

/// 集中タイマー(仕様書 第6.2節):本アプリが前面にある時間だけを数える。
/// 離れると一時停止(厳格モードなら0から)。実行中は自動ロックを止め、画面を点けたままにする。
@MainActor @Observable
final class FocusTimer {
    enum Phase { case ready, running, paused, done }

    let habit: HabitSnapshot
    let strict: Bool
    private(set) var minimum = false
    private(set) var targetSeconds: Int
    private(set) var phase: Phase = .ready
    private(set) var accumulated: TimeInterval = 0
    private(set) var runningSince: Date?
    /// 厳格モードで0に戻った回数
    private(set) var resets = 0
    let fullMinutes: Int
    let minimumMinutes: Int

    init(habit: HabitSnapshot, fullMinutes: Int, minimumMinutes: Int, strict: Bool) {
        self.habit = habit
        self.fullMinutes = fullMinutes
        self.minimumMinutes = minimumMinutes
        self.targetSeconds = fullMinutes * 60
        self.strict = strict
    }

    func setMinimum(_ on: Bool) {
        guard phase == .ready else { return }
        minimum = on
        targetSeconds = (on ? minimumMinutes : fullMinutes) * 60
    }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, TimeInterval(targetSeconds) - elapsed(at: now))
    }

    func progress(at now: Date) -> Double {
        min(1, elapsed(at: now) / TimeInterval(max(1, targetSeconds)))
    }

    func start() {
        guard phase == .ready || phase == .paused else { return }
        runningSince = Date()
        phase = .running
        UIApplication.shared.isIdleTimerDisabled = true
        showActivity()
    }

    func pause() {
        guard phase == .running else { return }
        accumulate()
        phase = .paused
        UIApplication.shared.isIdleTimerDisabled = false
        showActivity()
    }

    /// アプリを離れた(ホーム画面・別のアプリ・画面ロック)
    func leftApp() {
        guard phase == .running else { return }
        if strict {
            accumulated = 0
            runningSince = nil
            resets += 1
        } else {
            accumulate()
        }
        phase = .paused
        UIApplication.shared.isIdleTimerDisabled = false
        showActivity()
    }

    /// 目標に届いたら true(一度だけ)
    func finishIfReached(now: Date) -> Bool {
        guard phase == .running, elapsed(at: now) >= TimeInterval(targetSeconds) else { return false }
        accumulate()
        phase = .done
        UIApplication.shared.isIdleTimerDisabled = false
        LiveActivities.end(.focus)
        return true
    }

    func cancel() {
        phase = .ready
        accumulated = 0
        runningSince = nil
        UIApplication.shared.isIdleTimerDisabled = false
        LiveActivities.end(.focus)
    }

    private func accumulate() {
        if let since = runningSince { accumulated += Date().timeIntervalSince(since) }
        runningSince = nil
    }

    private func showActivity() {
        let now = Date()
        let left = remaining(at: now)
        let elapsedNow = elapsed(at: now)
        LiveActivities.show(.init(kind: .focus, title: habit.title,
                                  startsAt: now.addingTimeInterval(-elapsedNow),
                                  endsAt: now.addingTimeInterval(left),
                                  pausedRemaining: phase == .running ? nil : left))
    }
}

struct FocusTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var timer: FocusTimer
    @State private var recorded: Achievement?
    @State private var drawn: CGFloat = 0
    @State private var ticks = 0

    init(habit: HabitSnapshot, fullMinutes: Int, minimumMinutes: Int, strict: Bool) {
        _timer = State(initialValue: FocusTimer(habit: habit, fullMinutes: fullMinutes,
                                                minimumMinutes: minimumMinutes, strict: strict))
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(timer.habit.title)
                .font(Theme.heading(.title3))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let recorded {
                doneView(recorded)
            } else {
                timerFace
                controls
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .navigationTitle("集中タイマー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(recorded == nil && timer.phase != .ready ? "やめる" : "閉じる") {
                    timer.cancel()
                    dismiss()
                }
            }
        }
        .sensoryFeedback(.success, trigger: recorded?.id)
        .sensoryFeedback(.impact(weight: .light), trigger: timer.phase == .running)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { timer.leftApp() }
        }
        .task {
            // 1秒ごとに、目標に届いたかを見る
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                ticks &+= 1
                if timer.finishIfReached(now: Date()) { record() }
            }
        }
        .onDisappear {
            if recorded == nil { timer.cancel() }
        }
    }

    private var timerFace: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = timer.progress(at: context.date)
            let left = Int(timer.remaining(at: context.date).rounded(.up))
            ZStack {
                Circle()
                    .stroke(Theme.rule, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.seal, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: progress)
                VStack(spacing: 4) {
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(Theme.numeral(size: 60))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(countsDown: true))
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 260, height: 260)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("残り \(left / 60)分\(left % 60)秒")
        }
    }

    private var statusText: String {
        switch timer.phase {
        case .ready: return timer.minimum ? "最小版 \(timer.minimumMinutes)分" : "目標 \(timer.fullMinutes)分"
        case .running: return "集中中"
        case .paused: return timer.strict && timer.accumulated == 0 && timer.resets > 0 ? "離れたので0から(厳格)" : "一時停止中"
        case .done: return "達成"
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 14) {
            switch timer.phase {
            case .ready:
                if timer.habit.minimumTitle != nil {
                    Toggle(isOn: Binding(get: { timer.minimum }, set: { timer.setMinimum($0) })) {
                        Text("最小版で(\(timer.minimumMinutes)分)")
                    }
                    .disabled(!model.canUseMinimum())
                    .tint(Theme.seal)
                    .padding(.horizontal, 4)
                }
                Button("はじめる") { timer.start() }
                    .buttonStyle(SealButtonStyle())
            case .running:
                Button("一時停止") { timer.pause() }
                    .buttonStyle(.bordered)
                    .tint(Theme.muted)
                    .controlSize(.large)
            case .paused:
                Button("再開する") { timer.start() }
                    .buttonStyle(SealButtonStyle())
            case .done:
                EmptyView()
            }
            Text(timer.strict
                 ? "厳格モード:アプリを離れると0からやり直しです。"
                 : "アプリを離れると止まり、戻ってから「再開」で続きを数えます。")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private func doneView(_ achievement: Achievement) -> some View {
        VStack(spacing: 16) {
            HanamaruView(progress: drawn)
                .frame(width: 200, height: 200)
                .onAppear { withAnimation(.easeInOut(duration: 1.2)) { drawn = 1 } }
            Text(achievement.kind == .minimum ? "最小版で記録しました" : "記録しました")
                .font(Theme.heading())
                .foregroundStyle(Theme.ink)
            if let minutes = achievement.grantsMinutes {
                Text("\(Fmt.duration(minutes: minutes))、お金を使うアプリのロックが外れます。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            } else if model.decision?.todaySatisfied == true {
                Text("今日の必須コミットをすべて達成。ロックが外れました。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            Button("閉じる") { dismiss() }
                .buttonStyle(SealButtonStyle())
                .padding(.horizontal, 24)
        }
    }

    private func record() {
        let seconds = Int(timer.elapsed(at: Date()))
        if let achievement = model.checkIn(habit: timer.habit, minimum: timer.minimum, evidence: .timer(seconds: seconds)) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { recorded = achievement }
        }
    }
}
