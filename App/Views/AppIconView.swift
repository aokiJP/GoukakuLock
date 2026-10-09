import SwiftUI
import UIKit

/// 節目で解放される別アイコン(仕様書 第9.4節:変えるのは本人が選んだときだけ)
struct AppIconOption: Identifiable {
    let id: String
    /// UIApplication に渡す名前(nil は元のアイコン)
    let iconName: String?
    let label: String
    /// 最長の連続日数がこれ以上で解放
    let unlockStreak: Int
    let preview: String

    static let all: [AppIconOption] = [
        AppIconOption(id: "Shu", iconName: nil, label: "朱", unlockStreak: 0, preview: "IconPreview-Shu"),
        AppIconOption(id: "Sumi", iconName: "AppIcon-Sumi", label: "墨", unlockStreak: 7, preview: "IconPreview-Sumi"),
        AppIconOption(id: "Kin", iconName: "AppIcon-Kin", label: "金", unlockStreak: 30, preview: "IconPreview-Kin"),
        AppIconOption(id: "Sakura", iconName: "AppIcon-Sakura", label: "桜", unlockStreak: 100, preview: "IconPreview-Sakura"),
    ]
}

struct AppIconView: View {
    @Environment(AppModel.self) private var model
    @State private var current: String?
    @State private var changed = 0

    var body: some View {
        let longest = model.stats().longest
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("連続記録の節目で、アイコンの印が増えます。いまの最長は \(longest)日です。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    ForEach(AppIconOption.all) { option in
                        let unlocked = longest >= option.unlockStreak
                        Button {
                            guard unlocked else { return }
                            Task { await choose(option) }
                        } label: {
                            VStack(spacing: 8) {
                                Image(option.preview)
                                    .resizable()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.rule))
                                    .saturation(unlocked ? 1 : 0)
                                    .opacity(unlocked ? 1 : 0.45)
                                    .overlay {
                                        if !unlocked {
                                            Image(systemName: "lock.fill").font(.title2).foregroundStyle(Theme.ink)
                                        }
                                    }
                                Text(option.label)
                                    .font(Theme.heading(.headline))
                                    .foregroundStyle(Theme.ink)
                                Text(unlocked ? (current == option.iconName ? "使用中" : "使う") : "連続\(option.unlockStreak)日で解放")
                                    .font(.caption)
                                    .foregroundStyle(current == option.iconName ? Theme.seal : Theme.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(current == option.iconName ? Theme.seal : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label)のアイコン、\(unlocked ? "解放済み" : "連続\(option.unlockStreak)日で解放")")
                    }
                }
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("アイコン")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: changed)
        .onAppear { current = UIApplication.shared.alternateIconName }
    }

    private func choose(_ option: AppIconOption) async {
        guard UIApplication.shared.supportsAlternateIcons, current != option.iconName else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(option.iconName)
            current = option.iconName
            changed += 1
        } catch {
            model.show("アイコンを変えられませんでした", error.localizedDescription)
        }
    }
}
