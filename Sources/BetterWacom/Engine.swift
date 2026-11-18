import AppKit

/// 当前前台 App（主线程监听切换，后台线程随时可读）
enum FrontApp {
    private static let lock = NSLock()
    private static var id: String?
    static var bundleID: String? { lock.lock(); defer { lock.unlock() }; return id }

    /// 在主线程调用一次
    static func start() {
        set(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            set(app?.bundleIdentifier)
        }
    }

    private static func set(_ b: String?) { lock.lock(); id = b; lock.unlock() }
}

/// 把原始帧变成按键 / 波轮事件，再按配置执行动作。
/// 所有处理都在自己的串行队列上进行，不经过主线程（界面渲染再忙也不影响响应）。
final class Engine {
    let queue = DispatchQueue(label: "BetterWacom.engine", qos: .userInteractive)
    let store: ConfigStore
    var paused = false
    /// 以下两个回调在引擎队列上调用，界面更新需自行切回主线程
    var onEvent: ((String) -> Void)?
    /// 原始事件（不受暂停影响），供界面高亮和校准使用
    var onRaw: ((RawEvent) -> Void)?
    /// 为 true 时只上报原始事件、不执行任何动作（校准时使用）
    var capturing = false

    enum RawEvent { case button(Int), release(Int), dial(Int, Int) }

    /// 长按判定时间
    static let longPressDelay: TimeInterval = 0.4
    /// 长按弹出选择浮层（声音输出、色彩模式）时判定更快，接近单击弹出的速度；短按仍算单击
    static let pickerLongPressDelay: TimeInterval = 0.22

    private var lastButtons: UInt16 = 0
    private var held: [Int: Action] = [:]
    private var pendingLong: [Int: DispatchWorkItem] = [:]
    private var modeIndex: [String: Int] = [:]
    private var lastTick: [Int: TimeInterval] = [:]
    /// 正按住的「色彩模式」或「声音输出」键：按住期间两个波轮都用来在列表里选
    private var pickerButton: Int?
    /// 音量 / 亮度键按住时的连发
    private var repeats: [Int: DispatchWorkItem] = [:]

    init(store: ConfigStore) { self.store = store }

    private var frontBundleID: String? { FrontApp.bundleID }

    /// 任意线程调用
    func submit(_ f: PadFrame) { queue.async { self.handle(f) } }

    private func handle(_ f: PadFrame) {
        let changed = f.buttons ^ lastButtons
        if changed != 0 {
            for i in 0..<PadParser.buttonCount where changed & (1 << i) != 0 {
                buttonEvent(i + 1, down: f.buttons & (1 << i) != 0)
            }
            lastButtons = f.buttons
        }
        if f.dial1 != 0 { dialEvent(1, delta: f.dial1) }
        if f.dial2 != 0 { dialEvent(2, delta: f.dial2) }
    }

    // MARK: - 按键：单击 / 长按

