import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// 负责把 Action 变成真正的键盘 / 鼠标 / 媒体事件
enum ActionRunner {
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// 按下时调用。返回 true 表示这个动作需要在松开时再调用 release（按住型）
    @discardableResult
    static func press(_ a: Action) -> Bool {
        switch a.type {
        case "key":
            guard let name = a.key, let code = KeyMap.code(name) else {
                NSLog("BetterWacom: 未知按键 %@", a.key ?? "nil"); return false
            }
            let flags = KeyMap.flags(a.mods) .union(KeyMap.modifierFlag(name) ?? [])
            // 像真键盘一样：先真的按下修饰键，稍等再按主键，主键按住几毫秒再松开，最后松开修饰键。
            // 达芬奇 / Lightroom / Capture One 处理按键时会去查「此刻」的修饰键状态，
            // 一瞬间发完的话修饰键已经松开，组合键会被当成普通键或直接丢掉。
            // 全部放在串行队列里按顺序发，不阻塞调用方。
            let hold = a.hold == true
            keyQueue.async {
                let held = pressModifiers(a.mods)
                if !held.isEmpty { usleep(Timing.afterModifiers) }
                post(code, down: true, flags: flags)
                if hold { return }
                usleep(Timing.keyHold)
                post(code, down: false, flags: flags)
                if !held.isEmpty { usleep(Timing.beforeRelease); releaseModifiers(held) }
            }
            return hold
        case "scroll":
            let e = CGEvent(scrollWheelEvent2Source: source, units: a.lines == true ? .line : .pixel, wheelCount: 2,
                            wheel1: Int32(a.dy ?? 0), wheel2: Int32(a.dx ?? 0), wheel3: 0)
            // mods：滚动时带上修饰键（例如 Capture One 关闭「滚轮改变滑块」后，⌥ + 滚轮才调滑块）
            if a.mods?.isEmpty == false { e?.flags = KeyMap.flags(a.mods) }
            e?.post(tap: .cghidEventTap)
        case "media":
            if let m = a.media, let k = mediaKeys[m] { postMedia(k) }
        case "volume":
            changeVolume(by: a.step ?? 0.01)
        case "click":
            click(button: a.button ?? 0, count: a.count ?? 1)
        case "displayToggle":
            DispatchQueue.main.async { onDisplayToggle?() }
        case "sequence":
            for (i, step) in (a.steps ?? []).enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { press(step) }
            }
        case "app":
            if let b = a.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case "shell":
            if let cmd = a.command {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", cmd]
                try? p.run()
            }
        default:
            break
        }
        return false
    }

    /// 「显示切换」由 AppModel 处理
    static var onDisplayToggle: (() -> Void)?

    /// 在当前鼠标位置点击
    static func click(button: Int, count: Int) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        let (down, up, btn): (CGEventType, CGEventType, CGMouseButton) = {
            switch button {
            case 0: return (.leftMouseDown, .leftMouseUp, .left)
            case 1: return (.rightMouseDown, .rightMouseUp, .right)
            default: return (.otherMouseDown, .otherMouseUp, CGMouseButton(rawValue: UInt32(button == 2 ? 2 : button)) ?? .center)
            }
        }()
        for i in 1...max(1, count) {
            for t in [down, up] {
                let e = CGEvent(mouseEventSource: source, mouseType: t, mouseCursorPosition: loc, mouseButton: btn)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    /// 精细调节系统音量：发送系统音量键（⌥⇧ = 1/4 格，约 1.6%），由 macOS 自己调音量并显示原生音量浮层
    static func changeVolume(by delta: Double) {
        // 没有辅助功能权限时，系统会丢弃我们发出的按键事件：直接调系统音量，用自己的浮层
        VolumeDriver.shared.add(delta)
    }

    static var arrowFlags = ProcessInfo.processInfo.environment["BWArrowFlags"] != "0"

    /// 辅助功能权限（由 AppModel 每 2 秒刷新，避免每格都去查询）
    static var trusted = AXIsProcessTrusted()

    /// 给 VolumeDriver 用：发一次系统音量键（⌥⇧ 1/4 格）
    static func postVolumeKey(up: Bool) { postMedia(up ? 0 : 1, fine: true) }

    /// 波轮触发的动作：音量、亮度这类媒体键走 1/4 格精细调节
    static func pressFine(_ a: Action) {
        if a.type == "media", let m = a.media, let k = mediaKeys[m], fineKeys.contains(m) {
            postMedia(k, fine: true)
        } else {
            press(a)
        }
    }

    private static let fineKeys: Set<String> = ["volumeUp", "volumeDown", "brightnessUp", "brightnessDown"]

    /// 波轮连续触发：快捷键类动作走专用队列 —— 修饰键只按一次并一直按住，主键之间留几毫秒间隔，最后松开修饰键。
    /// 一瞬间反复按下松开修饰键会让 Lightroom 等软件把整串按键都丢掉。
    private static let keyQueue = DispatchQueue(label: "BetterWacom.keys", qos: .userInteractive)

    /// 单次快捷键的发送节奏（微秒）
    enum Timing {
        static let afterModifiers: useconds_t = 12_000
        static let keyHold: useconds_t = 8_000
        static let beforeRelease: useconds_t = 8_000
    }

    /// 等所有已排队的按键发完（退出前用）
    static func flushKeys() { keyQueue.sync {} }

    static func pressRepeated(_ a: Action, count: Int) {
        guard count > 0 else { return }
        guard a.type == "key", a.key != nil, a.hold != true else {
            for _ in 0..<count { pressFine(a) }
            return
        }
        KeyRepeater.shared.add(a, count: count)
    }

    // 给 KeyRepeater 用
    static func _pressModifiers(_ mods: [String]?) -> [(Int, CGEventFlags)] { pressModifiers(mods) }
    static func _releaseModifiers(_ keys: [(Int, CGEventFlags)]) { releaseModifiers(keys) }
    static func _post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) { post(code, down: down, flags: flags) }

    static func release(_ a: Action) {
        guard a.type == "key", let name = a.key, let code = KeyMap.code(name) else { return }
        keyQueue.async {
            post(code, down: false, flags: KeyMap.flags(a.mods))
            releaseModifiers(modifierKeys(a.mods))
        }
    }

    private static let modifierCodes: [(String, Int, CGEventFlags)] = [
        ("ctrl", kVK_Control, .maskControl), ("opt", kVK_Option, .maskAlternate),
        ("shift", kVK_Shift, .maskShift), ("cmd", kVK_Command, .maskCommand),
    ]

    private static func modifierKeys(_ mods: [String]?) -> [(Int, CGEventFlags)] {
        let names = Set((mods ?? []).map { m -> String in
            switch m.lowercased() { case "command": return "cmd"; case "option", "alt": return "opt"; case "control": return "ctrl"; default: return m.lowercased() }
        })
        return modifierCodes.filter { names.contains($0.0) }.map { ($0.1, $0.2) }
    }

    /// 依次按下修饰键（产生 flagsChanged 事件），返回按下的键，供之后松开
    @discardableResult
    private static func pressModifiers(_ mods: [String]?) -> [(Int, CGEventFlags)] {
        let keys = modifierKeys(mods)
        var f: CGEventFlags = []
        for (code, flag) in keys {
            f.insert(flag)
            postRaw(CGKeyCode(code), down: true, flags: f)
        }
        return keys
    }

    private static func releaseModifiers(_ keys: [(Int, CGEventFlags)]) {
        var f: CGEventFlags = keys.reduce([]) { $0.union($1.1) }
        for (code, flag) in keys.reversed() {
            f.remove(flag)
            postRaw(CGKeyCode(code), down: false, flags: f)
        }
    }

    private static func postRaw(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private static func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        var f = flags
        // 方向键带上 Fn + 小键盘标记（和真键盘一样）；可用 BWArrowFlags=0 关闭做对比
        if arrowFlags, [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(Int(code)) {
            f.insert(.maskSecondaryFn); f.insert(.maskNumericPad)
        }
        // F1–F20 和 Home/End/PageUp/PageDown/⌦ 在真键盘上也带 Fn 标记；
        // Snipaste 等用全局快捷键的软件不带这个标记就认不出 F1（实测 2026-11-17）
        if KeyMap.fnKeyCodes.contains(Int(code)) { f.insert(.maskSecondaryFn) }
        e.flags = f
        e.post(tap: .cghidEventTap)
        EventLog.add("\(down ? "↓" : "↑") key \(code) flags \(String(f.rawValue, radix: 16)) → \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
    }

    // 媒体键：NX_KEYTYPE_*
    private static let mediaKeys: [String: Int32] = [
        "volumeUp": 0, "volumeDown": 1, "brightnessUp": 2, "brightnessDown": 3,
        "mute": 7, "play": 16, "next": 17, "previous": 18,
    ]

    private static func postMedia(_ key: Int32, fine: Bool = false) {
        let extra: NSEvent.ModifierFlags = fine ? [.option, .shift] : []
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: (down ? 0xA00 : 0xB00) | extra.rawValue)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

enum KeyMap {
    static func flags(_ mods: [String]?) -> CGEventFlags {
        var f: CGEventFlags = []
        for m in mods ?? [] { if let x = modifierFlag(m) { f.insert(x) } }
        return f
    }

    static func modifierFlag(_ name: String) -> CGEventFlags? {
        switch name.lowercased() {
        case "cmd", "command": return .maskCommand
        case "shift": return .maskShift
        case "opt", "option", "alt": return .maskAlternate
        case "ctrl", "control": return .maskControl
        case "fn": return .maskSecondaryFn
        default: return nil
        }
    }

    static func code(_ name: String) -> CGKeyCode? {
        let n = name.lowercased()
        if let c = table[n] { return CGKeyCode(c) }
        if n.hasPrefix("f"), let num = Int(n.dropFirst()), (1...20).contains(num) {
            return CGKeyCode(fKeys[num - 1])
        }
        return nil
    }

    /// 真键盘发出时带 Fn（maskSecondaryFn）标记的键
    static let fnKeyCodes: Set<Int> = Set(fKeys + [kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete])

    private static let fKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let table: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        "\\": kVK_ANSI_Backslash, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma,
        ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave,
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
        "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
        "forwarddelete": kVK_ForwardDelete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "cmd": kVK_Command, "command": kVK_Command, "shift": kVK_Shift,
        "opt": kVK_Option, "option": kVK_Option, "alt": kVK_Option,
        "ctrl": kVK_Control, "control": kVK_Control,
    ]
}

/// 波轮调音量：合并 + 直接写系统音量（最跟手）
/// - 转动只累加到 pending；后台串行队列把累加量一次性写入默认输出设备，立即生效，不经过主线程
/// - 不用系统音量键：系统异步处理音量键，延迟明显，和直接写入并用还会互相覆盖
/// - 浮层仿系统原生样式（VolumeHUD），在主线程合并刷新；反馈音跟随系统设置
final class VolumeDriver {
    static let shared = VolumeDriver()
    private let queue = DispatchQueue(label: "BetterWacom.volume", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: Double = 0
    private var flushing = false
    /// 连续转动时以自己记的目标值为起点（不用每格都去读系统音量）
    private var intended: Float?
    private var lastChange: TimeInterval = 0
    private var hudScheduled = false
    private var hudValue: Float = 0
    /// 反馈音：转动时最多每 0.12 秒响一次
    private var lastSound: TimeInterval = 0
    private var soundOn = true

    func add(_ delta: Double) {
        lock.lock()
        pending += delta
        let start = !flushing
        flushing = true
        lock.unlock()
        if start { queue.async { self.flush() } }
    }

    private func take() -> Double {
        lock.lock(); defer { lock.unlock() }
        let d = pending; pending = 0; flushing = false
        return d
    }

    private func flush() {
        let d = take()
        guard d != 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let burst = intended != nil && now - lastChange < 0.6
        if !burst { soundOn = VolumeFeedback.enabled }
        guard let cur = burst ? intended : SystemVolume.volume else { fallbackKeys(d); return }
        let target = min(1, max(0, cur + Float(d)))
        guard let v = SystemVolume.set(target, checkMute: !burst) else { fallbackKeys(d); return }
        let changed = v != intended
        intended = v
        lastChange = now
        showHUD(v)
        if changed, soundOn, v > 0, now - lastSound >= 0.12 {
            lastSound = now
            VolumeFeedback.play()
        }
    }

    /// 输出设备不支持直接调音量（如部分 HDMI / 外接声卡）：退回系统音量键
    private func fallbackKeys(_ d: Double) {
        intended = nil
        let n = min(16, max(1, Int((abs(d) * 64).rounded())))
        for _ in 0..<n { ActionRunner.postVolumeKey(up: d > 0) }
    }

    private func showHUD(_ v: Float) {
        lock.lock()
        hudValue = v
        let schedule = !hudScheduled
        hudScheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async {
            self.lock.lock()
            let v = self.hudValue
            self.hudScheduled = false
            self.lock.unlock()
            VolumeHUD.shared.show(Double(v))
        }
    }
}

/// 调试日志：最近 200 条按键 / 波轮事件，写到 ~/Library/Application Support/Better Wacom/events.log
/// 默认关闭（每个按键都记会白白占用主线程和磁盘）。需要排查时打开，重启软件生效：
///   defaults write com.denis.BetterWacom debugLog -bool true
enum EventLog {
    static let enabled = UserDefaults.standard.bool(forKey: "debugLog")
    private static var lines: [String] = []
    private static let url = ConfigStore.dir.appendingPathComponent("events.log")
    private static var pending = false
    /// autoclosure：关闭时连日志文字都不拼
    static func add(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let s = message()
        let t = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.async {
            lines.append("\(t) \(s)")
            if lines.count > 200 { lines.removeFirst(lines.count - 200) }
            guard !pending else { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pending = false
                try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

/// 波轮连续触发快捷键：只累加「还差几格」，一个发送线程持续往外发，不按批排队，转多快都不会积压。
/// - 连续转动期间修饰键只按一次并保持，停手 80ms 后松开
/// - 方向一反转，未发出的旧方向按键直接作废，立即按新方向发
final class KeyRepeater {
    static let shared = KeyRepeater()
    private let queue = DispatchQueue(label: "BetterWacom.keyRepeater", qos: .userInteractive)
    private let lock = NSLock()
    private var current: Action?
    private var pending = 0
    private var running = false

    func add(_ a: Action, count: Int) {
        lock.lock()
        if current == a { pending += count } else { current = a; pending = count }
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { self.run() } }
    }

    private func next() -> Action? {
        lock.lock(); defer { lock.unlock() }
        guard pending > 0, let a = current else { return nil }
        pending -= 1
        return a
    }

    private func run() {
        var heldFor: Action?
        var held: [(Int, CGEventFlags)] = []
        var idleSince = ProcessInfo.processInfo.systemUptime
        while true {
            if let a = next(), let name = a.key, let code = KeyMap.code(name) {
                // 修饰键组合变了：先松开旧的，再按下新的
                if heldFor?.mods ?? [] != a.mods ?? [] || heldFor == nil {
                    ActionRunner._releaseModifiers(held)
                    held = ActionRunner._pressModifiers(a.mods)
                    if !held.isEmpty { usleep(20_000) }
                }
                heldFor = a
                let flags = KeyMap.flags(a.mods).union(KeyMap.modifierFlag(name) ?? [])
                ActionRunner._post(code, down: true, flags: flags)
                ActionRunner._post(code, down: false, flags: flags)
                usleep(5_000)
                idleSince = ProcessInfo.processInfo.systemUptime
            } else {
                // 停手 80ms 后松开修饰键并退出
                if ProcessInfo.processInfo.systemUptime - idleSince > 0.08 {
                    lock.lock()
                    if pending > 0 { lock.unlock(); continue }
                    running = false
                    lock.unlock()
                    ActionRunner._releaseModifiers(held)
                    return
                }
                usleep(4_000)
            }
        }
    }
}
