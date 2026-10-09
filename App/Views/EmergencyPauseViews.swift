import SwiftUI
import GoukakuCore
import GoukakuKit

/// S-07 緊急解除(安全の床:いつでも申請できる。15分後から2時間。固定)
struct EmergencyView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRequest = false

    var body: some View {
        let now = Date()
        let window = model.state?.emergency
        let pending = window.map { $0.isPending(at: now) } ?? false
        let active = window.map { $0.isActive(at: now) } ?? false
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    SealView(text: "急", color: Theme.amber, filled: active, size: 60)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("申請の15分後から2時間、ロックが外れます。")
                            .font(Theme.heading(.headline))
                            .foregroundStyle(Theme.ink)
                        Text("いつでも、ひとりで使えます。回数は記録され、ホームに今週の回数が出ます。終わったときに未達成なら、自動でロックが戻ります。")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 4)
            }
            if let window, pending {
                Section("待機中") {
                    HStack {
                        Text("解除まで")
                        Spacer()
                        Text(timerInterval: now...window.startsAt, countsDown: true)
                            .monospacedDigit()
                            .foregroundStyle(Theme.amber)
                    }
                    InfoRow(title: "解除", value: "\(Fmt.clock(window.startsAt)) 〜 \(Fmt.clock(window.endsAt))")
                    Button("取り消す(回数に数えません)", role: .destructive) { model.cancelEmergency() }
                }
            } else if let window, active {
                Section("解除中") {
                    HStack {
                        Text("残り")
                        Spacer()
                        Text(timerInterval: now...window.endsAt, countsDown: true)
                            .monospacedDigit()
                            .foregroundStyle(Theme.amber)
                    }
                    InfoRow(title: "再ロックの判定", value: Fmt.clock(window.endsAt))
                }
            } else {
                Section {
                    Button {
                        confirmRequest = true
                    } label: {
                        Text("緊急解除を申請する")
                    }
                    .buttonStyle(SealButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                InfoRow(title: "今週の回数", value: "\(model.emergencyCountThisWeek())回")
            } footer: {
                Text("開始時と、終了10分前に通知します。待機中に今日のコミットを達成したら、待機は自動で取り消されます。")
            }
        }
        .navigationTitle("緊急解除")
        .navigationBarTitleDisplayMode(.inline)
        .alert("緊急解除を申請しますか?", isPresented: $confirmRequest) {
            Button("申請する") { model.requestEmergency() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text(debugNote + "15分後から2時間、お金を使うアプリのロックが外れます。回数は記録されます。")
        }
    }

    private var debugNote: String {
        #if DEBUG
        return model.settings.debugShortEmergency ? "(デバッグ:待機1分・解除15分)\n" : ""
        #else
        return ""
        #endif
    }
}

/// S-08 一時停止・見守り・卒業
struct PauseView: View {
    @Environment(AppModel.self) private var model
    @State private var duration = PauseDuration.oneDay
    @State private var customEnd = Date().addingTimeInterval(3 * 86_400)
    @State private var confirmPause = false

    enum PauseDuration: String, CaseIterable, Identifiable {
        case oneDay = "1日"
        case threeDays = "3日"
        case oneWeek = "1週間"
        case custom = "日時を決める"
        case indefinite = "無期限"
        var id: String { rawValue }
    }

    private func endDate() -> Date? {
        let now = Date()
        switch duration {
        case .oneDay: return now.addingTimeInterval(86_400)
        case .threeDays: return now.addingTimeInterval(3 * 86_400)
        case .oneWeek: return now.addingTimeInterval(7 * 86_400)
        case .custom: return customEnd
        case .indefinite: return nil
        }
    }

    var body: some View {
        let locked = model.decision?.shouldLock == true
        Form {
            if let pause = model.activePause {
                Section {
                    Label(pause.end.map { "\(Fmt.clock($0)) まで一時停止中" } ?? "無期限で一時停止中", systemImage: "pause.circle.fill")
                        .foregroundStyle(Theme.ink)
                    Button("再開する") { model.resume() }
                        .buttonStyle(SealButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("再開はすぐ効きます。")
                }
            } else if locked {
                Section {
                    Text("ロック中は、緊急解除(申請の15分後から2時間)でロックを外してから一時停止できます。")
                    NavigationLink("緊急解除へ") { EmergencyView() }
                }
            } else {
                Section {
                    Picker("期間", selection: $duration) {
                        ForEach(PauseDuration.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if duration == .custom {
                        DatePicker("再開", selection: $customEnd, in: Date()...)
                    }
                    Button("一時停止する") { confirmPause = true }
                        .buttonStyle(SealButtonStyle())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("一時停止")
                } footer: {
                    Text("ロックをすべて止めます。ストリークはここで止まり、通算は減りません。")
                }
            }

            Section {
                Toggle("見守りモード(ロックせず記録だけ)", isOn: Binding(
                    get: { model.state?.enforcement == .monitorOnly },
                    set: { model.report(model.setEnforcement($0 ? .monitorOnly : .lock)) }
                ))
            } footer: {
                Text("見守りモードへの切り替えは「ゆるめる変更」です(達成後に受け付け、翌日から)。ロックに戻すのはすぐ効きます。")
            }

            if let rate = model.achievementRate(lastDays: 56, minimumScheduled: 40), rate >= 0.9 {
                Section("卒業の提案") {
                    Text("この8週間、予定した日の\(Int((rate * 100).rounded()))%を達成しています。刺激を弱めても続く段階かもしれません:朝からロック → 夕方からロック → 見守りモード → アンインストール。")
                        .font(.subheadline)
                }
            }

            Section {
                Text(AppConstants.quitSignal)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle("一時停止・見守り")
        .navigationBarTitleDisplayMode(.inline)
        .alert("一時停止しますか?", isPresented: $confirmPause) {
            Button("一時停止する") { model.pause(until: endDate()) }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("ストリークはここで止まります(通算は減りません)。")
        }
    }
}
