import SwiftUI
import GoukakuCore

/// 節目のお祝い:赤ペンのはなまるを描く(連続 3・7・14・30… 日、はじめての達成)
struct CelebrationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let celebration: Celebration
    @State private var progress: CGFloat = 0
    @State private var showText = false
    @State private var stamped = 0

    private var title: String {
        celebration.first ? "はじめての合格" : "\(celebration.streak)日連続"
    }

    private var message: String {
        if celebration.first { return "最初の一歩です。明日もこの調子で。" }
        switch celebration.streak {
        case ..<7: return "いい流れです。小さく続けよう。"
        case ..<30: return "習慣になりはじめています。"
        case ..<100: return "もう生活の一部です。"
        default: return "ここまで来たら、刺激を弱めても続くかもしれません。"
        }
    }

    var body: some View {
        ZStack {
            Theme.paper.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                HanamaruView(progress: progress)
                    .frame(width: 230, height: 230)
                VStack(spacing: 10) {
                    Text(title)
                        .font(Theme.heading(.largeTitle))
                        .foregroundStyle(Theme.ink)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Text("通算 \(celebration.total)日")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.seal)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 12)
                Spacer()
                VStack(spacing: 12) {
                    ShareCertificateButton(streak: celebration.streak, total: celebration.total)
                    Button("閉じる") { model.celebration = nil }
                        .font(.headline)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal)
                .opacity(showText ? 1 : 0)
            }
            .padding()
        }
        .sensoryFeedback(.success, trigger: stamped)
        .onAppear {
            if reduceMotion {
                progress = 1
                showText = true
                stamped += 1
                return
            }
            withAnimation(.easeInOut(duration: 1.5)) { progress = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(1.3)) { showText = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                stamped += 1
            }
        }
    }
}

/// 合格証(シェア用の画像)。載せるのは連続・通算と、本人が選んだときだけ目標の名前。
struct CertificateCard: View {
    var streak: Int
    var total: Int
    var goal: String?
    var date: Date

    var body: some View {
        ZStack {
            Color.white
            // 答案用紙の罫
            VStack(spacing: 22) {
                ForEach(0..<20, id: \.self) { _ in
                    Rectangle().fill(Color(red: 0.79, green: 0.83, blue: 0.88)).frame(height: 1)
                }
            }
            .padding(.top, 18)
            VStack(spacing: 12) {
                Text("合 格 証")
                    .font(.system(size: 34, weight: .heavy, design: .serif))
                    .foregroundStyle(Color(red: 0.11, green: 0.14, blue: 0.20))
                    .padding(.top, 24)
                // 先生が点数を花丸で囲むように、日数を花びらの輪で囲む
                ZStack {
                    HanamaruView(progress: 1, lineWidthRatio: 0.028, spiral: false)
                        .frame(width: 196, height: 196)
                    VStack(spacing: 0) {
                        Text("\(streak)")
                            .font(.system(size: 56, weight: .bold, design: .serif))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("日連続")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                    }
                    .frame(width: 112)
                    .foregroundStyle(Color(red: 0.11, green: 0.14, blue: 0.20))
                }
                if let goal, !goal.isEmpty {
                    Text(goal)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(Color(red: 0.11, green: 0.14, blue: 0.20))
                        .padding(.horizontal, 28)
                }
                Text("通算 \(total)日 達成")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.37, green: 0.40, blue: 0.47))
                Spacer()
                HStack {
                    Text(Self.dateText(date))
                    Spacer()
                    HStack(spacing: 6) {
                        SealView(text: "合格", color: Color(red: 0.79, green: 0.23, blue: 0.17), filled: true, size: 34)
                        Text("合格ロック")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.37, green: 0.40, blue: 0.47))
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 360, height: 450)
    }

    static func dateText(_ date: Date) -> String {
        let c = Fmt.calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日"
    }
}

/// 合格証を画像にしてシェアする(LINE・X・写真への保存など。送るかどうかは本人が決める)
struct ShareCertificateButton: View {
    @Environment(AppModel.self) private var model
    var streak: Int
    var total: Int
    @State private var includeGoal = false

    var body: some View {
        let goal = includeGoal ? model.today?.required.first?.title : nil
        let image = Self.render(streak: streak, total: total, goal: goal)
        VStack(spacing: 8) {
            if let image {
                ShareLink(item: image, preview: SharePreview("合格証", image: image)) {
                    Label("合格証をシェア", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SealButtonStyle())
            }
            Toggle("目標の名前も載せる", isOn: $includeGoal)
                .font(.footnote)
                .tint(Theme.seal)
        }
    }

    @MainActor
    static func render(streak: Int, total: Int, goal: String?) -> Image? {
        let renderer = ImageRenderer(content: CertificateCard(streak: streak, total: total, goal: goal, date: Date()))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
