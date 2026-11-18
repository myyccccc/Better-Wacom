import AppKit
import SwiftUI

/// 单线、等粗、圆角方正的小写字形（与板子上印的字标同一风格）
/// 坐标以字高 1 为单位，原点在左上，y 向下
enum Glyphs {
    static let stroke: CGFloat = 0.14
    private static let e = stroke / 2

    static let widths: [Character: CGFloat] = ["w": 1.26, "a": 0.80, "c": 0.70, "o": 0.82, "m": 1.26]
    static let gap: CGFloat = 0.17

    /// 单个字形的中心线
    static func path(_ ch: Character, at x0: CGFloat, height h: CGFloat, origin: CGPoint) -> Path {
        let W = widths[ch] ?? 1
        let r: CGFloat = 0.36
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + (x0 + x) * h, y: origin.y + y * h) }
        var p = Path()
        switch ch {
        case "w", "m":
            let flip = ch == "m"
            func Y(_ y: CGFloat) -> CGFloat { flip ? 1 - y : y }
            let mid = W / 2
            // 两个相连的 u（m 为上下翻转）
            for (a, b) in [(e, mid), (mid, W - e)] {
                p.move(to: P(a, Y(e)))
                p.addLine(to: P(a, Y(1 - e - r)))
                p.addQuadCurve(to: P(a + r, Y(1 - e)), control: P(a, Y(1 - e)))
                p.addLine(to: P(b - r, Y(1 - e)))
                p.addQuadCurve(to: P(b, Y(1 - e - r)), control: P(b, Y(1 - e)))
                p.addLine(to: P(b, Y(e)))
            }
        case "a":
            p.addRoundedRect(in: CGRect(origin: P(e, e), size: CGSize(width: (W - 2 * e) * h, height: (1 - 2 * e) * h)),
                             cornerSize: CGSize(width: r * h, height: r * h), style: .continuous)
            p.move(to: P(W - e, e))
            p.addLine(to: P(W - e, 1 - e))
        case "c":
            p.move(to: P(W - e, e))
            p.addLine(to: P(e + r, e))
            p.addQuadCurve(to: P(e, e + r), control: P(e, e))
            p.addLine(to: P(e, 1 - e - r))
            p.addQuadCurve(to: P(e + r, 1 - e), control: P(e, 1 - e))
            p.addLine(to: P(W - e, 1 - e))
        default: // o
            p.addRoundedRect(in: CGRect(origin: P(e, e), size: CGSize(width: (W - 2 * e) * h, height: (1 - 2 * e) * h)),
                             cornerSize: CGSize(width: r * h, height: r * h), style: .continuous)
        }
        return p
    }

    /// 整个单词的中心线，返回路径和总宽度
    static func word(_ s: String, height h: CGFloat, origin: CGPoint) -> (Path, CGFloat) {
        var p = Path()
        var x: CGFloat = 0
        for (i, ch) in s.enumerated() {
            if i > 0 { x += gap }
            p.addPath(path(ch, at: x, height: h, origin: origin))
            x += widths[ch] ?? 1
        }
        return (p, x * h)
    }

    static func width(_ s: String) -> CGFloat {
        s.reduce(0) { $0 + (widths[$1] ?? 1) } + gap * CGFloat(max(0, s.count - 1))
    }

    static func style(_ h: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: stroke * h, lineCap: .round, lineJoin: .round)
    }
}

/// Better Wacom 标志：白色圆角方块 + 单线圆角 w
enum Logo {
    static let menuBarImage: NSImage = {
        let size = NSSize(width: 20, height: 16)
        let img = NSImage(size: size, flipped: true) { rect in
            let h: CGFloat = 9
            let w = Glyphs.widths["w"]! * h
            let (p, _) = Glyphs.word("w", height: h, origin: CGPoint(x: rect.midX - w / 2, y: rect.midY - h / 2))
            let ns = NSBezierPath(cgPath: p.cgPath)
            ns.lineWidth = 1.9
            ns.lineCapStyle = .round
            ns.lineJoinStyle = .round
            NSColor.black.setStroke()
            ns.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }()
}

struct LogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.91)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.22), radius: size * 0.04, y: size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            Canvas { ctx, s in
                let h = s.height * 0.36
                let w = Glyphs.widths["w"]! * h
                let (p, _) = Glyphs.word("w", height: h, origin: CGPoint(x: (s.width - w) / 2, y: (s.height - h) / 2))
                ctx.stroke(p, with: .color(Color(white: 0.08)), style: StrokeStyle(lineWidth: h * 0.19, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
