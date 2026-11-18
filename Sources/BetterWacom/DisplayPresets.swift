import AppKit
import SwiftUI

/// 显示器色彩模式（系统设置 → 显示器 → 预设）。
/// 系统没有公开接口，这里用 MonitorPanel 私有框架，和系统设置里切换预设是同一套机制。只在主线程调用。
enum DisplayPresets {
    struct Preset: Hashable { let name: String; let index: Int }

    /// 用户没选时的默认列表
    static let defaultFavorites = ["Apple XDR Display (P3 + Adobe RGB-2000 nits)", "HDR Video (P3-ST 2084)"]

    private static var manager: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW) != nil,
              let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    /// 支持预设的显示器（如 Studio Display XDR、Pro Display XDR、MacBook Pro 内建屏）
    private static var display: NSObject? {
        guard let m = manager, let ds = m.safeValue("displays") as? [NSObject] else { return nil }
        return ds.first { ($0.safeValue("hasPresets") as? Bool) == true }
    }

    static var displayName: String? { display?.safeValue("displayName") as? String }

    private static func rawPresets() -> [NSObject] { (display?.safeValue("presets") as? [NSObject]) ?? [] }

    static func all() -> [Preset] {
        rawPresets().enumerated().compactMap { i, p in
            guard (p.safeValue("isValid") as? Bool) == true, let n = p.safeValue("presetName") as? String else { return nil }
            return Preset(name: n, index: i)
        }
    }

    static var activeName: String? {
        (display?.safeValue("activePreset") as? NSObject)?.safeValue("presetName") as? String
    }

    /// 用户选的常用预设（保持系统列表里的顺序）；都无效时退回全部
    static func favorites(_ chosen: [String]?) -> [Preset] {
        let names = Set(chosen ?? defaultFavorites)
        let list = all().filter { names.contains($0.name) }
        return list.isEmpty ? all() : list
    }

    @discardableResult
    static func apply(_ name: String) -> Bool {
        guard let d = display, let p = rawPresets().first(where: { ($0.safeValue("presetName") as? String) == name }) else { return false }
        let sel = NSSelectorFromString("setActivePreset:")
        guard d.responds(to: sel) else { return false }
        d.perform(sel, with: p)
        return true
    }
}

private extension NSObject {
    /// 私有类的 KVC 读取：系统更新后字段没了，value(forKey:) 会抛 ObjC 异常让整个软件闪退；
    /// 先确认对象还响应这个读取方法，没有就当作读不到（色彩模式功能失效，但软件照常运行）
    func safeValue(_ key: String) -> Any? {
        guard responds(to: NSSelectorFromString(key)) else { return nil }
        return value(forKey: key)
    }
}

/// 选择浮层里的一项：名称用于切换，标题 / 说明 / 图标用于显示
struct PickerItem: Equatable {
    let name: String
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color
}

/// 浮层标题：彩色图标方块 + 标题
struct PickerHeader {
    let title: String
    let subtitle: String?
    let symbol: String
    let colors: [Color]
}

extension DisplayPresets {
    /// 预设名「Apple XDR Display (P3-2000 nits)」拆成标题和括号里的说明，并按用途配图标
    static func pickerItem(_ name: String) -> PickerItem {
        var title = name, detail: String?
        if let open = name.firstIndex(of: "("), name.hasSuffix(")") {
            title = String(name[..<open]).trimmingCharacters(in: .whitespaces)
            detail = String(name[name.index(after: open)..<name.index(before: name.endIndex)])
                // 「P3-2000 nits」→「P3 · 2000 nits」
                .replacingOccurrences(of: #"-(\d+ nits)"#, with: " · $1", options: .regularExpression)
        }
        let n = name.lowercased()
        let (symbol, tint): (String, Color) =
            n.contains("hdr video") ? ("sparkles.tv.fill", .purple) :
            n.contains("hdr photo") ? ("camera.aperture", .orange) :
            n.contains("xdr") ? ("sun.max.fill", .blue) :
            n.contains("cinema") ? ("film.fill", .red) :
            n.contains("hdtv") || n.contains("ntsc") || n.contains("pal") ? ("tv.fill", .indigo) :
            n.contains("print") ? ("printer.fill", .green) :
            n.contains("photo") ? ("camera.fill", .teal) :
            n.contains("web") || n.contains("srgb") ? ("globe", .cyan) :
            n.contains("medical") ? ("cross.case.fill", .pink) :
            ("display", .gray)
        return PickerItem(name: name, title: title, detail: detail, symbol: symbol, tint: tint)
    }

    /// 按住「色彩模式」键：弹出常用预设，高亮当前模式
    static func showPicker(favorites: [String]?) {
        let list = Self.favorites(favorites).map { pickerItem($0.name) }
        guard !list.isEmpty else {
            HUD.shared.show(symbol: "display", title: L("这台显示器没有色彩预设"))
            return
        }
        let header = PickerHeader(title: L("色彩模式"), subtitle: displayName, symbol: "sun.max.fill",
                                  colors: [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 0.1, green: 0.35, blue: 0.95)])
        PresetPicker.shared.begin(tag: "色彩模式", header: header, items: list, active: activeName) { name in
            let ok = apply(name)
            EventLog.add("色彩模式：切换\(ok ? "已调用" : "失败（找不到显示器或预设）")")
            return activeName
        }
    }
}

/// 浮层窗口：不激活 Better Wacom 也能接收键盘（方向键、回车、Esc），按键不会漏给前台软件
private final class PickerPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with e: NSEvent) { if onKey?(e) != true { super.keyDown(with: e) } }
}

