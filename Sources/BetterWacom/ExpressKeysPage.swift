import SwiftUI

/// 按键页：产品渲染图放大居中；上下两组标注，用细线连到对应的键
struct ExpressKeysPage: View {
    @EnvironmentObject var model: AppModel
    /// 截图用：打开时直接展开某个键的面板
    static var initialEditing: PadTarget?
    @State private var editing: PadTarget? = ExpressKeysPage.initialEditing
    @State private var hover: PadTarget?

    var body: some View {
        ActionPanelHost(open: editing != nil, onClose: { editing = nil }) {
            KeysStage(editing: $editing, hover: $hover)
        } panel: {
            if let t = editing {
                if t == .leftDial || t == .rightDial {
                    DialPanel(target: t) { editing = nil }
                        .id(t)
                } else if let n = model.button(for: t) {
                    ButtonEditor(button: n, positionName: model.positionName(t)) { editing = nil }
                        .id(t)
                }
            }
        }
    }
}

/// 波轮面板：在按键页里直接设置某个波轮的各个模式
struct DialPanel: View {
    @EnvironmentObject var model: AppModel
    let target: PadTarget
    let onClose: () -> Void

    var body: some View {
        let left = target == .leftDial
        ScrollView {
            DialColumn(title: left ? L("左波轮") : L("右波轮"),
                       dial: left ? model.layout.leftDial : model.layout.rightDial, target: target)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.trailing, 30)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
        }
    }
}

/// Wacom 式的动作面板：从左侧滑入，内容区让开位置；点 × 或按 Esc 关闭，点别的键直接切换
struct ActionPanelHost<Content: View, Panel: View>: View {
    let open: Bool
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        ZStack(alignment: .leading) {
            // 只做缩放和位移（GPU 变换），不触发重新排版，动画更顺
            GeometryReader { g in
                let k = open ? max(0.8, (g.size.width - 320) / g.size.width) : 1
                content()
                    .scaleEffect(k, anchor: .trailing)
                    .offset(x: open ? -8 : 0)
            }
            if open {
                panel()
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .glassRounded(20)
                    .shadow(color: .black.opacity(0.18), radius: 24, x: 6)
                    .padding(.leading, 12)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: open)
        .onExitCommand { onClose() }
    }
}

struct KeysStage: View {
    @EnvironmentObject var model: AppModel
    @Binding var editing: PadTarget?
    @Binding var hover: PadTarget?

    // 进场动画（离屏渲染时直接显示）
    static var snapshot = false
    @State private var shown = KeysStage.snapshot
    @State private var labelsShown = KeysStage.snapshot
    @State private var hint = false

    static let above: [PadTarget] = [.leftToggle, .leftKey(0), .leftDial, .rightDial, .rightKey(0), .rightToggle]
    static let below: [PadTarget] = [.leftKey(1), .leftKey(2), .leftKey(3), .rightKey(3), .rightKey(2), .rightKey(1)]

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let aspect = TopGeo.region.width / TopGeo.region.height
            let rw = min(W - 64, H * 0.40 * aspect)
            let rh = rw / aspect
            let rect = CGRect(x: (W - rw) / 2, y: H * 0.47 - rh / 2, width: rw, height: rh)
            let f = Fit(rect.size, region: TopGeo.region)
            let toView: (CGPoint) -> CGPoint = { p in
                let q = f.p(p); return CGPoint(x: q.x + rect.minX, y: q.y + rect.minY)
            }
            let aboveY = rect.minY - max(54, rh * 0.42)
            let belowY = rect.maxY + max(48, rh * 0.36)

