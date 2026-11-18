import SwiftUI

/// 映射：上面是显示器排布，下面是板面；拖动板面上的区域即可，全局生效
struct MappingPage: View {
    @EnvironmentObject var model: AppModel
    @State private var screens = ScreenInfo.all()
    /// 拖动中的区域（松手后才写入配置）
    @State private var liveArea: [Double]?
    @State private var dragStart: [Double]?
    @State private var resizing = false

    private var m: MappingConfig { model.mapping }
    private var area: [Double] { liveArea ?? m.area ?? [0, 0, 1, 1] }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geo in
                stage(geo.size)
            }
            .padding(.leading, 28)
            .padding(.top, 70)
            .padding(.bottom, 40)
            panel
                .frame(width: 250)
                .padding(.trailing, 24)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = ScreenInfo.all()
        }
    }

    // MARK: 左侧：显示器 + 板面

    private func stage(_ size: CGSize) -> some View {
        let all = ScreenInfo.union(screens)
        let topH = size.height * 0.36
        let s = min((size.width - 20) / max(1, all.width), topH / max(1, all.height))
        let dispW = all.width * s, dispH = all.height * s
        let dispOrigin = CGPoint(x: (size.width - dispW) / 2, y: 10)
        func toStage(_ r: CGRect) -> CGRect {
            CGRect(x: dispOrigin.x + (r.minX - all.minX) * s, y: dispOrigin.y + (r.minY - all.minY) * s,
                   width: r.width * s, height: r.height * s)
        }
        let target = toStage(model.mapper.targetRect())

        // 板面（按真实比例，顶部带按键条）
        let tabW = min(size.width * 0.56, (size.height - topH - 110) * 1.45)
        let tabH = tabW / 1.45
        let tab = CGRect(x: (size.width - tabW) / 2, y: min(size.height - tabH - 4, 10 + dispH + 90), width: tabW, height: tabH)
        let stripH = tabH * 0.16
        let active = CGRect(x: tab.minX + tabW * 0.05, y: tab.minY + stripH + tabH * 0.05,
                            width: tabW * 0.90, height: (tabW * 0.90) * (PenPosition.size.height / PenPosition.size.width))
        let a = area
        let areaRect = CGRect(x: active.minX + a[0] * active.width, y: active.minY + a[1] * active.height,
                              width: a[2] * active.width, height: a[3] * active.height)
        let on = m.enabled

        return ZStack(alignment: .topLeading) {
            // 引导线：板面区域四角 → 目标区域四角
            Canvas { ctx, _ in
                guard on else { return }
                var p = Path()
                p.move(to: CGPoint(x: areaRect.minX, y: areaRect.minY)); p.addLine(to: CGPoint(x: target.minX, y: target.maxY))
                p.move(to: CGPoint(x: areaRect.maxX, y: areaRect.minY)); p.addLine(to: CGPoint(x: target.maxX, y: target.maxY))
                ctx.stroke(p, with: .color(Color.accentColor.opacity(0.45)), lineWidth: 1)
            }

            ForEach(screens) { sc in
                let r = toStage(sc.bounds)
                ScreenTile(name: sc.name, selected: on && (m.display == nil || m.display == sc.id))
                    .frame(width: r.width - 4, height: r.height - 4)
                    .offset(x: r.minX + 2, y: r.minY + 2)
                    .onTapGesture { model.setMapping { $0.enabled = true; $0.display = sc.id } }
            }
            if on {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: target.width, height: target.height)
                    .offset(x: target.minX, y: target.minY)
                    .allowsHitTesting(false)
            }

            // 板面
            RoundedRectangle(cornerRadius: tabW * 0.025, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(white: 0.21)).frame(height: stripH)
                        .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1), alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: tabW * 0.025, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                .frame(width: tab.width, height: tab.height)
                .offset(x: tab.minX, y: tab.minY)
            // 有效区域
            Rectangle()
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: active.width, height: active.height)
                .offset(x: active.minX, y: active.minY)
            // 自定义区域（可拖动，右下角可缩放）
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Color.accentColor.opacity(on ? 0.22 : 0.08))
                Rectangle().strokeBorder(Color.accentColor.opacity(on ? 1 : 0.4), lineWidth: 1.5)
                Circle().fill(Color.white).frame(width: 11, height: 11)
                    .shadow(radius: 1)
                    .offset(x: 5, y: 5)
                    .opacity(on ? 1 : 0)
            }
            .frame(width: areaRect.width, height: areaRect.height)
            .offset(x: areaRect.minX, y: areaRect.minY)
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if dragStart == nil {
                        dragStart = area
                        let local = CGPoint(x: g.startLocation.x, y: g.startLocation.y)
                        resizing = local.x > areaRect.width - 22 && local.y > areaRect.height - 22
                    }
                    guard let st = dragStart else { return }
                    let dx = g.translation.width / active.width, dy = g.translation.height / active.height
                    var n = st
                    if resizing {
                        n[2] = min(1 - st[0], max(0.15, st[2] + dx))
                        n[3] = min(1 - st[1], max(0.15, st[3] + dy))
                    } else {
                        n[0] = min(1 - st[2], max(0, st[0] + dx))
                        n[1] = min(1 - st[3], max(0, st[1] + dy))
                    }
                    liveArea = n
                }
                .onEnded { _ in
                    if let n = liveArea { model.setMapping { $0.enabled = true; $0.area = n } }
                    liveArea = nil; dragStart = nil
                })
        }
        .animation(.easeOut(duration: 0.2), value: m)
    }

    // MARK: 右侧：选项

    private var panel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Toggle(isOn: Binding(get: { m.enabled }, set: { v in model.setMapping { $0.enabled = v } })) {
                Text("接管映射").font(.system(size: 13, weight: .semibold))
            }
            .toggleStyle(.switch)

            Group {
                section(L("显示器")) {
                    RadioRow(title: L("所有显示器"), on: m.display == nil) { model.setMapping { $0.display = nil } }
                    ForEach(screens) { sc in
                        RadioRow(title: sc.name, on: m.display == sc.id) { model.setMapping { $0.display = sc.id } }
                    }
                }
                section(L("比例")) {
                    Toggle("强制比例", isOn: Binding(get: { m.forceProportions ?? false },
                                                 set: { v in model.setMapping { $0.forceProportions = v } }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                section(L("板面区域")) {
                    RadioRow(title: L("全部区域"), on: m.area == nil) { model.setMapping { $0.area = nil } }
                    RadioRow(title: L("自定义"), on: m.area != nil) {
                        model.setMapping { $0.area = $0.area ?? [0.1, 0.1, 0.8, 0.8] }
                    }
                }
            }
            .disabled(!m.enabled)
            .opacity(m.enabled ? 1 : 0.45)

            Spacer()
        }
        .padding(.top, 80)
        .padding(.bottom, 28)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}

struct RadioRow: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: on ? 5 : 1.2)
                }
                .frame(width: 15, height: 15)
                Text(title).font(.system(size: 13)).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 显示器缩略图：简洁的渐变 + 名称
