import SwiftUI

/// Pro Pen 3 的设计坐标（横放，笔尖朝左）。标准握把版本，长径比约 18:1
enum PenGeo {
    static let size = CGSize(width: 620, height: 90)
    static let cy: CGFloat = 45
    static let tipX: CGFloat = 66
    static let nibEnd: CGFloat = 77
    static let coneEnd: CGFloat = 110
    static let endX: CGFloat = 554
    static let r: CGFloat = 13
    /// 侧键凹槽
    static let wellX0: CGFloat = 136, wellX1: CGFloat = 268
    /// 三颗侧键（靠笔尖的是下键）的中心 x
    static let buttons: [CGFloat] = [160, 202, 244]
    static let buttonW: CGFloat = 34
    static let seamX: CGFloat = 380
    static let slots = ["p1", "p2", "p3"]
    static let names = [L("下键"), L("中键"), L("上键")]
}

struct PenDrawing {
    var lit: Set<String> = []
    var selected: String? = nil
    var hover: String? = nil

    private static func g(_ v: Double) -> Color { Color(red: v, green: v * 1.004, blue: v * 1.02) }

    /// 横截面明暗（取自官方产品图）：上沿细亮边、上部偏暗、中线稍上一条宽高光、下半很暗、最下沿一道反光
    /// hi 为高光强度（握把 1，笔杆 0.75，锥体 0.85）
    private func section(_ top: CGFloat, _ bottom: CGFloat, _ f: Fit, hi: Double, base: Double = 0) -> GraphicsContext.Shading {
        func v(_ x: Double) -> Color { Self.g(x + base) }
        let h = 0.24 + 0.20 * hi
        return .linearGradient(Gradient(stops: [
            .init(color: v(0.27), location: 0),
            .init(color: v(0.22), location: 0.07),
            .init(color: v(0.215), location: 0.22),
            .init(color: v(h), location: 0.42),
            .init(color: v(h - 0.06), location: 0.52),
            .init(color: v(0.14), location: 0.68),
            .init(color: v(0.115), location: 0.84),
            .init(color: v(0.24), location: 0.95),
            .init(color: v(0.33), location: 1),
        ]), startPoint: f.p(0, top), endPoint: f.p(0, bottom))
    }