            ZStack(alignment: .topLeading) {
                TabletTopView(selected: editing ?? hover, pulse: hint ? .leftKey(0) : nil, hover: $hover) { t in
                    hint = false
                    editing = t
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)

                // 引线（画在渲染图上方）
                Canvas { ctx, _ in
                    for (row, targets) in [(0, Self.above), (1, Self.below)] {
                        for (i, t) in targets.enumerated() {
                            let lx = labelX(i, rect)
                            let kp = toView(keyPoint(t))
                            let on = editing == t || hover == t || model.flashing.contains(t)
                            var p = Path()
                            if row == 0 {
                                p.move(to: CGPoint(x: lx, y: aboveY + 20))
                                p.addLine(to: CGPoint(x: lx, y: rect.minY + f.v(-6)))
                            } else {
                                p.move(to: CGPoint(x: lx, y: belowY - 22))
                                p.addLine(to: CGPoint(x: lx, y: rect.minY + f.v(TopGeo.cy + TopGeo.ringR + 12)))
                            }
                            p.addLine(to: kp)
                            let style = StrokeStyle(lineWidth: on ? 1.2 : 0.75, lineCap: .round, lineJoin: .round)
                            // 机身外：跟随系统的线色；机身上：白色细线
                            let tl = toView(CGPoint(x: 0, y: -TopDrawing.bevel)), br = toView(CGPoint(x: TopGeo.bodyW, y: TopGeo.region.maxY + 30))
                            let body = Path(CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y))
                            var outside = ctx
                            outside.clip(to: body, options: .inverse)
                            outside.stroke(p, with: .color(Color.primary.opacity(on ? 0.9 : 0.32)), style: style)
                            var inside = ctx
                            inside.clip(to: body)
                            inside.stroke(p, with: .color(Color.white.opacity(on ? 0.95 : 0.42)), style: style)
                            ctx.fill(Path(ellipseIn: CGRect(x: kp.x - 2, y: kp.y - 2, width: 4, height: 4)),
                                     with: .color(Color.white.opacity(on ? 1 : 0.75)))
                        }
                    }
                }
                .allowsHitTesting(false)
                .opacity(labelsShown ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: labelsShown)

                ForEach(Array(Self.above.enumerated()), id: \.offset) { i, t in
                    Callout(target: t, editing: $editing, hover: $hover, top: true)
                        .position(x: labelX(i, rect), y: aboveY)
                        .opacity(labelsShown ? 1 : 0)
                        .offset(y: labelsShown ? 0 : 6)
                        .animation(.easeOut(duration: 0.45).delay(Double(i) * 0.05), value: labelsShown)
                }
                ForEach(Array(Self.below.enumerated()), id: \.offset) { i, t in
                    Callout(target: t, editing: $editing, hover: $hover, top: false)
                        .position(x: labelX(i, rect), y: belowY)
                        .opacity(labelsShown ? 1 : 0)
                        .offset(y: labelsShown ? 0 : -6)
                        .animation(.easeOut(duration: 0.45).delay(0.3 + Double(i) * 0.05), value: labelsShown)
                }

                if hint {
                    let kp = toView(keyPoint(.leftKey(0)))
                    HintBubble()
                        .position(x: kp.x + 40, y: rect.minY + f.v(-2))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .onAppear(perform: playEntrance)
    }

    private func labelX(_ i: Int, _ rect: CGRect) -> CGFloat {
        rect.minX + rect.width * (CGFloat(i) + 0.5) / 6
    }

    private func keyPoint(_ t: PadTarget) -> CGPoint {
        let left = t.isLeft
        let rc = TopGeo.ring(left), dc = TopGeo.dial(left)
        let k = TopGeo.ringR * 0.7
        switch t {
        case .leftToggle, .rightToggle: return rc
        case .leftDial, .rightDial: return CGPoint(x: dc.x, y: dc.y - TopGeo.dialR * 0.85)
        case .leftKey(let i), .rightKey(let i):
            let a = TopGeo.angle(i, left: left) * .pi / 180
            return CGPoint(x: rc.x + cos(a) * k, y: rc.y + sin(a) * k)
        }
    }

    private func playEntrance() {
        let first = !model.welcomeShown
        withAnimation(.spring(response: first ? 0.9 : 0.5, dampingFraction: 0.85)) { shown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0.6 : 0.15)) { labelsShown = true }
        guard first else { return }
        model.welcomeShown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.easeOut(duration: 0.35)) { hint = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { withAnimation(.easeIn(duration: 0.35)) { hint = false } }
    }
}