/// 按住某个键时出现的选择浮层（色彩模式、声音输出共用）。
/// 只在按住键时显示：转波轮、方向键移动高亮，或鼠标点按直接切换；松开键就关闭，转过就切换
final class PresetPicker: ObservableObject {
    static let shared = PresetPicker()

    @Published var header = PickerHeader(title: "", subtitle: nil, symbol: "display", colors: [.blue])
    @Published var items: [PickerItem] = []
    @Published var selected = 0
    @Published var active: String?
    @Published var visible = false

    /// 浮层显示时为 true（引擎据此把波轮交给浮层）。任意线程可读
    static var isOpen: Bool { openLock.lock(); defer { openLock.unlock() }; return _open }
    private static let openLock = NSLock()
    private static var _open = false
    private static func setOpen(_ v: Bool) { openLock.lock(); _open = v; openLock.unlock() }

    private var tag = ""
    private var apply: ((String) -> String?)?
    private var moved = false
    private let panel: PickerPanel
    private var host: NSHostingView<AnyView>!
    private var hideWork: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?
    private var outsideMonitor: Any?

    private init() {
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        host = NSHostingView(rootView: AnyView(PresetPickerView().environmentObject(self)))
        panel.contentView = host
        panel.onKey = { [weak self] e in self?.key(e) ?? false }
    }

    /// 显示列表；apply 在切换时调用，返回切换后的当前项
    func begin(tag: String, header: PickerHeader, items list: [PickerItem], active current: String?,
               apply: @escaping (String) -> String?) {
        hideWork?.cancel()
        timeoutWork?.cancel()
        self.tag = tag
        self.header = header
        self.apply = apply
        active = current
        items = list
        selected = list.firstIndex { $0.name == current } ?? 0
        moved = false
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let f = screen?.frame ?? .zero
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        Self.setOpen(true)
        installOutsideMonitor()
        restartTimeout()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { visible = true }
    }

    /// 波轮 / 方向键：step 为 +1（下一个）或 -1（上一个），到头停住
    func move(_ step: Int) {
        guard visible, !items.isEmpty else { return }
        moved = true
        selected = min(items.count - 1, max(0, selected + step))
        restartTimeout()
    }

    /// 鼠标移到某一项上：只移动高亮
    func hover(_ i: Int) {
        guard visible, items.indices.contains(i) else { return }
        selected = i
        restartTimeout()
    }

    /// 点按某一项或按回车：切换到它并关闭
    func choose(_ i: Int) {
        guard Self.isOpen, items.indices.contains(i) else { return }
        selected = i
        let name = items[i].name
        hide()
        DispatchQueue.main.async { self.switchTo(name) }
    }

    /// 松开按键：转过就切换；不管切没切换，浮层都马上关闭
    func commit() {
        guard Self.isOpen else { EventLog.add("\(tag)：松开时浮层已关闭，忽略"); return }
        let name = items[safe: selected]?.name
        EventLog.add("\(tag)：松开，转过=\(moved)，选中=\(name ?? "nil")，当前=\(active ?? "nil")")
        // 先让浮层消失，再切换（切换色彩模式会占用主线程约 0.1 秒，不能让它拖住浮层）
        hide()
        if moved, let name { DispatchQueue.main.async { self.switchTo(name) } }
    }

    /// Esc、点浮层外面、超时：不切换直接关
    func cancel() { if Self.isOpen { hide() } }

    private func switchTo(_ name: String) {
        guard name != active else { return }
        let now = apply?(name)
        EventLog.add("\(tag)：切换后=\(now ?? "nil")")
        withAnimation(.easeOut(duration: 0.15)) { active = now ?? name }
    }

    private func key(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 125, 124: move(1)                       // ↓ →
        case 126, 123: move(-1)                      // ↑ ←
        case 36, 76, 49: choose(selected)            // 回车、小键盘回车、空格
        case 53: cancel()                            // Esc
        default: return false
        }
        return true
    }

    private func installOutsideMonitor() {
        if outsideMonitor != nil { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.cancel() }
        }
    }

    /// 保险：万一没收到松开（比如数位板断开），8 秒不动自动关闭
    private func restartTimeout() {
        timeoutWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.cancel() }
        timeoutWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    /// 立刻淡出（0.12 秒，由窗口服务器做动画，不受主线程忙碌影响）
    private func hide() {
        timeoutWork?.cancel()
        hideWork?.cancel()
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        Self.setOpen(false)
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !Self.isOpen else { return }
            self.panel.orderOut(nil)
            self.visible = false
        })
    }
}

private struct PresetPickerView: View {
    @EnvironmentObject var picker: PresetPicker

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: picker.header.symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(picker.header.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(picker.header.subtitle ?? L("转动波轮选择，松开切换"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)

            VStack(spacing: 3) {
                ForEach(Array(picker.items.enumerated()), id: \.offset) { i, item in
                    row(item, selected: i == picker.selected)
                        .contentShape(Rectangle())
                        .onHover { inside in if inside { picker.hover(i) } }
                        .onTapGesture { picker.choose(i) }
                }
            }
        }
        .padding(12)
        .frame(width: 440)
        // 玻璃下面衬一层深色，压在花哨的背景上也看得清
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .modifier(GlassPanel())
        .environment(\.colorScheme, .dark)
        .opacity(picker.visible ? 1 : 0)
        .scaleEffect(picker.visible ? 1 : 0.94)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: picker.selected)
        .padding(30)   // 给阴影留位置；窗口按内容大小，周围不会挡住下面软件的点击
    }

    private func row(_ item: PickerItem, selected: Bool) -> some View {
        let isActive = item.name == picker.active
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let d = item.detail {
                    Text(d)
                        .font(.system(size: 11.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.accentColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
            }
        }
    }
}

private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        }
    }
}