    /// 握把的细颗粒（固定伪随机）
    private static let grain: (Path, Path) = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        var a = Path(), b = Path()
        for _ in 0..<7000 {
            let x = PenGeo.coneEnd + rnd() * (PenGeo.seamX - PenGeo.coneEnd)
            let y = PenGeo.cy - PenGeo.r + rnd() * PenGeo.r * 2
            let s = 0.10 + rnd() * 0.12
            if rnd() > 0.5 { a.addEllipse(in: CGRect(x: x, y: y, width: s, height: s)) }
            else { b.addEllipse(in: CGRect(x: x, y: y, width: s, height: s)) }
        }
        return (a, b)
    }()

    func draw(_ ctx: GraphicsContext, _ f: Fit) {
        let cy = PenGeo.cy, r = PenGeo.r
        let top = cy - r, bot = cy + r
        // 落影
        var sh = ctx
        sh.addFilter(.blur(radius: f.v(6)))
        sh.fill(Path(roundedRect: CGRect(origin: f.p(PenGeo.coneEnd, bot + 3), size: CGSize(width: f.v(PenGeo.endX - PenGeo.coneEnd), height: f.v(5))),
                     cornerRadius: f.v(2.5)), with: .color(.black.opacity(0.22)))

        // 外形：锥体 + 直筒 + 平头笔尾
        let tipR: CGFloat = 2.6
        var outline = Path()
        outline.move(to: f.p(PenGeo.nibEnd, cy - tipR))
        outline.addCurve(to: f.p(PenGeo.coneEnd, top), control1: f.p(PenGeo.nibEnd + 12, cy - tipR - 4.5), control2: f.p(PenGeo.coneEnd - 12, top))
        outline.addLine(to: f.p(PenGeo.endX - 2, top))
        outline.addQuadCurve(to: f.p(PenGeo.endX, top + 2), control: f.p(PenGeo.endX, top))
        outline.addLine(to: f.p(PenGeo.endX, bot - 2))
        outline.addQuadCurve(to: f.p(PenGeo.endX - 2, bot), control: f.p(PenGeo.endX, bot))
        outline.addLine(to: f.p(PenGeo.coneEnd, bot))
        outline.addCurve(to: f.p(PenGeo.nibEnd, cy + tipR), control1: f.p(PenGeo.coneEnd - 12, bot), control2: f.p(PenGeo.nibEnd + 12, cy + tipR + 4.5))
        outline.closeSubpath()

        func region(_ x0: CGFloat, _ x1: CGFloat) -> Path {
            Path(CGRect(origin: f.p(x0, top - 1), size: CGSize(width: f.v(x1 - x0), height: f.v(r * 2 + 2))))
        }
        var body = ctx
        body.clip(to: outline)
        // 锥体：硬塑料，略亮
        var cone = body; cone.clip(to: region(PenGeo.nibEnd - 1, PenGeo.coneEnd + 0.5))
        cone.fill(outline, with: section(top, bot, f, hi: 0.85, base: 0.01))
        // 握把：软胶哑光，高光更宽更柔，带细颗粒
        var grip = body; grip.clip(to: region(PenGeo.coneEnd, PenGeo.seamX))
        grip.fill(outline, with: section(top, bot, f, hi: 1.0))
        var gs = grip
        gs.translateBy(x: f.origin.x, y: f.origin.y); gs.scaleBy(x: f.scale, y: f.scale)
        gs.fill(Self.grain.0, with: .color(.white.opacity(0.07)))
        gs.fill(Self.grain.1, with: .color(.black.opacity(0.14)))
        // 笔杆：硬塑料，更暗更平滑，高光窄一点
        var back = body; back.clip(to: region(PenGeo.seamX, PenGeo.endX + 1))
        back.fill(outline, with: section(top, bot, f, hi: 0.7, base: -0.015))
        // 笔尾端面一点暗
        back.fill(region(PenGeo.endX - 1.6, PenGeo.endX + 1), with: .color(.black.opacity(0.25)))

        // 锥体与握把的分界：一道很细的缝
        var c0 = Path(); c0.move(to: f.p(PenGeo.coneEnd, top + 0.3)); c0.addLine(to: f.p(PenGeo.coneEnd, bot - 0.3))
        body.stroke(c0, with: .color(.black.opacity(0.45)), lineWidth: f.v(0.4))
        // 握把与笔杆的接缝
        var seam = Path(); seam.move(to: f.p(PenGeo.seamX, top)); seam.addLine(to: f.p(PenGeo.seamX, bot))
        body.stroke(seam, with: .color(.black.opacity(0.7)), lineWidth: f.v(0.7))
        var seamHL = Path(); seamHL.move(to: f.p(PenGeo.seamX + 0.7, top + 1)); seamHL.addLine(to: f.p(PenGeo.seamX + 0.7, bot - 1))
        body.stroke(seamHL, with: .color(.white.opacity(0.08)), lineWidth: f.v(0.4))

        // 笔芯：浅灰半透明塑料
        let nib = CGRect(origin: f.p(PenGeo.tipX, cy - 1.3), size: CGSize(width: f.v(PenGeo.nibEnd - PenGeo.tipX + 1.5), height: f.v(2.6)))
        ctx.fill(Path(roundedRect: nib, cornerSize: CGSize(width: f.v(1.3), height: f.v(1.3))),
                 with: .linearGradient(Gradient(colors: [Self.g(0.80), Self.g(0.93), Self.g(0.70)]),
                                       startPoint: f.p(0, cy - 1.3), endPoint: f.p(0, cy + 1.3)))

        // 侧键凹槽：长圆形下沉，上内壁背光、下内壁受光
        let wh: CGFloat = 13.0
        let well = CGRect(origin: f.p(PenGeo.wellX0, cy - wh / 2 - 0.8), size: CGSize(width: f.v(PenGeo.wellX1 - PenGeo.wellX0), height: f.v(wh)))
        let wellPath = Path(roundedRect: well, cornerRadius: f.v(wh / 2), style: .continuous)
        ctx.fill(wellPath, with: section(well.minY / f.scale - f.origin.y / f.scale, well.maxY / f.scale - f.origin.y / f.scale, f, hi: 0.55, base: -0.04))
        var inner = ctx
        inner.clip(to: wellPath)
        inner.stroke(wellPath.offsetBy(dx: 0, dy: f.v(0.9)), with: .color(.black.opacity(0.7)), lineWidth: f.v(1.4))
        ctx.stroke(wellPath.offsetBy(dx: 0, dy: -f.v(0.25)), with: .color(.white.opacity(0.10)), lineWidth: f.v(0.35))

        // 三颗胶囊侧键：微凸，顶面跟随笔身的光
        for (i, x) in PenGeo.buttons.enumerated() {
            let slot = PenGeo.slots[i]
            let bh: CGFloat = 8.6
            let br = CGRect(origin: f.p(x - PenGeo.buttonW / 2, cy - bh / 2 - 0.8), size: CGSize(width: f.v(PenGeo.buttonW), height: f.v(bh)))
            let bp = Path(roundedRect: br, cornerRadius: f.v(bh / 2), style: .continuous)
            var s2 = ctx
            s2.addFilter(.shadow(color: .black.opacity(0.65), radius: f.v(0.6), y: f.v(0.45)))
            s2.fill(bp, with: .linearGradient(Gradient(stops: [
                .init(color: Self.g(0.30), location: 0),
                .init(color: Self.g(0.36), location: 0.35),
                .init(color: Self.g(0.22), location: 0.7),
                .init(color: Self.g(0.15), location: 1),
            ]), startPoint: CGPoint(x: br.midX, y: br.minY), endPoint: CGPoint(x: br.midX, y: br.maxY)))
            ctx.stroke(bp, with: .color(.black.opacity(0.5)), lineWidth: f.v(0.3))
            var tl = Path()
            tl.move(to: CGPoint(x: br.minX + f.v(3.5), y: br.minY + f.v(0.7)))
            tl.addLine(to: CGPoint(x: br.maxX - f.v(3.5), y: br.minY + f.v(0.7)))
            ctx.stroke(tl, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: f.v(0.35), lineCap: .round))
            if i == 1 {
                ctx.fill(Path(ellipseIn: CGRect(origin: f.p(x - 1.1, cy - 1.9), size: CGSize(width: f.v(2.2), height: f.v(2.2)))),
                         with: .color(.black.opacity(0.35)))
            }
            let on = lit.contains(slot) || selected == slot
            if on { ctx.fill(bp, with: .color(Color.accentColor.opacity(0.85))) }
            else if hover == slot { ctx.fill(bp, with: .color(.white.opacity(0.10))) }
        }

        // 凹印 wacom 字样
        let h: CGFloat = 4.4
        let (word, _) = Glyphs.word("wacom", height: f.v(h), origin: f.p(292, cy - h / 2 - 1.2))
        let st = Glyphs.style(f.v(h))
        ctx.stroke(word.offsetBy(dx: 0, dy: f.v(0.35)), with: .color(.white.opacity(0.07)), style: st)
        ctx.stroke(word, with: .color(.black.opacity(0.5)), style: st)

        // 轮廓
        ctx.stroke(outline, with: .color(.black.opacity(0.45)), lineWidth: f.v(0.35))
    }
}

