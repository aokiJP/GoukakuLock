import Foundation
import GoukakuCore
import GoukakuKit

/// 設定まわりの state.json の書き換え(AppActions の続き)。
/// 受け付けてよいかの判断(ChangePolicy)は AppModel が済ませてから呼ぶ。ここは書くだけ。
extension AppActions {
    /// はじめの設定の最後に、最初の state.json を作る
    func createInitialState(_ state: SharedState) throws {
        try store.save(state)
    }

    func setSchedule(_ config: ScheduleConfig) throws {
        try mutate { $0.schedule = config }
    }

    func setEnforcement(_ enforcement: Enforcement) throws {
        let now = clock()
        try mutate { state in
            guard state.enforcement != enforcement else { return }
            state.enforcement = enforcement
            state.enforcementChangedAt = now
        }
    }

    func setOptions(_ options: LockOptions) throws {
        try mutate { $0.options = options }
    }

    /// コミットの写しを追加または置き換える(id で照合)
    func upsertHabit(_ snapshot: HabitSnapshot) throws {
        try mutate { state in
            if let i = state.habits.firstIndex(where: { $0.id == snapshot.id }) {
                state.habits[i] = snapshot
            } else {
                state.habits.append(snapshot)
            }
        }
    }

    /// コミットを until のサイクルから無効にする(過去の判定のため、写しは14日残す)
    func endHabit(id: UUID, until: CycleID) throws {
        try mutate { state in
            guard let i = state.habits.firstIndex(where: { $0.id == id }) else { return }
            state.habits[i].activeUntil = until
        }
    }

    /// 休養日を外す(厳しくする変更なので、いつでも受け付ける)
    func removeRestDay(_ day: CycleID) throws {
        try mutate { $0.restDays.remove(day) }
    }

    /// 判定し直してロックに反映する
    @discardableResult
    func reconcile(source: String) -> LockDecision? {
        Reconciler.run(store: store, now: clock(), source: source, logToInbox: false)
    }

    #if DEBUG
    /// デバッグ:日付切替を任意の時刻(分)にする。区切りが動くので記録の意味は変わる
    func debugSetDayStart(minute: Int) throws {
        try mutate { $0.schedule.dayStartMinute = minute }
    }
    #endif
}
