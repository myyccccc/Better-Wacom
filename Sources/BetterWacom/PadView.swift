import SwiftUI

/// 板子上的一个物理位置
enum PadTarget: Hashable {
    case leftKey(Int), rightKey(Int), leftToggle, rightToggle, leftDial, rightDial

    var isLeft: Bool {
        switch self {
        case .leftKey, .leftToggle, .leftDial: return true
        default: return false
        }
    }
}

/// Intuos Pro M（2025）顶部的设计坐标：按实物照片校正倾斜后实测（机身宽 567）
enum TopGeo {
    static let bodyW: CGFloat = 567
    static let stripH: CGFloat = 61.2
    static let corner: CGFloat = 5
    static let cy: CGFloat = 30.4
    static let ringR: CGFloat = 26
    static let dialR: CGFloat = 26
    static let leftRingX: CGFloat = 139
    static let leftDialX: CGFloat = 202
    static var rightRingX: CGFloat { bodyW - leftRingX }
    static var rightDialX: CGFloat { bodyW - leftDialX }
    static let logoX: CGFloat = 38.2
    static let logoW: CGFloat = 35.8
    static let led = CGPoint(x: 519.2, y: 30.3)
    static let dots: [CGPoint] = [CGPoint(x: 26.4, y: 84.8), CGPoint(x: 542.6, y: 84.3)]
    /// 顶边上的拨动开关和长条按键（x, 宽）
    static let switchKey: (CGFloat, CGFloat) = (471.6, 13.8)
    static let barKey: (CGFloat, CGFloat) = (510.4, 15.5)

    /// 显示区域：机身顶部 + 一段感应区
    static let region = CGRect(x: -16, y: -14, width: bodyW + 32, height: 122)

    static func ring(_ left: Bool) -> CGPoint { CGPoint(x: left ? leftRingX : rightRingX, y: cy) }
    static func dial(_ left: Bool) -> CGPoint { CGPoint(x: left ? leftDialX : rightDialX, y: cy) }

    /// 键 i 的中心角度（0 上 1 外 2 下 3 内；屏幕坐标 0° = 右）
    static func angle(_ i: Int, left: Bool) -> Double {
        switch i {
        case 0: return -90
        case 2: return 90
        case 1: return left ? 180 : 0
        default: return left ? 0 : 180
        }
    }

    static let segInner: CGFloat = 0.47
    static let wellR: CGFloat = 0.43
    static let buttonR: CGFloat = 0.32

    static func hit(_ p: CGPoint) -> PadTarget? {
        for left in [true, false] {
            let c = ring(left)
            let d = hypot(p.x - c.x, p.y - c.y)
            if d < ringR * wellR { return left ? .leftToggle : .rightToggle }
            if d < ringR + 2 {
                let a = atan2(p.y - c.y, p.x - c.x) * 180 / .pi
                let i = (0..<4).min { angDist(a, angle($0, left: left)) < angDist(a, angle($1, left: left)) }!
                return left ? .leftKey(i) : .rightKey(i)
            }
            let dc = dial(left)
            if hypot(p.x - dc.x, p.y - dc.y) < dialR + 2 { return left ? .leftDial : .rightDial }
        }
        return nil
    }

    private static func angDist(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}

/// 设计坐标 → 视图坐标
struct Fit {
    let scale: CGFloat
    let origin: CGPoint

    init(_ size: CGSize, region: CGRect) {
        scale = min(size.width / region.width, size.height / region.height)
        origin = CGPoint(x: (size.width - region.width * scale) / 2 - region.minX * scale,
                         y: (size.height - region.height * scale) / 2 - region.minY * scale)
    }
    init(_ size: CGSize, design: CGSize) { self.init(size, region: CGRect(origin: .zero, size: design)) }

    func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: origin.x + pt.x * scale, y: origin.y + pt.y * scale) }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { p(CGPoint(x: x, y: y)) }
    func v(_ x: CGFloat) -> CGFloat { x * scale }
    func inverse(_ pt: CGPoint) -> CGPoint { CGPoint(x: (pt.x - origin.x) / scale, y: (pt.y - origin.y) / scale) }
    func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        let q = p(c); let rr = v(r)
        return CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2)
    }
}

/// 绘制所需的动画状态
struct PadState {
    var selected: PadTarget? = nil
    var hover: PadTarget? = nil
    var pressed: Set<PadTarget> = []
    var lit: (PadTarget) -> Double = { _ in 0 }
    var pulse: PadTarget? = nil
    var dialAngle: (Bool) -> Double = { _ in 0 }
    var time: Double = 0
}

/// 一整块的顶部特写：可点击、可悬停，有按下 / 旋转 / 呼吸灯动画
struct TabletTopView: View {
    @EnvironmentObject var model: AppModel
    var selected: PadTarget? = nil
    var pulse: PadTarget? = nil
    var onTap: ((PadTarget) -> Void)? = nil
    @Binding var hover: PadTarget?

    init(selected: PadTarget? = nil, pulse: PadTarget? = nil,
         hover: Binding<PadTarget?> = .constant(nil), onTap: ((PadTarget) -> Void)? = nil) {
        self.selected = selected; self.pulse = pulse; self._hover = hover; self.onTap = onTap
    }

    var body: some View {
        GeometryReader { g in
            let f = Fit(g.size, region: TopGeo.region)
            ZStack {
                // 静态层：材质很密，只在尺寸变化时重绘
                Canvas { ctx, _ in TopDrawing(st: PadState()).drawStatic(ctx, f) }
                    .drawingGroup()
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !(model.animateUntil > AppModel.now || pulse != nil))) { tl in
                    let now = AppModel.now
                    let st = PadState(selected: selected, hover: hover, pressed: model.pressed,
                                      lit: { model.flashLevel($0, at: now) }, pulse: pulse,
                                      dialAngle: { model.dialShown[$0] ?? 0 },
                                      time: tl.date.timeIntervalSinceReferenceDate)
                    Canvas { ctx, _ in TopDrawing(st: st).drawDynamic(ctx, f) }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard onTap != nil else { return }
                switch phase {
                case .active(let p):
                    let t = TopGeo.hit(f.inverse(p))
                    if hover != t { hover = t }
                    (t != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
                case .ended:
                    hover = nil
                    NSCursor.arrow.set()
                }
            }
            .onTapGesture(coordinateSpace: .local) { p in
                if let t = TopGeo.hit(f.inverse(p)) { onTap?(t) }
            }
        }
        .aspectRatio(TopGeo.region.width / TopGeo.region.height, contentMode: .fit)
    }
}

/// 特写的底板：跟随系统深浅色的柔和背景
struct StudioPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// 校准页使用
struct PadCanvas: View {
    var pulse: PadTarget? = nil
    var body: some View { StudioPanel { TabletTopView(pulse: pulse) } }
}