/// 首次打开时的提示气泡
struct HintBubble: View {
    @State private var bob = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow.click.2")
            Text("点击按键，查看或修改快捷键")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassCapsule()
        .offset(y: bob ? -3 : 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { bob = true } }
    }
}

/// 一条标注：动作名 + 键帽；点击弹出编辑器
struct Callout: View {
    @EnvironmentObject var model: AppModel
    let target: PadTarget
    @Binding var editing: PadTarget?
    @Binding var hover: PadTarget?
    let top: Bool

    var body: some View {
        let isDial = target == .leftDial || target == .rightDial
        let on = editing == target || hover == target || model.flashing.contains(target)
        Button {
            editing = target
        } label: {
            VStack(spacing: 4) {
                if isDial {
                    let dial = target == .leftDial ? model.layout.leftDial : model.layout.rightDial
                    let modes = model.effectiveDial(dial)
                    if modes.isEmpty {
                        // 没有任何模式：和按键一样显示「未设置」
                        Text(L("未设置"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(L(modes[0].name))
                            .font(.system(size: 13, weight: .medium))
                        Text(LF("%@ 个模式", "\(modes.count)"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if let n = model.button(for: target) {
                    let a = model.effectiveAction("\(n)")
                    HStack(spacing: 4) {
                        Text(model.title(of: a))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(a == nil || a?.type == "none" ? .tertiary : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)
                        if !model.isDefaultProfile && model.ownAction("\(n)") == nil {
                            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                                .help("跟随通用设置")
                        }
                    }
                    ActionDetail(action: a)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(on ? Color.primary.opacity(0.07) : Color.clear))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: on)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 150)
        .onHover { h in if h { hover = target } else if hover == target { hover = nil } }
    }
}

struct ActionDetail: View {
    @EnvironmentObject var model: AppModel
    let action: Action?

    var body: some View {
        if let a = action, a.type != "none" {
            if a.type == "key", a.key != nil {
                HStack(spacing: 3) {
                    ForEach(Array(KeyMap.keycaps(a.mods, a.key).enumerated()), id: \.offset) { _, cap in Keycap(text: cap) }
                    if a.hold == true { Text("按住").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
            } else if a.label != nil {
                Label(model.summary(of: a), systemImage: a.symbol)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Image(systemName: a.symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 19)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.10)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 4.5, style: .continuous).strokeBorder(Color.primary.opacity(0.14)))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}

/// 弹出编辑器：单击 / 长按（笔侧键只有单击）
struct ButtonEditor: View {
    @EnvironmentObject var model: AppModel
    let button: Int
    let positionName: String
    var slotPrefix = ""
    var onClose: (() -> Void)? = nil
    @State private var slot = 0

    var body: some View {
        let base = slotPrefix.isEmpty ? "\(button)" : slotPrefix
        let key = slot == 0 ? base : "\(base)L"
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(positionName).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
            }
            if slotPrefix.isEmpty {
                Picker("", selection: $slot.animation(.easeInOut(duration: 0.2))) {
                    Text("单击").tag(0)
                    Text("长按").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ActionEditor(
                action: Binding(get: { model.ownAction(key) }, set: { model.setAction(key, $0) }),
                inheritedSummary: model.isDefaultProfile ? nil : model.title(of: model.defaultAction(key)),
                allowDialMode: slotPrefix.isEmpty,
                noneLabel: slot == 1 ? L("不使用长按") : (slotPrefix.isEmpty ? L("禁用") : L("保持原功能"))
            )
            .id(slot)
            .padding(.horizontal, -10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

extension View {
    /// 新版 macOS 用 Liquid Glass，旧版退回毛玻璃
    @ViewBuilder func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder func glassRounded(_ r: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: r, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: r, style: .continuous))
        }
    }
}
