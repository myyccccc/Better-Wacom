import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// 全局状态：配置、设备、引擎、界面实时高亮、校准流程
final class AppModel: NSObject, ObservableObject {
    static let shared = AppModel()

    let store = ConfigStore()
    lazy var engine = Engine(store: store)
    let device = DeviceService()
    let tap = EventTap()
    let mapper = MappingEngine()

    // MARK: 界面状态
    @Published var showSettings = false
    @Published var showCalibration = false
    @Published var toast: String?
    @Published var welcomePlaying = false
    /// 最近被按下的笔侧键槽位（用于高亮）
    @Published private(set) var penFlash: Set<String> = []

    // MARK: 外观（0 自动 1 浅色 2 深色）
    @Published var appearance: Int = UserDefaults.standard.integer(forKey: "appearance") {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); applyAppearance() }
    }

    func applyAppearance() {
        NSApp.appearance = appearance == 1 ? NSAppearance(named: .aqua) : appearance == 2 ? NSAppearance(named: .darkAqua) : nil
    }

    // MARK: 一键接管
    var takeover: Bool {
        get { store.config.takeover ?? false }
        set {
            store.mutate { $0.takeover = newValue }
            tap.takeover = newValue
            showToast(newValue ? L("已接管官方按键设置") : L("已恢复官方设置"))
        }
    }

    func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.25)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self?.toast == text else { return }
            withAnimation(.easeIn(duration: 0.4)) { self?.toast = nil }
        }
    }

    // MARK: 欢迎动画（首次打开）
    var welcomeShown: Bool {
        get { UserDefaults.standard.bool(forKey: "welcomeShown") }
        set { UserDefaults.standard.set(newValue, forKey: "welcomeShown") }
    }

    // MARK: iCloud 云盘同步
    static let cloudDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Better Wacom", isDirectory: true)
    var cloudFile: URL { Self.cloudDir.appendingPathComponent("config.json") }
    var cloudAvailable: Bool {
        FileManager.default.fileExists(atPath: Self.cloudDir.deletingLastPathComponent().path)
    }
    @Published var cloudAuto: Bool = UserDefaults.standard.bool(forKey: "cloudAuto") {
        didSet { UserDefaults.standard.set(cloudAuto, forKey: "cloudAuto"); if cloudAuto { uploadToCloud(quiet: true) } }
    }
    @Published var cloudLast: Date? = UserDefaults.standard.object(forKey: "cloudLast") as? Date

    func uploadToCloud(quiet: Bool = false) {
        do {
            try FileManager.default.createDirectory(at: Self.cloudDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cloudFile.path) { try FileManager.default.removeItem(at: cloudFile) }
            try FileManager.default.copyItem(at: ConfigStore.url, to: cloudFile)
            cloudLast = Date()
            UserDefaults.standard.set(cloudLast, forKey: "cloudLast")
            if !quiet { showToast(L("已上传到 iCloud")) }
        } catch {
            if !quiet { showToast(L("上传失败")) }
        }
    }

    func restoreFromCloud() {
        guard let data = try? Data(contentsOf: cloudFile),
              let c = try? JSONDecoder().decode(AppConfig.self, from: data) else { showToast(L("云端没有设置")); return }
        store.replace(c)
        engine.reset()
        tap.takeover = c.takeover ?? false
        showToast(L("已从 iCloud 恢复"))
    }

    // MARK: 笔侧键

    private func handlePen(_ slot: String, down: Bool) -> Bool {
        let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let a = store.action(slot: slot, bundleID: bid), a.type != "none" else { return false }
        let id = 200 + (Int(slot.dropFirst()) ?? 0)
        if down {
            penFlash.insert(slot)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.penFlash.remove(slot) }
            lastEvent = LF("笔 %@ → %@", slot, title(of: a))
            engine.externalPress(a, id: id)
        } else {
            engine.externalRelease(id: id)
        }
        return true
    }

    @Published var connected = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var paused = false { didSet { engine.paused = paused } }
    @Published var selectedProfile = "default"
    @Published var page: Page? = .keys
    @Published var lastEvent = L("无")
    /// 当前正在闪烁高亮的物理位置
    @Published private(set) var flashing: Set<PadTarget> = []
    /// 正被按住的位置（用于按下动画）
    @Published private(set) var pressed: Set<PadTarget> = []
    /// 最近一次触发的时间（用于高光淡出动画）
    private(set) var flashTimes: [PadTarget: TimeInterval] = [:]
    /// 波轮在图上的旋转角度（度）：target 为目标值，shown 为缓动后的显示值
    private var dialTarget: [Bool: Double] = [true: 0, false: 0]
    private(set) var dialShown: [Bool: Double] = [true: 0, false: 0]
    /// 动画需要持续到的时间
    @Published private(set) var animateUntil: TimeInterval = 0
    private var dialTimer: Timer?
    @Published private(set) var calibration: Calibration?
    @Published var calibrationDone = false

    // MARK: 启动通知

    struct Notice: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let actionTitle: String
        let action: () -> Void
    }

    @Published private(set) var notices: [Notice] = []
    private var noticesShown = false

    /// 设置窗口第一次出现时调用：只在启动时提示一次
    func showStartupNotices() {
        guard !noticesShown else { return }
        noticesShown = true
        // 窗口可能比配置读取更早出现：等启动完成后再判断
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            var list: [Notice] = []
            if self.store.config.layout == nil {
                list.append(Notice(id: "layout", symbol: "scope", title: L("校准按键位置"),
                                   detail: "", actionTitle: L("去校准"),
                                   action: { [weak self] in self?.showCalibration = true }))
            }
            self.notices = list
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.notices.removeAll() }
        }
    }

    func dismiss(_ id: String) { notices.removeAll { $0.id == id } }

    private var bag: Set<AnyCancellable> = []
    private var iconCache: [String: NSImage] = [:]

    @objc private func autoUpload() { uploadToCloud(quiet: true) }

    private override init() {
        super.init()
        store.load()
        store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        store.$config.sink { [weak self] c in
            self?.mapper.config = c.mapping ?? MappingConfig()
            self?.mapper.feel = c.pen?.feel ?? 0
        }.store(in: &bag)
    }

    // MARK: 映射 / 显示切换

    var mapping: MappingConfig { store.config.mapping ?? MappingConfig() }

    func setMapping(_ change: (inout MappingConfig) -> Void) {
        store.mutate { c in
            var m = c.mapping ?? MappingConfig()
            change(&m)
            c.mapping = m
        }
    }

    var penFeel: Double {
        get { store.config.pen?.feel ?? 0 }
        set { store.mutate { $0.pen = PenConfig(feel: newValue) } }
    }

    /// 在「显示切换」列表里轮换：所有显示器 → 显示器 1 → 显示器 2 …
    func toggleDisplay() {
        let screens = ScreenInfo.all()
        var cycle: [UInt32?] = [nil] + screens.map { Optional($0.id) }
        if let t = mapping.toggle, !t.isEmpty {
            cycle = cycle.filter { t.contains($0 ?? 0) }
        }
        guard !cycle.isEmpty else { return }
        let i = cycle.firstIndex(where: { $0 == mapping.display }) ?? -1
        let next = cycle[(i + 1) % cycle.count]
        setMapping { $0.enabled = true; $0.display = next }
        let name = next.flatMap { id in screens.first { $0.id == id }?.name } ?? L("所有显示器")
        HUD.shared.show(symbol: "display.2", title: L("显示切换"), detail: name, level: nil)
    }

    func start() {
        #if DEBUG
        // 开发测试（只在 debug 构建里启用：任何进程都能发系统广播，正式版不能借此替别人按键）
        // xcrun swift -e 发通知 "BetterWacom.testKey"，object 为 "opt+up 3"
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("BetterWacom.testKey"), object: nil, queue: .main) { n in
            guard let s = n.object as? String else { return }
            let parts = s.split(separator: " ")
            guard let first = parts.first else { return }
            let keys = first.split(separator: "+").map(String.init)
            guard let key = keys.last else { return }
            ActionRunner.pressRepeated(Action.key(key, Array(keys.dropLast())), count: min(50, Int(parts.dropFirst().first ?? "1") ?? 1))
        }
        // 开发测试：模拟数位板输入，走和实体板子相同的流程。object 例如 "down 10"、"dial 2 -1"、"up 10"
        var testButtons: UInt16 = 0
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("BetterWacom.testPad"), object: nil, queue: .main) { [weak self] n in
            guard let self, let s = n.object as? String else { return }
            let p = s.split(separator: " ").map(String.init)
            guard p.count >= 2, let a = Int(p[1]), (1...PadParser.buttonCount).contains(a) else { return }
            switch p[0] {
            case "down": testButtons |= 1 << (a - 1); self.engine.submit(PadFrame(buttons: testButtons, dial1: 0, dial2: 0))
            case "up": testButtons &= ~(1 << (a - 1)); self.engine.submit(PadFrame(buttons: testButtons, dial1: 0, dial2: 0))
            case "dial":
                let v = p.count > 2 ? Int(p[2]) ?? 1 : 1
                self.engine.submit(PadFrame(buttons: testButtons, dial1: a == 1 ? v : 0, dial2: a == 2 ? v : 0))
            default: break
            }
        }
        #endif
        store.load()
        FrontApp.start()
        // 引擎和设备都在后台线程：动作直接在后台执行，界面只在主线程上合并刷新
        engine.onEvent = { [weak self] t in
            EventLog.add(t + " @ " + (FrontApp.bundleID ?? "?"))
            self?.postLastEvent(t)
        }
        engine.onRaw = { [weak self] e in DispatchQueue.main.async { self?.handleRaw(e) } }
        device.onFrame = { [weak self] f in self?.engine.submit(f) }
        device.onConnectionChange = { [weak self] c in DispatchQueue.main.async { self?.connected = c } }
        device.start()
        connected = device.isConnected
        applyAppearance()
        tap.takeover = store.config.takeover ?? false
        // 笔、映射、显示切换暂不开发：不拦截任何笔 / 鼠标事件，全部交给官方驱动
        // 一键接管已取消：不安装任何键盘拦截，避免干扰 Better Wacom 自己发出的按键
        store.onSave = { [weak self] in
            guard let self, self.cloudAuto else { return }
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.autoUpload), object: nil)
            self.perform(#selector(self.autoUpload), with: nil, afterDelay: 2)
        }

        try? "trusted=\(AXIsProcessTrusted())".write(to: ConfigStore.dir.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
        // 不在启动时弹系统权限窗口；未授权时只在设置面板里显示状态
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            let t = AXIsProcessTrusted()
            ActionRunner.trusted = t
            if self?.trusted != t { self?.trusted = t }
            if t { self?.dismiss("ax") }
            self?.store.reloadIfChangedOnDisk()
        }
    }

    /// 「最近」文字每秒最多刷新 10 次：每格都改会让整个界面跟着重算
    private let eventLock = NSLock()
    private var pendingEvent: String?
    private func postLastEvent(_ t: String) {
        eventLock.lock()
        let schedule = pendingEvent == nil
        pendingEvent = t
        eventLock.unlock()
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.eventLock.lock()
            let t = self.pendingEvent
            self.pendingEvent = nil
            self.eventLock.unlock()
            if let t, self.lastEvent != t { self.lastEvent = t }
        }
    }

    var config: AppConfig { store.config }
    var layout: PadLayout { store.config.padLayout }
    var isDefaultProfile: Bool { selectedProfile == "default" }

    // MARK: - 实时高亮

    func target(forButton n: Int) -> PadTarget? {
        let l = layout
        if let i = l.leftKeys.firstIndex(of: n) { return .leftKey(i) }
        if let i = l.rightKeys.firstIndex(of: n) { return .rightKey(i) }
        if n == l.leftToggle { return .leftToggle }
        if n == l.rightToggle { return .rightToggle }
        return nil
    }

    func button(for t: PadTarget) -> Int? {
        let l = layout
        switch t {
        case .leftKey(let i): return l.leftKeys[safe: i]
        case .rightKey(let i): return l.rightKeys[safe: i]
        case .leftToggle: return l.leftToggle
        case .rightToggle: return l.rightToggle
        default: return nil
        }
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func keepAnimating(_ seconds: TimeInterval) {
        let until = Self.now + seconds
        if until > animateUntil + 0.05 {
            animateUntil = until
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in self?.objectWillChange.send() }
        }
    }

    func flashLevel(_ t: PadTarget, at time: TimeInterval) -> Double {
        guard let f = flashTimes[t] else { return 0 }
        return max(0, 1 - (time - f) / 0.7)
    }

    private func turnDial(left: Bool, by raw: Int) {
        // 顺时针为负数；每格约 6°
        let sign: Double = store.config.invertDials == true ? 1 : -1
        dialTarget[left, default: 0] += Double(raw) * sign * 6
        keepAnimating(0.8)
        guard dialTimer == nil else { return }
        dialTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            var moving = false
            for side in [true, false] {
                let target = self.dialTarget[side] ?? 0, shown = self.dialShown[side] ?? 0
                let next = shown + (target - shown) * 0.22
                self.dialShown[side] = abs(target - next) < 0.05 ? target : next
                if abs(target - next) >= 0.05 { moving = true }
            }
            if !moving { t.invalidate(); self.dialTimer = nil }
        }
    }

    private func flash(_ t: PadTarget) {
        flashTimes[t] = Self.now
        keepAnimating(0.8)
        flashing.insert(t)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.flashing.remove(t) }
    }

    private func handleRaw(_ e: Engine.RawEvent) {
        switch e {
        case .button(let n):
            if let t = target(forButton: n) { pressed.insert(t); keepAnimating(0.8) }
        case .release(let n):
            if let t = target(forButton: n) { pressed.remove(t); flashTimes[t] = Self.now; keepAnimating(0.8) }
        case .dial(let n, let raw):
            turnDial(left: n == layout.leftDial, by: raw)
        }
        if calibration != nil { calibrate(e); return }
        switch e {
        case .button(let n):
            if let t = target(forButton: n) { flash(t) }
        case .dial(let n, _):
            flash(n == layout.leftDial ? .leftDial : .rightDial)
        case .release:
            break
        }
    }

    // MARK: - 显示文字

    func summary(of a: Action) -> String {
        if a.type == "dialMode" {
            return a.dial == layout.leftDial ? L("切换左波轮模式") : L("切换右波轮模式")
        }
        return a.summary
    }

    func title(of a: Action?) -> String {
        guard let a else { return L("未设置") }
        if let l = a.label, !l.isEmpty { return L(l) }
        if a.type == "none" { return L("未设置") }
        return summary(of: a)
    }

    func shortPositionName(_ t: PadTarget) -> String {
        switch t {
        case .leftToggle, .rightToggle: return L("中间")
        case .leftKey(let i): return [L("上"), L("左"), L("下"), L("右")][i]
        case .rightKey(let i): return [L("上"), L("右"), L("下"), L("左")][i]
        default: return L("波轮")
        }
    }

    func positionName(_ t: PadTarget) -> String {
        let dirs = [L("上"), L("外侧"), L("下"), L("内侧")]
        switch t {
        case .leftKey(let i): return L("左环 · ") + (i == 1 ? L("左") : i == 3 ? L("右") : dirs[i])
        case .rightKey(let i): return L("右环 · ") + (i == 1 ? L("右") : i == 3 ? L("左") : dirs[i])
        case .leftToggle: return L("左环 · 中间按钮")
        case .rightToggle: return L("右环 · 中间按钮")
        case .leftDial: return L("左波轮")
        case .rightDial: return L("右波轮")
        }
    }

    // MARK: - 按键配置读写（当前选中的配置）；slot 为 "3"（单击）或 "3L"（长按）

    func ownAction(_ slot: String) -> Action? {
        config.profiles[selectedProfile]?.buttons?[slot]
    }

    func defaultAction(_ slot: String) -> Action? {
        config.profiles["default"]?.buttons?[slot]
    }

    func effectiveAction(_ slot: String) -> Action? { ownAction(slot) ?? defaultAction(slot) }

    /// a 为 nil：App 配置里表示跟随通用；通用配置里单击表示禁用、长按表示不设置
    func setAction(_ slot: String, _ a: Action?) {
        let p = selectedProfile
        store.mutate { c in
            var prof = c.profiles[p] ?? Profile(name: p)
            var b = prof.buttons ?? [:]
            if let a { b[slot] = a }
            else if p == "default" && !slot.hasSuffix("L") { b[slot] = .disabled }
            else { b[slot] = nil }
            prof.buttons = b
            c.profiles[p] = prof
        }
    }

    // MARK: - 波轮配置读写

    func ownDial(_ d: Int) -> [DialMode]? { config.profiles[selectedProfile]?.dials?[String(d)]?.modes }
    func defaultDial(_ d: Int) -> [DialMode] { config.profiles["default"]?.dials?[String(d)]?.modes ?? [] }
    func effectiveDial(_ d: Int) -> [DialMode] { ownDial(d) ?? defaultDial(d) }

    func setDial(_ d: Int, _ modes: [DialMode]?) {
        let p = selectedProfile
        store.mutate { c in
            var prof = c.profiles[p] ?? Profile(name: p)
            var ds = prof.dials ?? [:]
            ds[String(d)] = modes.map { DialConfig(modes: $0) }
            prof.dials = ds
            c.profiles[p] = prof
        }
    }

    // MARK: - App 配置

    /// 通用在最前，其余按名称排序
    var profileKeys: [String] {
        let others = config.profiles.keys.filter { $0 != "default" }
            .sorted { profileName($0).localizedCompare(profileName($1)) == .orderedAscending }
        return ["default"] + others
    }

    func profileName(_ key: String) -> String {
        key == "default" ? L("通用") : (config.profiles[key]?.name ?? key)
    }

    func icon(for bundleID: String) -> NSImage? {
        if let i = iconCache[bundleID] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = i
        return i
    }

    func addAppProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("添加")
        panel.message = L("选择要单独设置按键的 App")
        guard panel.runModal() == .OK, let url = panel.url,
              let bid = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        if config.profiles[bid] == nil {
            store.mutate { $0.profiles[bid] = Profile(name: name) }
        }
        selectedProfile = bid
    }

    func removeSelectedProfile() {
        let p = selectedProfile
        guard p != "default" else { return }
        selectedProfile = "default"
        store.mutate { $0.profiles[p] = nil }
    }

    // MARK: - 按键位置校准

    struct Calibration {
        var step = 0
        var leftKeys: [Int] = []
        var rightKeys: [Int] = []
        var leftToggle = 0
        var rightToggle = 0
        var used: Set<Int> = []
    }

    static let calibrationSteps: [(String, PadTarget)] = [
        (L("按左边环形键中间的按钮"), .leftToggle),
        (L("按左边环形键的「上」"), .leftKey(0)),
        (L("按左边环形键的「左」"), .leftKey(1)),
        (L("按左边环形键的「下」"), .leftKey(2)),
        (L("按左边环形键的「右」"), .leftKey(3)),
        (L("按右边环形键中间的按钮"), .rightToggle),
        (L("按右边环形键的「上」"), .rightKey(0)),
        (L("按右边环形键的「右」"), .rightKey(1)),
        (L("按右边环形键的「下」"), .rightKey(2)),
        (L("按右边环形键的「左」"), .rightKey(3)),
        (L("顺时针慢慢转动左边的波轮"), .leftDial),
    ]

    var calibrationTarget: PadTarget? {
        guard let c = calibration else { return nil }
        return Self.calibrationSteps[safe: c.step]?.1
    }

    func startCalibration() {
        calibrationDone = false
        calibration = Calibration()
        engine.capturing = true
    }

    func cancelCalibration() {
        calibration = nil
        engine.capturing = false
    }

    private func calibrate(_ e: Engine.RawEvent) {
        guard var c = calibration, let target = calibrationTarget else { return }
        switch (e, target) {
        case (.button(let n), _) where target != .leftDial:
            guard !c.used.contains(n) else { NSSound.beep(); return }
            c.used.insert(n)
            switch target {
            case .leftToggle: c.leftToggle = n
            case .rightToggle: c.rightToggle = n
            case .leftKey: c.leftKeys.append(n)
            case .rightKey: c.rightKeys.append(n)
            default: break
            }
            flash(target)
            c.step += 1
            calibration = c
        case (.dial(let d, let raw), .leftDial):
            // 顺时针时 raw 应为负数（引擎里 delta = -raw）；不是的话需要反转
            let invert = raw > 0
            finishCalibration(c, leftDial: d, invert: invert)
        default:
            break
        }
    }

    private func finishCalibration(_ c: Calibration, leftDial: Int, invert: Bool) {
        let new = PadLayout(leftKeys: c.leftKeys, rightKeys: c.rightKeys,
                            leftToggle: c.leftToggle, rightToggle: c.rightToggle,
                            leftDial: leftDial, rightDial: leftDial == 1 ? 2 : 1)
        let old = layout
        store.mutate { cfg in
            cfg = ConfigStore.remap(cfg, from: old, to: new)
            cfg.layout = new
            cfg.invertDials = invert
        }
        dismiss("layout")
        flash(.leftDial)
        calibration = nil
        engine.capturing = false
        calibrationDone = true
        showToast(L("校准完成"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.showCalibration = false }
    }

    // MARK: - 窗口

    // 设置窗口见 SettingsWindow.swift

}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