/// 笔页面：渲染居中，三个侧键的标注上下错开
struct PenPage: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: String?

    var body: some View {
        ActionPanelHost(open: editing != nil, onClose: { editing = nil }) {
            PenStage(editing: $editing)
        } panel: {
            if let slot = editing, let i = PenGeo.slots.firstIndex(of: slot) {
                ButtonEditor(button: 0, positionName: LF("笔 · %@", PenGeo.names[i]), slotPrefix: slot) { editing = nil }
                    .id(slot)
            }
        }
    }
}

struct PenStage: View {
    @EnvironmentObject var model: AppModel
    @Binding var editing: String?
    @State private var hover: String?
    @State private var shown = KeysStage.snapshot

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let aspect = PenGeo.size.width / PenGeo.size.height
            let rw = min(W - 80, 760)
            let rh = rw / aspect
            let rect = CGRect(x: (W - rw) / 2, y: H * 0.27 - rh / 2, width: rw, height: rh)
            let f = Fit(rect.size, design: PenGeo.size)
            let toView: (CGFloat, CGFloat) -> CGPoint = { x, y in
                let q = f.p(CGPoint(x: x, y: y)); return CGPoint(x: q.x + rect.minX, y: q.y + rect.minY)
            }
            let bx = PenGeo.buttons.map { toView($0, PenGeo.cy).x }
            let labelXs: [CGFloat] = [bx[0] - 70, bx[1], bx[2] + 70]
            let ys: [CGFloat] = [rect.maxY + 50, rect.minY - 40, rect.maxY + 50]

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    PenDrawing(lit: model.penFlash, selected: editing, hover: hover).draw(ctx, f)
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .scaleEffect(shown ? 1 : 0.96)
                .opacity(shown ? 1 : 0)

