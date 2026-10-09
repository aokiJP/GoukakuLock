import SwiftUI
import SwiftData
import GoukakuCore

/// S-05 履歴・統計(カレンダーは色と記号の両方で結果を出す)
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var monthOffset = 0
    @State private var selected: CycleID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.state == nil {
                        Text("はじめの設定が済むと、ここに記録が並びます。").foregroundStyle(Theme.muted)
                    } else {
                        let map = model.outcomeMap()
                        statsRow(map: map)
                        calendar(map: map)
                        legend
                        emergencyList
                    }
                }
                .padding()
            }
            .background(Theme.paper)
            .navigationTitle("記録")
            .sheet(item: $selected) { cycle in
                NavigationStack { DayDetailView(cycle: cycle) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: 統計

    private func statsRow(map: [CycleID: CycleOutcome]) -> some View {
        let stats = model.stats()
        let month = monthCycles()
        let judged = month.compactMap { map[$0] }.filter { [.achieved, .minimum, .pendingReview, .missed].contains($0) }
        let achieved = judged.filter { $0 != .missed }.count
        let rate = judged.isEmpty ? "—" : "\(Int((Double(achieved) / Double(judged.count) * 100).rounded()))%"
        return HStack(spacing: 0) {
            cell(value: "\(stats.streak)", label: "連続")
            cell(value: "\(stats.longest)", label: "最長")
            cell(value: "\(stats.total)", label: "通算")
            cell(value: rate, label: "この月の達成率")
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func cell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.numeral(size: 28))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: カレンダー

    /// 表示する月(暦の月)の1日〜末日のサイクル
    private func monthCycles() -> [CycleID] {
        let cal = model.cycleCalendar
        let base = cal.cycle(containing: Date())
        var comps = DateComponents(year: base.year, month: base.month + monthOffset, day: 1)
        let gregorian = Fmt.calendar
        guard let first = gregorian.date(from: comps) else { return [] }
        comps = gregorian.dateComponents([.year, .month], from: first)
        let range = gregorian.range(of: .day, in: .month, for: first) ?? 1..<29
        return range.map { CycleID(year: comps.year ?? base.year, month: comps.month ?? base.month, day: $0) }
    }

    private func calendar(map: [CycleID: CycleOutcome]) -> some View {
        let days = monthCycles()
        let cal = model.cycleCalendar
        let leading = days.first.map { (cal.weekday(of: $0) + 5) % 7 } ?? 0   // 月曜はじまりの空き
        let current = model.currentCycle
        let title = days.first.map { "\($0.year)年\($0.month)月" } ?? ""
        return VStack(spacing: 10) {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前の月")
                Spacer()
                Text(title).font(Theme.heading(.headline)).foregroundStyle(Theme.ink)
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(monthOffset >= 0)
                    .accessibilityLabel("次の月")
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Fmt.weekdayOrder, id: \.self) { wd in
                    Text(Fmt.weekdaySymbols[wd - 1]).font(.caption2).foregroundStyle(Theme.muted)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 46) }
                ForEach(days, id: \.self) { day in
                    let outcome = day > current ? nil : map[day]
                    Button {
                        if day <= current { selected = day }
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(day.day)")
                                .font(.caption.weight(day == current ? .bold : .regular))
                                .foregroundStyle(day == current ? Theme.seal : Theme.ink)
                            MarkView(outcome: outcome?.mark ?? .blank, size: 20)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(day == current ? Theme.seal.opacity(0.06) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.month)月\(day.day)日 \(outcome?.label ?? "記録なし")")
                }
            }
        }
    }

    private var legend: some View {
        let items: [(OutcomeMark, String)] = [(.maru, "達成"), (.sankaku, "最小版"), (.batsu, "未達成"),
                                              (.rest, "休養日"), (.paused, "一時停止"), (.none, "予定なし"),
                                              (.pending, "進行中")]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    MarkView(outcome: items[i].0, size: 14)
                    Text(items[i].1).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 緊急解除の履歴

    @ViewBuilder private var emergencyList: some View {
        let records = model.emergencyRecords
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("緊急解除の履歴").font(Theme.heading(.headline)).foregroundStyle(Theme.ink)
                ForEach(records.prefix(20)) { record in
                    HStack {
                        Image(systemName: record.didStart(asOf: Date()) ? "clock.badge.exclamationmark" : "xmark.circle")
                            .foregroundStyle(record.didStart(asOf: Date()) ? Theme.amber : Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Fmt.dateTime(record.startsAt)) 〜 \(Fmt.hm(record.endsAt))")
                                .font(.subheadline)
                            Text(record.didStart(asOf: Date()) ? "解除あり" : "待機中に取り消し(回数に数えない)")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}

extension CycleID: @retroactive Identifiable {
    public var id: String { description }
}

/// ある日の詳細(結果・チェックインの一言・緊急解除)
struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cycle: CycleID

    var body: some View {
        let outcome = model.outcomeMap()[cycle]
        let checkIns = model.fetchAll(CheckIn.self)
            .filter { $0.cycleRaw == cycle.description }
            .sorted { $0.at < $1.at }
        List {
            Section {
                HStack(spacing: 12) {
                    MarkView(outcome: outcome?.mark ?? .blank, size: 28)
                    Text(outcome?.label ?? "記録なし").font(Theme.heading(.title3)).foregroundStyle(Theme.ink)
                }
            }
            Section("チェックイン") {
                if checkIns.isEmpty {
                    Text("記録はありません").foregroundStyle(Theme.muted)
                }
                ForEach(checkIns) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.habitTitle).font(.subheadline.weight(.semibold))
                            if item.isMinimum { Text("最小").font(.caption).foregroundStyle(Theme.seal) }
                            Spacer()
                            Text(Fmt.hm(item.at)).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Text(item.note).font(.subheadline)
                        if let undone = item.undoneAt {
                            Text("\(Fmt.hm(undone)) に取り消し").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .opacity(item.undoneAt == nil ? 1 : 0.5)
                }
            }
        }
        .navigationTitle(Fmt.cycle(cycle, dayStartMinute: model.cycleCalendar.dayStartMinute))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
    }
}
