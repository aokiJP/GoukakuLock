import SwiftUI
import FamilyControls
import GoukakuCore
import GoukakuKit

/// 曜日を選ぶ(月曜はじまり)
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Fmt.weekdayOrder, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Fmt.weekdaySymbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Color.white : Theme.ink)
                        .background(
                            Circle().fill(on ? Theme.ink : Color.clear)
                        )
                        .overlay(Circle().strokeBorder(Theme.rule, lineWidth: on ? 0 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Fmt.weekdaySymbols[day - 1])曜日")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// 「時:分」(0:00 からの分)を選ぶ。choices に選べる値を並べる
struct MinuteChoicePicker: View {
    var title: String
    var choices: [Int]
    @Binding var minute: Int

    var body: some View {
        Picker(title, selection: $minute) {
            ForEach(choices, id: \.self) { m in
                Text(Fmt.hm(minuteOfDay: m)).tag(m)
            }
        }
    }

    /// 日付切替:0:00〜6:00、30分刻み
    static var dayStartChoices: [Int] { Array(stride(from: 0, through: 360, by: 30)) }

    /// 夕方からロックの開始:日付切替の30分後〜20時間後、30分刻み(並びは日付切替から近い順)
    static func lockStartChoices(dayStart: Int) -> [Int] {
        stride(from: 30, through: 1200, by: 30).map { (dayStart + $0) % 1440 }
            .filter { SchedulePlanner.isValidLockStart($0, dayStartMinute: dayStart) }
    }

    /// 通知の時刻:30分刻みの一日
    static var anyTimeChoices: [Int] { Array(stride(from: 0, to: 1440, by: 30)) }
}

/// ロック対象と「常に許可」を選ぶ欄(S-01 の手順4・S-06)
struct TargetsEditor: View {
    @Binding var targets: LockTargets
    @Binding var confirmed: Bool
    @State private var pickingLock = false
    @State private var pickingAllow = false

    var body: some View {
        Section {
            Button {
                pickingLock = true
            } label: {
                Label("ロック対象を選ぶ", systemImage: "lock")
            }
            .familyActivityPicker(isPresented: $pickingLock, selection: $targets.lock)
            TokenSummary(selection: targets.lock)
        } header: {
            Text("ロック対象")
        } footer: {
            Text("決済アプリ・買い物アプリ・「ショッピング」などのカテゴリ・買い物サイト。個別のアプリとサイトは、それぞれ\(LockTargets.maxItemsPerKind)個まで。")
        }

        Section {
            Button {
                pickingAllow = true
            } label: {
                Label("常に許可するものを選ぶ", systemImage: "checkmark.shield")
            }
            .familyActivityPicker(isPresented: $pickingAllow, selection: $targets.allow)
            TokenSummary(selection: targets.allow)
        } header: {
            Text("常に許可")
        } footer: {
            Text("地図・乗換案内・銀行・連絡手段・健康/医療など、ロックしてはいけないアプリ。カテゴリで選んだときに巻き込まれるのを防ぎます。両方にあるものは、常に許可が優先されます。")
        }

        Section {
            Toggle(isOn: $confirmed) {
                Text("銀行・地図・乗換・連絡・医療のアプリを、ロック対象に入れていないことを確かめました")
                    .font(.subheadline)
            }
            ForEach(targets.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.seal)
            }
        }
    }
}

/// 選んだトークンの一覧(アプリ側は名前を読めないので、システムの Label で表示する)
struct TokenSummary: View {
    var selection: FamilyActivitySelection

    var body: some View {
        let apps = Array(selection.applicationTokens)
        let categories = Array(selection.categoryTokens)
        let domains = Array(selection.webDomainTokens)
        if apps.isEmpty && categories.isEmpty && domains.isEmpty {
            Text("まだ選んでいません")
                .foregroundStyle(Theme.muted)
        } else {
            ForEach(categories, id: \.self) { token in
                Label(token)
            }
            ForEach(apps, id: \.self) { token in
                Label(token)
            }
            ForEach(domains, id: \.self) { token in
                Label(token)
            }
            Text("アプリ \(apps.count)・カテゴリ \(categories.count)・サイト \(domains.count)")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }
}

/// 長押しなどで出す小さな説明つきの行
struct InfoRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Theme.muted)
        }
    }
}
