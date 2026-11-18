import SwiftUI

enum Page: String, Hashable, CaseIterable {
    case pen, keys, dials, mapping, toggle

    /// 当前开放的页面：笔、映射、显示切换交给官方 Wacom Center
    static let visible: [Page] = [.keys, .dials]

    var title: String {
        switch self {
        case .pen: return L("笔")
        case .keys: return L("按键")
        case .dials: return L("波轮")
        case .mapping: return L("映射")
        case .toggle: return L("显示切换")
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "applepencil.tip"
        case .keys: return "circle.grid.cross"
        case .dials: return "dial.low"
        case .mapping: return "rectangle.dashed"
        case .toggle: return "rectangle.on.rectangle"
        }
    }
}

/// 主窗口：单页。左上角型号，右上角账户和设置，中间是渲染图（点键或波轮从左侧滑出设置面板），底部是配置栏
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAccount = false

    var body: some View {
        ExpressKeysPage().id(model.selectedProfile)
            .safeAreaInset(edge: .bottom, spacing: 0) { ProfileBar().padding(.bottom, 16) }
            .overlay(alignment: .topTrailing) { NoticeStack().padding(.top, 12) }
            .overlay { ToastView() }
            .onAppear { model.showStartupNotices() }
            // 标题栏一行：左边型号（让开红绿灯），右边账户和设置
            .overlay(alignment: .top) {
                HStack(spacing: 6) {
                    DeviceHeader()
                    Spacer()
                    TopButton(symbol: "person.crop.circle", help: L("账户与云同步")) { showAccount.toggle() }
                        .popover(isPresented: $showAccount, arrowEdge: .bottom) { AccountPanel() }
                    TopButton(symbol: "gearshape", help: L("设置")) { model.showSettings = true }
                }
                .padding(.leading, 88)
                .padding(.trailing, 14)
                .padding(.top, 6)
                .ignoresSafeArea(.container, edges: .top)
            }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .sheet(isPresented: $model.showSettings) { SettingsPanel() }
            .sheet(isPresented: $model.showCalibration) { CalibrationSheet() }
    }
}

/// 侧栏顶部：线稿设备图标 + 型号
struct DeviceHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            DeviceGlyph()
                .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 17)
            Text("Intuos Pro M").font(.system(size: 13, weight: .semibold))
            Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.6)).frame(width: 6, height: 6)
                .help(model.connected ? L("已连接") : L("未连接"))
        }
    }
}

/// 设备线稿：机身、顶条分隔线、两组环 + 波轮
struct DeviceGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let body = r.insetBy(dx: 0.7, dy: 0.7)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: body.width * 0.08, height: body.width * 0.08), style: .continuous)
        let stripY = body.minY + body.height * 0.30
        p.move(to: CGPoint(x: body.minX, y: stripY))
        p.addLine(to: CGPoint(x: body.maxX, y: stripY))
        let cy = body.minY + body.height * 0.15
        let rr = body.height * 0.085
        for fx in [0.245, 0.355, 0.645, 0.755] {
            let cx = body.minX + body.width * fx
            p.addEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
        }
        return p
    }
}

/// 底部悬浮的配置条：所有图标同样大小，选中只换底色；右侧是暂停
struct ProfileBar: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.profileKeys, id: \.self) { key in
                ProfileIcon(key: key, selected: key == model.selectedProfile)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { model.selectedProfile = key } }
            }
            BarButton(symbol: "plus", help: L("为某个 App 单独设置")) { model.addAppProfile() }
            Divider().frame(height: 22).padding(.horizontal, 4)
            BarButton(symbol: model.paused ? "play.fill" : "pause.fill",
                      help: model.paused ? L("恢复") : L("暂停所有自定义"), active: model.paused) { model.paused.toggle() }
        }
        .padding(5)
        .glassCapsule()
        .confirmationDialog(LF("删除「%@」的设置？", model.profileName(model.selectedProfile)), isPresented: $confirmRemove) {
            Button("删除", role: .destructive) { model.removeSelectedProfile() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeProfile)) { _ in confirmRemove = true }
    }
}

extension Notification.Name {
    static let removeProfile = Notification.Name("BetterWacom.removeProfile")
}

struct BarButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(hovering ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct ProfileIcon: View {
    @EnvironmentObject var model: AppModel
    let key: String
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.primary.opacity(0.14) : hovering ? Color.primary.opacity(0.07) : .clear)
            Group {
                if key == "default" {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? .primary : .secondary)
                } else if let icon = model.icon(for: key) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .saturation(selected ? 1 : 0.85)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 16)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
        }
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .help(model.profileName(key))
        .contextMenu {
            if key != "default" {
                Button(LF("删除「%@」的设置…", model.profileName(key)), role: .destructive) {
                    model.selectedProfile = key
                    NotificationCenter.default.post(name: .removeProfile, object: nil)
                }
            }
        }
    }
}

/// 居中弹出、自动淡出的提示
struct ToastView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let t = model.toast {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(t).font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .glassRounded(20)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .onTapGesture { withAnimation { model.toast = nil } }
        }
    }
}

/// 启动时出现一次的通知，问题解决或关闭后消失
struct NoticeStack: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.notices) { n in
                HStack(spacing: 10) {
                    Image(systemName: n.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.title).font(.callout.weight(.semibold))
                        if !n.detail.isEmpty { Text(n.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 8)
                    Button(n.actionTitle) { n.action(); model.dismiss(n.id) }
                        .controlSize(.small)
                    Button { model.dismiss(n.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 340)
                .glassRounded(16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.notices.map(\.id))
    }
}

/// 右上角的圆形按钮
struct TopButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