                Canvas { ctx, _ in
                    for i in 0..<3 {
                        let slot = PenGeo.slots[i]
                        let on = editing == slot || hover == slot || model.penFlash.contains(slot)
                        let kp = toView(PenGeo.buttons[i], PenGeo.cy - 1)
                        let up = ys[i] < rect.minY
                        var p = Path()
                        p.move(to: CGPoint(x: labelXs[i], y: ys[i] + (up ? 20 : -22)))
                        p.addLine(to: CGPoint(x: labelXs[i], y: up ? rect.minY + 4 : rect.maxY - 4))
                        p.addLine(to: kp)
                        let style = StrokeStyle(lineWidth: on ? 1.2 : 0.75, lineCap: .round, lineJoin: .round)
                        // 笔身外跟随系统线色，压在黑色笔身上的部分用白色
                        let a = toView(PenGeo.tipX, PenGeo.cy - PenGeo.r), b = toView(PenGeo.endX, PenGeo.cy + PenGeo.r)
                        let pen = Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
                        var outside = ctx
                        outside.clip(to: pen, options: .inverse)
                        outside.stroke(p, with: .color(Color.primary.opacity(on ? 0.9 : 0.32)), style: style)
                        var inside = ctx
                        inside.clip(to: pen)
                        inside.stroke(p, with: .color(Color.white.opacity(on ? 0.95 : 0.5)), style: style)
                        ctx.fill(Path(ellipseIn: CGRect(x: kp.x - 2, y: kp.y - 2, width: 4, height: 4)), with: .color(Color.white.opacity(on ? 1 : 0.8)))
                    }
                }
                .allowsHitTesting(false)
                .opacity(shown ? 1 : 0)

                ForEach(0..<3, id: \.self) { i in
                    PenCallout(index: i, editing: $editing, hover: $hover, up: ys[i] < rect.minY)
                        .position(x: labelXs[i], y: ys[i])
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2 + Double(i) * 0.06), value: shown)
                }

                // 下半部分：笔尖手感 + 测试区
                HStack(alignment: .top, spacing: 28) {
                    TipFeel()
                        .frame(width: 230)
                    PressurePad()
                }
                .frame(width: min(W - 80, 760), height: max(160, H * 0.40))
                .position(x: W / 2, y: rect.maxY + 110 + max(160, H * 0.40) / 2)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.35), value: shown)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = true } }
    }
}

struct PenCallout: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    @Binding var editing: String?
    @Binding var hover: String?
    let up: Bool

    var body: some View {
        let slot = PenGeo.slots[index]
        let a = model.effectiveAction(slot)
        let on = editing == slot || hover == slot || model.penFlash.contains(slot)
        Button { editing = slot } label: {
            VStack(spacing: 4) {
                Text(a == nil || a?.type == "none" ? L("原功能") : model.title(of: a))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(a == nil || a?.type == "none" ? .secondary : .primary)
                ActionDetail(action: a)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in if h { hover = slot } else if hover == slot { hover = nil } }
    }
}

struct TipFeel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("笔尖手感").font(.system(size: 13, weight: .semibold))
            Slider(value: Binding(get: { model.penFeel }, set: { model.penFeel = ($0 * 4).rounded() / 4 }), in: -1...1)
            HStack {
                Text("软"); Spacer(); Text("硬")
            }
            .font(.caption).foregroundStyle(.secondary)
            // 压力曲线预览
            Canvas { ctx, size in
                let g = pow(2, model.penFeel * 1.5)
                var p = Path()
                for i in 0...40 {
                    let x = Double(i) / 40
                    let pt = CGPoint(x: x * size.width, y: size.height - pow(x, g) * size.height)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.08)), lineWidth: 1)
                ctx.stroke(p, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(height: 90)
            Button("恢复默认") { model.penFeel = 0 }
                .buttonStyle(.link)
                .font(.caption)
                .opacity(model.penFeel == 0 ? 0 : 1)
        }
    }
}

/// 测试区：用笔画一画，线条粗细跟随压力
struct PressurePad: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            PressureCanvas()
            Text("测试区").font(.caption).foregroundStyle(.tertiary).padding(10).allowsHitTesting(false)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PressureCanvas: NSViewRepresentable {
    func makeNSView(context: Context) -> PressureView { PressureView() }
    func updateNSView(_ v: PressureView, context: Context) {}
}

final class PressureView: NSView {
    private var strokes: [[(CGPoint, CGFloat)]] = []
    private var fade: Timer?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        fade?.invalidate()
        strokes.append([(convert(e.locationInWindow, from: nil), CGFloat(e.pressure))])
        needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].append((convert(e.locationInWindow, from: nil), CGFloat(e.pressure)))
        needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        fade?.invalidate()
        fade = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.strokes.removeAll(); self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.setStroke()
        for s in strokes {
            for i in 1..<max(1, s.count) {
                let p = NSBezierPath()
                p.lineCapStyle = .round
                p.lineWidth = 0.5 + 9 * max(s[i].1, 0.02)
                p.move(to: s[i - 1].0)
                p.line(to: s[i].0)
                p.stroke()
            }
        }
    }
}
