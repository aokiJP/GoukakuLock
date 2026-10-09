import SwiftUI
import UIKit
import GoukakuCore

/// 見た目の芯:「答案用紙と赤ペン」。
/// 白い紙・紺の墨・朱の印。達成は朱の ◯、最小版は △、未達成は ✕(採点の赤ペンと同じ記号)。
/// 状態は丸い印(はんこ)1つで表し、見出しは明朝で、本文はゴシックで書く。
enum Theme {
    /// 墨(本文・ロック中)
    static let ink = dynamic(light: 0x1D2433, dark: 0xE6EAF2)
    /// 朱(合格印・達成・主要なボタン)
    static let seal = dynamic(light: 0xC93A2B, dark: 0xF0614F)
    /// 罫線(答案用紙の罫)
    static let rule = dynamic(light: 0xC9D3E0, dark: 0x3A4352)
    /// 紙(画面の地)
    static let paper = dynamic(light: 0xFFFFFF, dark: 0x101318)
    /// 一段沈んだ紙(カードの地)
    static let paperSunken = dynamic(light: 0xF3F5F8, dark: 0x1A1E26)
    /// 緊急解除の琥珀
    static let amber = dynamic(light: 0xB86E00, dark: 0xF2A43A)
    /// 休養日の青緑
    static let rest = dynamic(light: 0x23807A, dark: 0x4CC2B8)
    /// 補助の文字
    static let muted = dynamic(light: 0x5E6778, dark: 0x9AA3B4)
    /// 鉛筆(相棒AIの書き込み。採点の赤ペンとは分ける)
    static let pencil = dynamic(light: 0x3D5A80, dark: 0x9DB8E0)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// 見出し(明朝)
    static func heading(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .serif, weight: .bold)
    }

    /// 大きな数字(明朝の数字)
    static func numeral(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// 丸い印(はんこ)。状態を1〜2文字で表す。
struct SealView: View {
    var text: String
    var color: Color
    /// 朱肉で押したように塗るか(達成)、枠だけか(それ以外)
    var filled: Bool
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? color : Color.clear)
            Circle()
                .strokeBorder(color, lineWidth: size * 0.055)
            Circle()
                .strokeBorder(filled ? Theme.paper.opacity(0.55) : color.opacity(0.45), lineWidth: 1)
                .padding(size * 0.1)
            Text(text)
                .font(.system(size: text.count > 1 ? size * 0.3 : size * 0.44, weight: .heavy, design: .serif))
                .foregroundStyle(filled ? Theme.paper : color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-8))
        .accessibilityHidden(true)
    }
}

/// 採点の記号(履歴のカレンダー・統計で使う)
struct MarkView: View {
    var outcome: OutcomeMark
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch outcome {
            case .maru:
                Circle().strokeBorder(Theme.seal, lineWidth: size * 0.14)
            case .sankaku:
                Triangle().stroke(Theme.seal, style: StrokeStyle(lineWidth: size * 0.13, lineJoin: .round))
                    .padding(size * 0.06)
            case .batsu:
                Image(systemName: "xmark").font(.system(size: size * 0.8, weight: .bold)).foregroundStyle(Theme.ink)
            case .rest:
                Text("休").font(.system(size: size * 0.75, weight: .bold, design: .serif)).foregroundStyle(Theme.rest)
            case .paused:
                Image(systemName: "pause.fill").font(.system(size: size * 0.65)).foregroundStyle(Theme.muted)
            case .none:
                Image(systemName: "minus").font(.system(size: size * 0.7, weight: .semibold)).foregroundStyle(Theme.muted)
            case .pending:
                Circle().strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            case .blank:
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

enum OutcomeMark {
    case maru, sankaku, batsu, rest, paused, none, pending, blank
}

/// 帯(直近の日々)の1マス。まだ記録のない日も小さな点で枠を見せ、「埋めていく」形にする
struct SlotMarkView: View {
    var outcome: OutcomeMark
    var size: CGFloat = 16

    var body: some View {
        if outcome == .blank {
            Circle()
                .fill(Theme.rule)
                .frame(width: max(3, size * 0.3), height: max(3, size * 0.3))
                .frame(width: size, height: size)
        } else {
            MarkView(outcome: outcome, size: size)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.08))
        p.closeSubpath()
        return p
    }
}

/// 主要な操作のボタン(朱)
struct SealButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Theme.seal : Theme.muted.opacity(0.5))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// 罫線つきの枠(答案用紙の欄)
struct RuledBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            )
    }
}

// MARK: - 状態の色

extension StatusSummary.Tone {
    /// 印と強調に使う色
    var color: Color {
        switch self {
        case .locked, .grace: return Theme.ink
        case .achieved, .earn: return Theme.seal
        case .emergency: return Theme.amber
        case .rest: return Theme.rest
        case .idle: return Theme.muted
        }
    }

    /// 朱肉で押したように塗る(達成だけ)
    var filled: Bool { self == .achieved }
}