    private func buttonEvent(_ n: Int, down: Bool) {
        onRaw?(down ? .button(n) : .release(n))
        if capturing { return }
        let bid = frontBundleID

        if down {
            let tap = store.action(slot: "\(n)", bundleID: bid)
            let long = store.action(slot: "\(n)L", bundleID: bid).flatMap { $0.type == "none" ? nil : $0 }
            onEvent?(LF("按键 %@", "\(n)") + (tap.map { " → \($0.title)" } ?? ""))
            guard !paused else { return }

            if let long {
                // 有长按动作：等到松开或超时再决定
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingLong[n] = nil
                    self.onEvent?(LF("按键 %@ 长按 → %@", "\(n)", long.title))
                    self.perform(long, button: n, bundleID: bid)
                }
                pendingLong[n] = work
                let picker = long.type == "audioOutputs" || long.type == "displayPresets"
                queue.asyncAfter(deadline: .now() + (picker ? Self.pickerLongPressDelay : Self.longPressDelay), execute: work)
            } else if let tap {
                perform(tap, button: n, bundleID: bid)
            }
        } else {
            repeats.removeValue(forKey: n)?.cancel()
            if pickerButton == n {
                pickerButton = nil
                DispatchQueue.main.async { PresetPicker.shared.commit() }
                return
            }
            if let work = pendingLong.removeValue(forKey: n) {
                // 长按还没触发就松开了：当作单击
                work.cancel()
                if let tap = store.action(slot: "\(n)", bundleID: bid), !paused {
                    perform(tap, button: n, bundleID: bid)
                    repeats.removeValue(forKey: n)?.cancel()   // 已经松开，音量键不再连发
                    if let a = held.removeValue(forKey: n) { ActionRunner.release(a) }
                }
                return
            }
            if let a = held.removeValue(forKey: n) { ActionRunner.release(a) }
        }
    }

    private static let repeatingMedia: Set<String> = ["volumeUp", "volumeDown", "brightnessUp", "brightnessDown"]

    /// 按住 0.4 秒后开始连发，之后每 0.09 秒一次，松开即停
    private func startRepeat(_ n: Int, _ a: Action) {
        repeats[n]?.cancel()
        func schedule(after delay: TimeInterval) {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.repeats[n] != nil, !self.paused else { return }
                ActionRunner.press(a)
                schedule(after: 0.09)
            }
            repeats[n] = work
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
        schedule(after: 0.4)
    }

    private func perform(_ a: Action, button n: Int, bundleID: String?) {
        if a.type == "dialMode", let d = a.dial {
            cycleMode(dial: d, bundleID: bundleID)
            return
        }
        if a.type == "displayToggle" {
            DispatchQueue.main.async { ActionRunner.onDisplayToggle?() }
            return
        }
        if a.type == "displayPresets" {
            pickerButton = n
            let favorites = store.current.displayPresets
            DispatchQueue.main.async { DisplayPresets.showPicker(favorites: favorites) }
            return
        }
        if a.type == "audioOutputs" {
            pickerButton = n
            let favorites = store.current.audioOutputs
            DispatchQueue.main.async { AudioOutputs.showPicker(favorites: favorites) }
            return
        }
        if a.type == "media", let m = a.media, Self.repeatingMedia.contains(m) {
            ActionRunner.press(a)
            startRepeat(n, a)
            return
        }
        if ActionRunner.press(a) { held[n] = a }
    }

    // MARK: - 波轮：带加速

    private func dialEvent(_ n: Int, delta raw: Int) {
        onRaw?(.dial(n, raw))
        if capturing { return }
        // 实测顺时针为负数；invertDials 可翻转
        var delta = -raw
        if store.current.invertDials == true { delta = -delta }
        if pickerButton != nil || PresetPicker.isOpen {
            // 按住色彩模式或声音输出键时：两个波轮都用来在列表里选，每格移一项
            // 按物理方向，不受「反转波轮方向」影响：顺时针（原始值为负）往下选，逆时针往上选
            let step = raw < 0 ? 1 : -1
            EventLog.add("选择列表：波轮 \(n) 原始值 \(raw) → 移动 \(step)")
            DispatchQueue.main.async { PresetPicker.shared.move(step) }
            return
        }
        let bid = frontBundleID
        guard let (key, cfg) = store.dial(n, bundleID: bid) else { return }
        let mode = cfg.modes[(modeIndex["\(key)#\(n)"] ?? 0) % cfg.modes.count]

        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - (lastTick[n] ?? 0)
        lastTick[n] = now
        let multiplier = mode.accelerate == true ? Self.acceleration(dt) : 1
        let count = abs(delta) * multiplier

        onEvent?(LF("波轮 %@ %@ ×%@（%@）", "\(n)", delta > 0 ? L("顺时针") : L("逆时针"), "\(count)", L(mode.name)))
        guard !paused else { return }
        let a = delta > 0 ? mode.cw : mode.ccw
        if a.type == "volume" {
            // 音量按步数加总后一次发出
            ActionRunner.changeVolume(by: (a.step ?? 0.01) * Double(count))
        } else if a.type == "dragAdjust" {
            DragAdjuster.shared.add((a.step ?? 2) * Double(count))
        } else {
            ActionRunner.pressRepeated(a, count: min(count, 24))
        }
    }

    /// 两格之间间隔越短，倍数越大：慢转（间隔 ≥ 90ms）每格 1 倍做微调，越快越大，最多 8 倍
    static func acceleration(_ dt: TimeInterval) -> Int {
        guard dt < 0.09 else { return 1 }
        let m = pow(0.09 / max(dt, 0.008), 1.25)
        return min(8, max(1, Int(m.rounded())))
    }

    private func cycleMode(dial n: Int, bundleID: String?) {
        guard let (key, cfg) = store.dial(n, bundleID: bundleID) else { return }
        let k = "\(key)#\(n)"
        let next = ((modeIndex[k] ?? 0) + 1) % cfg.modes.count
        modeIndex[k] = next
        let title = L(cfg.modes[next].name), detail = LF("模式 %@ / %@", "\(next + 1)", "\(cfg.modes.count)")
        DispatchQueue.main.async { HUD.shared.show(symbol: "dial.medium.fill", title: title, detail: detail) }
    }

    /// 外部（笔侧键）触发动作；id 用于松开时释放按住型动作
    func externalPress(_ a: Action, id: Int) {
        queue.async {
            guard !self.paused else { return }
            self.perform(a, button: id, bundleID: self.frontBundleID)
        }
    }

    func externalRelease(id: Int) {
        queue.async { if let a = self.held.removeValue(forKey: id) { ActionRunner.release(a) } }
    }

    /// wait 为 true 时等清理完成再返回（退出前用，确保按住的键都被松开）
    func reset(wait: Bool = false) {
        let work = {
            for (_, a) in self.held { ActionRunner.release(a) }
            self.held.removeAll()
            self.pendingLong.values.forEach { $0.cancel() }
            self.pendingLong.removeAll()
            self.repeats.values.forEach { $0.cancel() }
            self.repeats.removeAll()
            if self.pickerButton != nil { self.pickerButton = nil; DispatchQueue.main.async { PresetPicker.shared.commit() } }
            self.modeIndex.removeAll()
            self.lastButtons = 0
        }
        if wait { queue.sync(execute: work); ActionRunner.flushKeys() } else { queue.async(execute: work) }
    }
}
