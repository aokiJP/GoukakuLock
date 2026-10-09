import SwiftUI

/// 花丸(はなまる):先生が赤ペンで描く「よくできました」の印。
/// 中心から渦を巻き、そのまま外側に花びらを一周描いて、最後に払う。一筆書きなので trim で「描く」アニメーションができる。
struct HanamaruShape: Shape {
    var petals = 8

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()

        // 1. 渦巻き(少し揺らして手描きらしく)
        let turns: CGFloat = 2.3
        let steps = 160
        let r0 = size * 0.03, r1 = size * 0.25
        let theta0 = -CGFloat.pi / 2
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let theta = theta0 + t * turns * 2 * .pi
            let r = (r0 + (r1 - r0) * t) * (1 + 0.035 * sin(t * 19))
            let point = CGPoint(x: c.x + r * cos(theta), y: c.y + r * sin(theta))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }

        // 2. 花びら(渦の終わりの角度から一周)
        let ringR = size * 0.34
        let bulge = size * 0.12
        let start = theta0 + turns * 2 * .pi
        p.addLine(to: CGPoint(x: c.x + ringR * cos(start), y: c.y + ringR * sin(start)))
        for k in 1...petals {
            let angle = start + CGFloat(k) * 2 * .pi / CGFloat(petals)
            let mid = start + (CGFloat(k) - 0.5) * 2 * .pi / CGFloat(petals)
            let wobble = 1 + 0.06 * sin(CGFloat(k) * 2.3)
            let end = CGPoint(x: c.x + ringR * cos(angle), y: c.y + ringR * sin(angle))
            let control = CGPoint(x: c.x + (ringR + bulge * 2 * wobble) * cos(mid),
                                  y: c.y + (ringR + bulge * 2 * wobble) * sin(mid))
            p.addQuadCurve(to: end, control: control)
        }

        // 3. 払い
        let last = CGPoint(x: c.x + ringR * cos(start), y: c.y + ringR * sin(start))
        p.addQuadCurve(to: CGPoint(x: last.x + size * 0.13, y: last.y + size * 0.16),
                       control: CGPoint(x: last.x + size * 0.12, y: last.y + size * 0.02))
        return p
    }
}

/// 花丸を赤ペンで描く(progress 0→1 で描き進める)
struct HanamaruView: View {
    var progress: CGFloat = 1
    var lineWidthRatio: CGFloat = 0.034

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            HanamaruShape()
                .trim(from: 0, to: progress)
                .stroke(Theme.seal, style: StrokeStyle(lineWidth: max(1.5, size * lineWidthRatio),
                                                       lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("はなまる")
    }
}