struct ScreenTile: View {
    let name: String
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: selected ? [Color(red: 0.30, green: 0.42, blue: 0.62), Color(red: 0.16, green: 0.20, blue: 0.32)]
                                                  : [Color.primary.opacity(0.10), Color.primary.opacity(0.05)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .overlay {
                Text(name).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : .secondary)
                    .lineLimit(1).padding(6)
            }
    }
}

/// 显示切换：选哪些显示器参与轮换
struct DisplayTogglePage: View {
    @EnvironmentObject var model: AppModel
    @State private var screens = ScreenInfo.all()

    private var list: [UInt32]? { model.mapping.toggle }

    private func included(_ id: UInt32) -> Bool { list?.contains(id) ?? true }

    private func set(_ id: UInt32, _ v: Bool) {
        var all = list ?? ([0] + screens.map(\.id))
        if v { if !all.contains(id) { all.append(id) } } else { all.removeAll { $0 == id } }
        model.setMapping { $0.toggle = all }
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 20)
            ToggleRow(icon: AnyView(Image(systemName: "rectangle.on.rectangle").font(.system(size: 22, weight: .light))),
                      title: L("所有显示器"), on: included(0), current: model.mapping.enabled && model.mapping.display == nil) { set(0, $0) }
            ForEach(screens) { sc in
                ToggleRow(icon: AnyView(ScreenTile(name: "", selected: true).frame(width: 46, height: 28)),
                          title: sc.name, on: included(sc.id),
                          current: model.mapping.enabled && model.mapping.display == sc.id) { set(sc.id, $0) }
            }
            Spacer()
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

private struct ToggleRow: View {
    let icon: AnyView
    let title: String
    let on: Bool
    let current: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            icon.frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                if current { Text("当前").font(.caption).foregroundStyle(Color.accentColor) }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
