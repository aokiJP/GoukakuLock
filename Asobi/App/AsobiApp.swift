import SwiftUI
import UIKit
import Combine

@main struct AsobiApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scene
    var body: some Scene {
        WindowGroup {
            PlayView().environmentObject(store)
                .preferredColorScheme(.dark)
                .onChange(of: scene) { _, value in
                    if value == .active { store.paused = false }
                    else { store.background() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in store.memoryWarning() }
        }
    }
}
struct PlayView: View {
    @EnvironmentObject var store: Store
    @State private var panel: Panel?
    @State private var note = ""
    @State private var saved = false
    enum Panel: String, Identifiable { case context, shelf; var id: String { rawValue } }
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let accent = Color(red: 0.78, green: 1, blue: 0.37)
    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.055, blue: 0.065).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text("asobi").font(.system(size: 23, weight: .black, design: .rounded)).foregroundStyle(accent)
                        Spacer()
                        Button { panel = .shelf } label: { Image(systemName: "square.stack") }.accessibilityLabel("保存した体験")
                        Button { panel = .context } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("今の気分と状況")
                    }.font(.title3).buttonStyle(.plain)
                    if let current = store.data.current {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(current.experience.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                            if current.moves.isEmpty { Text(current.experience.premise).foregroundStyle(.secondary) }
                        }
                        HStack(spacing: 14) {
                            ForEach(current.values.keys.sorted(), id: \.self) { key in
                                Text("\(key) \(current.values[key] ?? 0)").font(.callout.monospacedDigit()).foregroundStyle(accent)
                            }
                            Spacer(minLength: 0)
                            if let seconds = current.remaining, !current.finished {
                                Text("\(seconds)s").monospacedDigit().accessibilityLabel("残り\(seconds)秒")
                            }
                        }
                        Text(current.node.text).font(.title2).lineSpacing(7).frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                            .padding(24).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 28))
                        if current.finished {
                            primary("この先をつくる", icon: "arrow.up.right") { store.react(true) }
                            Button("違う遊びへ") { store.react(false) }.frame(maxWidth: .infinity)
                        } else {
                            if current.node.actions.contains(where: \.input) {
                                TextField("思いついたこと", text: $note, axis: .vertical)
                                    .lineLimit(1...4).padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                                    .onChange(of: note) { _, value in note = String(value.prefix(200)) }
                            }
                            VStack(spacing: 12) {
                                ForEach(current.node.actions) { action in
                                    primary(action.label, icon: action.input ? "pencil" : "arrow.right") { store.act(action, note: note); note = "" }
                                        .disabled(action.input && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                        HStack(spacing: 24) {
                            Button { store.generate("今の発見を引き継いで、ルールと展開を途中変更") } label: { Image(systemName: "shuffle") }.accessibilityLabel("途中変更")
                            Button { store.save(); saved = true } label: { Image(systemName: saved ? "bookmark.fill" : "bookmark") }.accessibilityLabel("保存")
                            Spacer()
                            Button { store.generate() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("再生成")
                        }.font(.title3).foregroundStyle(.secondary).buttonStyle(.plain)
                    } else if !store.generating {
                        Spacer(minLength: 65)
                        Text("まだない遊びを、\nここで。").font(.system(size: 42, weight: .bold, design: .rounded))
                        primary("つくる", icon: "sparkles") { store.generate() }
                    }
                    if let error = store.error {
                        Text(error).font(.callout).foregroundStyle(.orange)
                        Button("もう一度つくる") { store.generate() }
                    }
                    if store.generating {
                        HStack { ProgressView(); Text("ひらめきを形にしています").font(.callout); Spacer(); Button("中止") { store.cancel() } }
                            .padding(18).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }
                }.padding(24).frame(maxWidth: 650)
            }
            .disabled(store.generating && store.data.current != nil)
        }
        .tint(accent)
        .safeAreaInset(edge: .bottom) {
            if store.generating && store.data.current != nil { Button("生成を中止") { store.cancel() }.padding().frame(maxWidth: .infinity).background(.ultraThinMaterial) }
        }
        .sheet(item: $panel, onDismiss: { store.sheetOpen = false; store.persist() }) { selected in
            Group { if selected == .context { ContextView() } else { ShelfView() } }
                .environmentObject(store).presentationDragIndicator(.visible)
        }
        .onChange(of: panel) { _, value in store.sheetOpen = value != nil }
        .onChange(of: store.data.current?.id) { _, _ in note = ""; saved = false }
        .onChange(of: store.data.current?.nodeID) { _, _ in note = "" }
        .onReceive(clock) { _ in store.tick() }
        .task { if store.data.current == nil && store.error == nil { store.generate() } }
    }
    private func primary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title).multilineTextAlignment(.leading); Spacer(); Image(systemName: icon) }.font(.headline).padding(20).frame(maxWidth: .infinity).foregroundStyle(.black).background(accent, in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain)
    }
}
struct ContextView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("どこで・誰と", text: $store.data.profile.situation)
                TextField("興味", text: $store.data.profile.interests)
                TextField("今の気分", text: $store.data.profile.mood)
                Stepper("\(store.data.profile.minutes)分", value: $store.data.profile.minutes, in: 1...30)
                TextField("使える道具", text: $store.data.profile.tools)
                Button("この気分でつくる") { dismiss(); store.generate() }
            }.navigationTitle("いま").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
struct ShelfView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if store.data.saved.isEmpty { Text("遊びの途中で保存できます").foregroundStyle(.secondary) }
                ForEach(store.data.saved) { session in
                    Button { store.resume(session); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(session.experience.title).font(.headline); Text(session.node.text).lineLimit(2).font(.caption).foregroundStyle(.secondary) }
                    }
                }.onDelete { store.data.saved.remove(atOffsets: $0); store.persist() }
            }.navigationTitle("つづき").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
