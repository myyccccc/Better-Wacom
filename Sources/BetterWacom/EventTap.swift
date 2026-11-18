import AppKit
import Darwin

/// 系统事件拦截：
/// 1. 一键接管：丢掉来自 Wacom 驱动进程的键盘 / 滚动事件（笔的移动和点击不受影响）
/// 2. 笔侧键：拦截数位笔发出的右键 / 中键 / 其他鼠标键，换成自定义动作
final class EventTap {
    /// 返回 true 表示吞掉这个笔按键事件；参数为（槽位 p1…p4，是否按下）
    var onPenButton: ((String, Bool) -> Bool)?
    var takeover = false

    private var tap: CFMachPort?
    private var wacomPIDs: Set<Int64> = []
    private var lastScan: TimeInterval = 0

    func start() {
        guard tap == nil else { return }
        // 只看键盘和滚动（用于一键接管）；不碰任何鼠标 / 笔事件
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, ctx in
            let me = Unmanaged<EventTap>.fromOpaque(ctx!).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: ctx) else {
            NSLog("BetterWacom: 无法创建事件拦截（需要辅助功能权限）")
            return
        }
        tap = port
        let src = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        scanWacom()
    }

    var isRunning: Bool { tap != nil }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScan > 5 { scanWacom() }

        switch type {
        case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            // 数位笔发出的鼠标键带有 tablet 子类型
            let isPen = e.getIntegerValueField(.mouseEventSubtype) == Int64(CGEventMouseSubtype.tabletPoint.rawValue)
            guard isPen else { break }
            let n = e.getIntegerValueField(.mouseEventButtonNumber)   // 1 右键，2 中键，3、4 侧键
            let down = type == .rightMouseDown || type == .otherMouseDown
            if let cb = onPenButton, cb("p\(n)", down) { return nil }
        case .keyDown, .keyUp, .flagsChanged, .scrollWheel:
            if takeover, wacomPIDs.contains(e.getIntegerValueField(.eventSourceUnixProcessID)) { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(e)
    }

    /// 找出所有 Wacom 驱动相关进程
    private func scanWacom() {
        lastScan = ProcessInfo.processInfo.systemUptime
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var found: Set<Int64> = []
        var name = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0 {
                let s = String(cString: name)
                if s.contains("Wacom") || s.contains("TabletDriver") || s.contains("TabletEventService") {
                    found.insert(Int64(pid))
                }
            }
        }
        wacomPIDs = found
    }
}
