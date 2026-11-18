import SwiftUI

/// 产品渲染风格的板子顶部：按实物照片的结构和比例，用中性冷灰 + 影棚柔光重新绘制
/// 光源：左上方大面积柔光，右侧自然衰减；所有明暗都用低对比度渐变表现
struct TopDrawing {
    let st: PadState
    private var accent: Color { .accentColor }

    // MARK: 色板（中性冷灰）

    private static func g(_ v: Double) -> Color { Color(red: v, green: v * 1.006, blue: v * 1.035) }
    private static let groove = g(0.075)
    private static let partBase = 0.215

    // MARK: 材质：泼墨塑料（不规则碎屑 + 云状起伏 + 微颗粒），固定伪随机，合并成少量路径

    private struct Texture {
        var mottle: [(CGPoint, CGFloat, Double)]      // 云状起伏：中心、半径、明暗（正亮负暗）
        var flecks: [(Path, Double, Bool)]            // 碎屑：路径、不透明度、是否柔化（嵌在表层下）
        var micro: (Path, Path)                       // 微颗粒：亮、暗
        var sensorMicro: Path
    }

    private static let texture: Texture = {
        var seed: UInt64 = 0x51F15EED1234ABCD
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        let W = TopGeo.bodyW, S = TopGeo.stripH
        func onPart(_ p: CGPoint) -> Bool {
            for left in [true, false] {
                for c in [TopGeo.ring(left), TopGeo.dial(left)] where hypot(p.x - c.x, p.y - c.y) < TopGeo.ringR + 0.8 { return true }
            }
            return false
        }

        var mottle: [(CGPoint, CGFloat, Double)] = []
        for _ in 0..<90 {
            mottle.append((CGPoint(x: rnd() * W, y: rnd() * S), 4 + rnd() * 14, Double(rnd() - 0.5) * 0.07))
        }

        // 不规则碎屑：5~7 边的小多边形，带随机旋转和拉伸
        func fleck(at p: CGPoint, size s: CGFloat) -> Path {
            let n = 5 + Int(rnd() * 3)
            let rot = rnd() * .pi * 2
            let stretch = 0.6 + rnd() * 0.8
            var path = Path()
            for k in 0..<n {
                let a = Double(k) / Double(n) * 2 * .pi
                let rr = s * (0.55 + rnd() * 0.5)
                let x = cos(a) * rr * stretch, y = sin(a) * rr
                let pt = CGPoint(x: p.x + x * cos(rot) - y * sin(rot), y: p.y + x * sin(rot) + y * cos(rot))
                k == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
            return path
        }
        // 档位：(数量, 尺寸范围, 不透明度, 柔化)
        let tiers: [(Int, ClosedRange<CGFloat>, Double, Bool)] = [
            (15000, 0.10...0.22, 0.12, true),   // 嵌在表层下的细屑
            (9000, 0.14...0.30, 0.20, false),
            (3200, 0.24...0.44, 0.27, false),
            (800, 0.38...0.62, 0.20, true),     // 大颗、半透出
            (280, 0.28...0.52, 0.42, false),    // 少量清晰亮屑
        ]
        var flecks: [(Path, Double, Bool)] = []
        for (count, range, op, soft) in tiers {
            var p = Path()
            var placed = 0
            while placed < count {
                // 碎屑会成簇：一部分围绕上一个点
                let pt = CGPoint(x: rnd() * W, y: 0.4 + rnd() * (S - 0.8))
                placed += 1
                if onPart(pt) { continue }
                p.addPath(fleck(at: pt, size: range.lowerBound + rnd() * (range.upperBound - range.lowerBound)))
            }
            flecks.append((p, op, soft))
        }
        // 深色杂点
        var darkFleck = Path()
        for _ in 0..<2200 {
            let pt = CGPoint(x: rnd() * W, y: 0.4 + rnd() * (S - 0.8))
            if onPart(pt) { continue }
            darkFleck.addPath(fleck(at: pt, size: 0.10 + rnd() * 0.18))
        }
        flecks.append((darkFleck, -0.28, false))

        var mLight = Path(), mDark = Path()
        for _ in 0..<26000 {
            let pt = CGPoint(x: rnd() * W, y: rnd() * S)
            let s = 0.05 + rnd() * 0.06
            if rnd() > 0.5 { mLight.addRect(CGRect(x: pt.x, y: pt.y, width: s, height: s)) }
            else { mDark.addRect(CGRect(x: pt.x, y: pt.y, width: s, height: s)) }
        }
        var sensor = Path()
        for _ in 0..<9000 {
            let pt = CGPoint(x: rnd() * W, y: S + 0.6 + rnd() * 80)
            let s = 0.04 + rnd() * 0.05
            sensor.addRect(CGRect(x: pt.x, y: pt.y, width: s, height: s))
        }
        return Texture(mottle: mottle, flecks: flecks, micro: (mLight, mDark), sensorMicro: sensor)
    }()

    /// 静态层：机身、边框、分模线、材质、字标、感应区（不随动画重绘）
    func drawStatic(_ ctx: GraphicsContext, _ f: Fit) {
        drawBody(ctx, f)
    }

    /// 动画层：波轮、环形键、指示灯
    func drawDynamic(_ ctx: GraphicsContext, _ f: Fit) {
        for left in [true, false] {
            drawDial(ctx, f, left: left)
            drawRing(ctx, f, left: left)
        }
        drawLED(ctx, f)
    }

    func draw(_ ctx: GraphicsContext, _ f: Fit) {
        drawStatic(ctx, f)
        drawDynamic(ctx, f)
    }

    private func level(_ t: PadTarget) -> Double {
        var l = st.lit(t)
        if st.selected == t { l = max(l, 0.9) }
        if st.pulse == t { l = max(l, 0.4 + 0.4 * sin(st.time * 6)) }
        return l
    }

    // MARK: - 机身

    /// 边框宽度：左、右、上（实测）
    static let bevel: CGFloat = 0
    private static let railL: CGFloat = 4.3, railR: CGFloat = 4.7, railT: CGFloat = 0

    private func drawBody(_ ctx: GraphicsContext, _ f: Fit) {
        let W = TopGeo.bodyW, S = TopGeo.stripH
        let bottom = TopGeo.region.maxY + 30
        let outerRect = CGRect(origin: f.p(0, 0), size: CGSize(width: f.v(W), height: f.v(bottom)))
        let outer = Path(roundedRect: outerRect, cornerRadius: f.v(3.2), style: .continuous)
        let panelRect = CGRect(origin: f.p(Self.railL, Self.railT),
                               size: CGSize(width: f.v(W - Self.railL - Self.railR), height: f.v(bottom)))
        let panel = Path(roundedRect: panelRect, cornerRadius: f.v(0.9), style: .continuous)

        // 落影
        var far = ctx
        far.addFilter(.shadow(color: .black.opacity(0.30), radius: f.v(10), y: f.v(5)))
        far.fill(outer, with: .color(Self.g(0.14)))
        var near = ctx
        near.addFilter(.shadow(color: .black.opacity(0.45), radius: f.v(0.9), y: f.v(0.5)))
        near.fill(outer, with: .color(Self.g(0.14)))

        drawTopKeys(ctx, f)

        // 边框：圆柱面，外侧暗、三分之一处一道柔和高光、靠近分模线再暗下去
        var rail = ctx
        rail.clip(to: outer)
        rail.fill(outer, with: .color(Self.g(0.155)))
        for left in [true, false] {
            let w = left ? Self.railL : Self.railR
            let x0 = left ? outerRect.minX : outerRect.maxX - f.v(w)
            let r = CGRect(x: x0, y: outerRect.minY, width: f.v(w), height: outerRect.height)
            // 和顶条同一种泼墨塑料
            var tex = rail
            tex.clip(to: Path(r))
            speckle(tex, f, Path(r), tiles: 3)
            // 圆柱面明暗：外侧暗、偏外三分之一一道柔光、靠缝处再暗
            let stops: [Gradient.Stop] = [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.10), location: 0.22),
                .init(color: .white.opacity(left ? 0.07 : 0.04), location: 0.42),
                .init(color: .black.opacity(0.0), location: 0.7),
                .init(color: .black.opacity(0.28), location: 1),
            ]
            tex.fill(Path(r), with: .linearGradient(Gradient(stops: left ? stops : stops.reversed().map { .init(color: $0.color, location: 1 - $0.location) }),
                                                    startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
        }
        // 外沿细高光（左侧更亮）
        ctx.stroke(outer, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0.05)]),
                                                startPoint: CGPoint(x: outerRect.minX, y: 0), endPoint: CGPoint(x: outerRect.maxX, y: 0)),
                   lineWidth: f.v(0.3))

        // 顶面面板
        var c = ctx
        c.clip(to: panel)

        // 感应区：光滑哑光，左上亮、右下暗，极细微颗粒
        let seamY = f.p(0, S).y
        let sensor = CGRect(x: panelRect.minX, y: seamY, width: panelRect.width, height: panelRect.maxY - seamY)
        c.fill(Path(sensor), with: .linearGradient(Gradient(colors: [Self.g(0.212), Self.g(0.176)]),
                                                   startPoint: CGPoint(x: sensor.minX, y: sensor.minY),
                                                   endPoint: CGPoint(x: sensor.maxX, y: sensor.minY + f.v(70))))
        var sm = c
        sm.translateBy(x: f.origin.x, y: f.origin.y); sm.scaleBy(x: f.scale, y: f.scale)
        sm.fill(Self.texture.sensorMicro, with: .color(.white.opacity(0.025)))
        for d in TopGeo.dots {
            let q = f.p(d)
            var gl = c
            gl.addFilter(.blur(radius: f.v(0.5)))
            gl.fill(Path(ellipseIn: CGRect(x: q.x - f.v(1), y: q.y - f.v(1), width: f.v(2), height: f.v(2))), with: .color(.white.opacity(0.22)))
            c.fill(Path(ellipseIn: CGRect(x: q.x - f.v(0.5), y: q.y - f.v(0.5), width: f.v(1.0), height: f.v(1.0))), with: .color(.white.opacity(0.85)))
        }

        // 顶条底色：左上受光
        let strip = CGRect(x: panelRect.minX, y: panelRect.minY, width: panelRect.width, height: seamY - panelRect.minY)
        speckle(c, f, Path(strip), tiles: 1)
        // 哑光表层：整体再压一层很淡的灰，让碎屑像嵌在里面
        c.fill(Path(strip), with: .color(Self.g(0.22).opacity(0.06)))

        // 接缝
        c.fill(Path(CGRect(x: strip.minX, y: seamY - f.v(0.8), width: strip.width, height: f.v(1.3))), with: .color(.black.opacity(0.85)))
        c.fill(Path(CGRect(x: strip.minX, y: seamY + f.v(0.3), width: strip.width, height: f.v(0.45))), with: .color(.white.opacity(0.05)))

        drawLogo(c, f)

        // 分模线：面板与边框之间一道深缝，边框一侧有一丝反光
        var seams = Path()
        for x in [panelRect.minX, panelRect.maxX] {
            seams.move(to: CGPoint(x: x, y: panelRect.minY + f.v(0.4)))
            seams.addLine(to: CGPoint(x: x, y: panelRect.maxY))
        }
        ctx.stroke(seams, with: .color(.black.opacity(0.85)), lineWidth: f.v(0.62))
        var lip = ctx
        lip.clip(to: outer)
        // 只在两侧竖缝外侧有反光
        for x in [panelRect.minX - f.v(0.5), panelRect.maxX + f.v(0.5)] {
            lip.fill(Path(CGRect(x: x - f.v(0.11), y: panelRect.minY + f.v(1.2), width: f.v(0.22), height: panelRect.height)),
                     with: .color(.white.opacity(0.07)))
        }
        // 上沿：圆角向下过渡 —— 最外沿暗、往里一道柔和受光带，再融进平面
        var edge = ctx
        edge.clip(to: outer)
        let band = CGRect(x: outerRect.minX, y: outerRect.minY, width: outerRect.width, height: f.v(4.2))
        edge.fill(Path(band), with: .linearGradient(Gradient(stops: [
            .init(color: .black.opacity(0.62), location: 0),
            .init(color: .black.opacity(0.18), location: 0.10),
            .init(color: .white.opacity(0.10), location: 0.24),
            .init(color: .white.opacity(0.05), location: 0.45),
            .init(color: .white.opacity(0.0), location: 1),
        ]), startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
        // 左右两端的圆角也带一点暗边
        for left in [true, false] {
            let x = left ? outerRect.minX : outerRect.maxX - f.v(1.4)
            let r = CGRect(x: x, y: outerRect.minY, width: f.v(1.4), height: outerRect.height)
            edge.fill(Path(r), with: .linearGradient(Gradient(colors: [.black.opacity(0.35), .black.opacity(0)]),
                                                     startPoint: CGPoint(x: left ? r.minX : r.maxX, y: 0),
                                                     endPoint: CGPoint(x: left ? r.maxX : r.minX, y: 0)))
        }

        ctx.stroke(outer, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, f.v(0.2)))
    }

    /// 泼墨塑料：底色 + 云状起伏 + 微颗粒 + 碎屑。tiles > 1 时向下平铺（用于两侧边框）
    private func speckle(_ ctx: GraphicsContext, _ f: Fit, _ area: Path, tiles: Int) {
        let box = area.boundingRect
        ctx.fill(area, with: .linearGradient(Gradient(colors: [Self.g(0.258), Self.g(0.202)]),
                                             startPoint: CGPoint(x: box.minX, y: box.minY),
                                             endPoint: CGPoint(x: box.maxX, y: box.minY + f.v(TopGeo.stripH))))
        var t = ctx
        t.clip(to: area)
        t.translateBy(x: f.origin.x, y: f.origin.y)
        t.scaleBy(x: f.scale, y: f.scale)
        for k in 0..<tiles {
            var l = t
            l.translateBy(x: 0, y: CGFloat(k) * TopGeo.stripH)
            for (p, r, v) in Self.texture.mottle {
                let col: Color = v > 0 ? .white.opacity(v) : .black.opacity(-v)
                l.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [col, col.opacity(0)]), center: p, startRadius: 0, endRadius: r))
            }
            l.fill(Self.texture.micro.0, with: .color(.white.opacity(0.035)))
            l.fill(Self.texture.micro.1, with: .color(.black.opacity(0.07)))
            for (p, o, soft) in Self.texture.flecks {
                var layer = l
                if soft { layer.addFilter(.blur(radius: f.v(0.12))) }
                layer.fill(p, with: .color(o > 0 ? Color(red: 0.86, green: 0.87, blue: 0.9).opacity(o) : Color.black.opacity(-o)))
            }
        }
    }

    /// 压印的 wacom 字标：单线圆角字形，上沿背光、下沿受光
    private func drawLogo(_ ctx: GraphicsContext, _ f: Fit) {
        let h = TopGeo.logoW / Glyphs.width("wacom")
        let (path, _) = Glyphs.word("wacom", height: f.v(h), origin: f.p(TopGeo.logoX, TopGeo.cy - h / 2))
        let style = Glyphs.style(f.v(h))
        var light = ctx; light.translateBy(x: 0, y: f.v(0.3))
        light.stroke(path, with: .color(.white.opacity(0.09)), style: style)
        var dark = ctx; dark.translateBy(x: 0, y: -f.v(0.22))
        dark.stroke(path, with: .color(.black.opacity(0.5)), style: style)
        ctx.stroke(path, with: .color(Self.g(0.19)), style: style)
    }

    /// 指示灯：冷白小点 + 柔和光晕，缓慢呼吸
    private func drawLED(_ ctx: GraphicsContext, _ f: Fit) {
        let breath = 0.95
        let l = f.p(TopGeo.led)
        let color = Color(red: 0.86, green: 0.95, blue: 1.0)
        let halo = Color(red: 0.6, green: 0.85, blue: 1)
        ctx.fill(Path(ellipseIn: CGRect(x: l.x - f.v(2.2), y: l.y - f.v(2.2), width: f.v(4.4), height: f.v(4.4))),
                 with: .radialGradient(Gradient(colors: [halo.opacity(0.28 * breath), halo.opacity(0)]),
                                       center: l, startRadius: 0, endRadius: f.v(2.2)))
        ctx.fill(Path(ellipseIn: CGRect(x: l.x - f.v(0.75), y: l.y - f.v(0.75), width: f.v(1.5), height: f.v(1.5))),
                 with: .color(color.opacity(breath)))
    }

    /// 顶边：左边是双段拨杆，右边是细长圆条键，都只凸出上沿一点
    private func drawTopKeys(_ ctx: GraphicsContext, _ f: Fit) {
        // 拨杆
        let (sx, sw) = TopGeo.switchKey
        let sr = CGRect(origin: f.p(sx, -2.1), size: CGSize(width: f.v(sw), height: f.v(2.8)))
        let sp = Path(roundedRect: sr, cornerRadius: f.v(0.9), style: .continuous)
        ctx.fill(sp, with: .linearGradient(Gradient(stops: [
            .init(color: Self.g(0.36), location: 0),
            .init(color: Self.g(0.24), location: 0.35),
            .init(color: Self.g(0.15), location: 1),
        ]), startPoint: CGPoint(x: sr.midX, y: sr.minY), endPoint: CGPoint(x: sr.midX, y: sr.maxY)))
        ctx.stroke(sp, with: .color(.black.opacity(0.55)), lineWidth: f.v(0.22))
        // 中间分缝
        let mid = f.p(sx + sw * 0.5, -2.0)
        ctx.fill(Path(CGRect(x: mid.x - f.v(0.18), y: mid.y, width: f.v(0.36), height: f.v(2.4))), with: .color(.black.opacity(0.6)))
        // 顶面高光
        var hl = Path()
        hl.move(to: f.p(sx + 0.9, -1.75)); hl.addLine(to: f.p(sx + sw * 0.5 - 0.6, -1.75))
        hl.move(to: f.p(sx + sw * 0.5 + 0.6, -1.75)); hl.addLine(to: f.p(sx + sw - 0.9, -1.75))
        ctx.stroke(hl, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: f.v(0.35), lineCap: .round))

        // 长条键：细圆条
        let (bx, bw) = TopGeo.barKey
        let br = CGRect(origin: f.p(bx, -1.5), size: CGSize(width: f.v(bw), height: f.v(1.9)))
        let bp = Path(roundedRect: br, cornerRadius: f.v(0.95), style: .continuous)
        ctx.fill(bp, with: .linearGradient(Gradient(stops: [
            .init(color: Self.g(0.20), location: 0),
            .init(color: Self.g(0.40), location: 0.3),
            .init(color: Self.g(0.20), location: 0.75),
            .init(color: Self.g(0.12), location: 1),
        ]), startPoint: CGPoint(x: br.midX, y: br.minY), endPoint: CGPoint(x: br.midX, y: br.maxY)))
        ctx.stroke(bp, with: .color(.black.opacity(0.45)), lineWidth: f.v(0.2))
    }

    /// 拨杆下方：三个小圆环 + 一道竖向长圆槽（压印在顶条上）
    private func drawSwitchHoles(_ ctx: GraphicsContext, _ f: Fit) {
        let sx = TopGeo.switchKey.0
        for (dx, dy) in [(-1.8, 3.4), (2.9, 3.4), (-1.8, 7.2)] as [(CGFloat, CGFloat)] {
            let q = f.p(sx + dx, dy)
            let rr = f.v(1.05)
            let circle = Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            ctx.stroke(circle.offsetBy(dx: 0, dy: f.v(0.22)), with: .color(.white.opacity(0.07)), lineWidth: f.v(0.3))
            ctx.stroke(circle, with: .color(.black.opacity(0.6)), lineWidth: f.v(0.32))
        }
        let slot = CGRect(origin: f.p(sx + 6.9, 2.1), size: CGSize(width: f.v(1.5), height: f.v(6.0)))
        let sp = Path(roundedRect: slot, cornerRadius: f.v(0.75), style: .continuous)
        ctx.stroke(sp.offsetBy(dx: 0, dy: f.v(0.22)), with: .color(.white.opacity(0.07)), lineWidth: f.v(0.3))
        ctx.stroke(sp, with: .color(.black.opacity(0.6)), lineWidth: f.v(0.32))
    }

    // MARK: - 共用

    private func glowRing(_ ctx: GraphicsContext, _ f: Fit, _ c: CGPoint, _ r: CGFloat, _ o: Double) {
        guard o > 0.01 else { return }
        var glow = ctx
        glow.addFilter(.blur(radius: f.v(1.4)))
        glow.stroke(Path(ellipseIn: f.circle(c, r + 1)), with: .color(accent.opacity(o)), lineWidth: f.v(1.4))
        ctx.stroke(Path(ellipseIn: f.circle(c, r + 0.4)), with: .color(accent.opacity(o)), lineWidth: f.v(0.8))
    }

    /// 零件和顶条之间的缝：外圈深色描边 + 缝外下沿反光
    private func seat(_ ctx: GraphicsContext, _ f: Fit, _ c: CGPoint, _ r: CGFloat) {
        ctx.stroke(Path(ellipseIn: f.circle(c, r)), with: .color(Self.groove), lineWidth: f.v(1.25))
        var lip = Path()
        lip.addArc(center: f.p(c), radius: f.v(r + 0.85), startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
        ctx.stroke(lip, with: .color(.white.opacity(0.07)), lineWidth: f.v(0.35))
        var top = Path()
        top.addArc(center: f.p(c), radius: f.v(r + 0.9), startAngle: .degrees(205), endAngle: .degrees(335), clockwise: false)
        ctx.stroke(top, with: .color(.black.opacity(0.18)), lineWidth: f.v(0.5))
    }

    // MARK: - 波轮：外圈 36 条长凹槽（圆头、通到外沿）+ 中间浅碟面

    private func drawDial(_ ctx: GraphicsContext, _ f: Fit, left: Bool) {
        let cD = TopGeo.dial(left)
        let r = TopGeo.dialR
        let t: PadTarget = left ? .leftDial : .rightDial
        let c = f.p(cD)
        let R = f.v(r)
        let b = Self.partBase
        let top = CGPoint(x: c.x, y: c.y - R), bot = CGPoint(x: c.x, y: c.y + R)
        let rRib = R * 0.66

        // 肋带：略外凸，朝上的部分亮、朝下的暗
        let disc = f.circle(cD, r)
        ctx.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [Self.g(b + 0.03), Self.g(b), Self.g(b - 0.045)]),
                                                              startPoint: top, endPoint: bot))
        // 中间浅碟面：边缘略暗、中心略亮，和肋带柔和过渡
        let face = f.circle(cD, r * 0.70)
        ctx.fill(Path(ellipseIn: face), with: .radialGradient(Gradient(stops: [
            .init(color: Self.g(b + 0.012), location: 0),
            .init(color: Self.g(b + 0.002), location: 0.75),
            .init(color: Self.g(b - 0.012).opacity(0.9), location: 0.92),
            .init(color: Self.g(b - 0.012).opacity(0), location: 1),
        ]), center: CGPoint(x: c.x, y: c.y - R * 0.05), startRadius: 0, endRadius: R * 0.70))

        // 36 条凸起的筋：和机身同色，靠上沿受光、下沿背光的两条细边显出立体
        let n = 36
        let rot = st.dialAngle(left) * .pi / 180
        let w = f.v(1.2)
        let r0 = R * 0.68, r1 = R * 0.955
        var ribs = Path()
        for k in 0..<n {
            let a = Double(k) / Double(n) * 2 * .pi + rot - .pi / 2
            let d = CGPoint(x: cos(a), y: sin(a))
            ribs.move(to: CGPoint(x: c.x + d.x * (r0 + w / 2), y: c.y + d.y * (r0 + w / 2)))
            ribs.addLine(to: CGPoint(x: c.x + d.x * (r1 - w * 0.3), y: c.y + d.y * (r1 - w * 0.3)))
        }
        var clip = ctx
        clip.clip(to: Path(ellipseIn: disc))
        let round = StrokeStyle(lineWidth: w, lineCap: .round)
        // 筋与筋之间的缝底：略暗
        clip.stroke(Path(ellipseIn: f.circle(cD, r * 0.82)), with: .color(.black.opacity(0.10)), lineWidth: R * 0.27)
        // 每条筋四周一样的细暗边（对称，不偏移）
        clip.stroke(ribs, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: w * 1.3, lineCap: .round))
        // 筋的顶面
        clip.stroke(ribs, with: .linearGradient(Gradient(colors: [Self.g(b + 0.055), Self.g(b + 0.03), Self.g(b + 0.01)]),
                                                startPoint: top, endPoint: bot),
                    style: StrokeStyle(lineWidth: w, lineCap: .round))
        // 筋顶中线一丝高光
        clip.stroke(ribs, with: .color(.white.opacity(0.05)), style: StrokeStyle(lineWidth: w * 0.35, lineCap: .round))

        // 中心圆面：不画边线，只靠明暗让中间显得略高 —— 中心偏左上最亮，向外柔和地暗下去融进刻度区
        let fr = r * 0.74
        ctx.fill(Path(ellipseIn: f.circle(cD, fr)), with: .radialGradient(Gradient(stops: [
            .init(color: Self.g(b + 0.04), location: 0),
            .init(color: Self.g(b + 0.025), location: 0.55),
            .init(color: Self.g(b + 0.012), location: 0.84),
            .init(color: Self.g(b - 0.01).opacity(0), location: 0.96),
        ]), center: c, startRadius: 0, endRadius: f.v(fr)))
        // 下半圈外缘一点很淡的暗，表现坡面背光
        var soft = ctx
        soft.addFilter(.blur(radius: f.v(0.6)))
        soft.stroke(Path(ellipseIn: f.circle(cD, r * 0.665)), with: .color(.black.opacity(0.22)), lineWidth: f.v(1.1))

        // 外圈粗描边 + 缝外反光
        ctx.stroke(Path(ellipseIn: f.circle(cD, r)), with: .color(Self.groove), lineWidth: f.v(1.05))
        var lip = Path()
        lip.addArc(center: c, radius: f.v(r + 0.8), startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
        ctx.stroke(lip, with: .color(.white.opacity(0.07)), lineWidth: f.v(0.35))

        glowRing(ctx, f, cD, r, max(level(t), st.hover == t ? 0.4 : 0))
    }

    // MARK: - 环形键：每块 = 外圈斜面 + 平台，0.81R 处一道硬折线；中间是凸起的按钮

    private func drawRing(_ ctx: GraphicsContext, _ f: Fit, left: Bool) {
        let cR = TopGeo.ring(left)
        let r = TopGeo.ringR
        let c = f.p(cR)
        let R = f.v(r)
        let rIn = R * 0.43            // 平台内沿
        let rBreak = R * 0.81         // 斜面与平台的折线
        let b = Self.partBase
        let top = CGPoint(x: c.x, y: c.y - R), bot = CGPoint(x: c.x, y: c.y + R)

        func sector(_ mid: Double, _ r0: CGFloat, _ r1: CGFloat) -> Path {
            var p = Path()
            p.addArc(center: c, radius: r1, startAngle: .degrees(mid - 45), endAngle: .degrees(mid + 45), clockwise: false)
            p.addArc(center: c, radius: r0, startAngle: .degrees(mid + 45), endAngle: .degrees(mid - 45), clockwise: true)
            p.closeSubpath()
            return p
        }

        for i in 0..<4 {
            let t: PadTarget = left ? .leftKey(i) : .rightKey(i)
            let mid = TopGeo.angle(i, left: left)
            let down = st.pressed.contains(t)
            let dk: Double = down ? 0.03 : 0

            // 平台：平整，左上略亮
            let plateau = sector(mid, rIn, rBreak)
            ctx.fill(plateau, with: .linearGradient(Gradient(colors: [Self.g(b + 0.012 - dk), Self.g(b - 0.012 - dk)]),
                                                    startPoint: CGPoint(x: c.x - R, y: c.y - R), endPoint: CGPoint(x: c.x + R, y: c.y + R)))
            // 外斜面：法线朝外，朝上的亮、朝下的暗
            let bevel = sector(mid, rBreak, R)
            ctx.fill(bevel, with: .linearGradient(Gradient(colors: [Self.g(b + 0.04 - dk), Self.g(b - 0.005 - dk), Self.g(b - 0.06 - dk)]),
                                                  startPoint: top, endPoint: bot))
            // 内沿小倒角
            let inner = sector(mid, rIn, rIn + f.v(0.9))
            ctx.fill(inner, with: .linearGradient(Gradient(colors: [.black.opacity(0.18), .white.opacity(0.05)]),
                                                  startPoint: top, endPoint: bot))
            // 折线：上半边锐利高光，下半边暗线
            var crease = Path()
            crease.addArc(center: c, radius: rBreak, startAngle: .degrees(mid - 43), endAngle: .degrees(mid + 43), clockwise: false)
            ctx.stroke(crease, with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(down ? 0.06 : 0.20), location: 0),
                .init(color: .white.opacity(0.04), location: 0.45),
                .init(color: .black.opacity(0.10), location: 0.55),
                .init(color: .black.opacity(0.35), location: 1),
            ]), startPoint: top, endPoint: bot), lineWidth: f.v(0.35))

            if down {
                var sh = ctx
                sh.clip(to: sector(mid, rIn, R))
                sh.addFilter(.blur(radius: f.v(0.8)))
                sh.stroke(sector(mid, rIn, R), with: .color(.black.opacity(0.55)), lineWidth: f.v(2))
            }
            let lv = level(t)
            if lv > 0.01 {
                ctx.fill(sector(mid, rIn, R), with: .color(accent.opacity(0.80 * lv)))
                ctx.stroke(crease, with: .color(.white.opacity(0.25 * lv)), lineWidth: f.v(0.35))
            } else if st.hover == t {
                ctx.fill(sector(mid, rIn, R), with: .color(.white.opacity(0.05)))
            }
        }

        // X 形分缝：等宽深槽
        for k in 0..<4 {
            let a = (45 + Double(k) * 90) * .pi / 180
            let d = CGPoint(x: cos(a), y: sin(a))
            var p = Path()
            p.move(to: CGPoint(x: c.x + d.x * (rIn - f.v(1)), y: c.y + d.y * (rIn - f.v(1))))
            p.addLine(to: CGPoint(x: c.x + d.x * R, y: c.y + d.y * R))
            ctx.stroke(p, with: .color(Self.groove), lineWidth: f.v(0.95))
        }

        // 中间：粗凹槽 + 凸起的按钮
        let t: PadTarget = left ? .leftToggle : .rightToggle
        let down = st.pressed.contains(t)
        ctx.fill(Path(ellipseIn: f.circle(cR, r * 0.43)), with: .color(Self.groove))
        let bR = r * 0.37 * (down ? 0.97 : 1)
        let bC = CGPoint(x: cR.x, y: cR.y + (down ? 0.2 : 0))
        let bRect = f.circle(bC, bR)
        if !down {
            // 凸起在凹槽里的落影
            var sh = ctx
            sh.addFilter(.shadow(color: .black.opacity(0.7), radius: f.v(0.7), y: f.v(0.5)))
            sh.fill(Path(ellipseIn: bRect), with: .color(Self.g(b)))
        }
        // 按钮顶面：微微隆起
        ctx.fill(Path(ellipseIn: bRect), with: .radialGradient(Gradient(stops: [
            .init(color: Self.g(b + (down ? -0.02 : 0.022)), location: 0),
            .init(color: Self.g(b + (down ? -0.03 : 0.004)), location: 0.7),
            .init(color: Self.g(b - 0.03), location: 1),
        ]), center: CGPoint(x: bRect.midX - bRect.width * 0.1, y: bRect.midY - bRect.height * 0.14),
            startRadius: 0, endRadius: bRect.width * 0.58))
        // 凸起的上沿受光、下沿背光
        var rim = Path()
        rim.addEllipse(in: bRect.insetBy(dx: f.v(0.2), dy: f.v(0.2)))
        ctx.stroke(rim, with: .linearGradient(Gradient(colors: [.white.opacity(down ? 0.04 : 0.16), .clear, .black.opacity(0.3)]),
                                              startPoint: CGPoint(x: bRect.midX, y: bRect.minY), endPoint: CGPoint(x: bRect.midX, y: bRect.maxY)),
                   lineWidth: f.v(0.4))
        let lv = level(t)
        if lv > 0.01 {
            ctx.fill(Path(ellipseIn: bRect), with: .color(accent.opacity(0.88 * lv)))
        } else if st.hover == t {
            ctx.fill(Path(ellipseIn: bRect), with: .color(.white.opacity(0.06)))
        }

        seat(ctx, f, cR, r)
        if !left { drawSwitchHoles(ctx, f) }
    }
}
