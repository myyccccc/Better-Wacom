import AppKit

struct ScreenInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    /// 全局坐标（左上原点，和 CGEvent 一致）
    let bounds: CGRect

    static func all() -> [ScreenInfo] {
        NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            return ScreenInfo(id: id, name: s.localizedName, bounds: CGDisplayBounds(id))
        }
    }

    static func union(_ list: [ScreenInfo]) -> CGRect {
        list.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
    }
}

/// 映射与笔尖手感：在 HID 层改写数位笔事件的位置和压力，不改官方驱动
final class MappingEngine {
    var config = MappingConfig()
    var feel: Double = 0
    private var tap: CFMachPort?
    private var screens = ScreenInfo.all()

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screens = ScreenInfo.all()
        }
    }

    var isActive: Bool { config.enabled || abs(feel) > 0.01 }

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .tabletPointer]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, ctx in
            Unmanaged<MappingEngine>.fromOpaque(ctx!).takeUnretainedValue().handle(type, event)
        }, userInfo: ctx) else { return }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        guard isActive else { return Unmanaged.passUnretained(e) }
        let isPen = type == .tabletPointer ||
            e.getIntegerValueField(.mouseEventSubtype) == Int64(CGEventMouseSubtype.tabletPoint.rawValue)
        guard isPen else { return Unmanaged.passUnretained(e) }

        if config.enabled, ProcessInfo.processInfo.systemUptime - PenPosition.stamp < 0.5 {
            e.location = target(PenPosition.x, PenPosition.y)
        }
        if abs(feel) > 0.01 {
            let g = pow(2, feel * 1.5)   // >1 更硬，<1 更软
            let p = e.getDoubleValueField(.mouseEventPressure)
            if p > 0 { e.setDoubleValueField(.mouseEventPressure, value: pow(p, g)) }
            let tp = e.getDoubleValueField(.tabletEventPointPressure)
            if tp > 0 { e.setDoubleValueField(.tabletEventPointPressure, value: pow(min(1, tp), g)) }
        }
        return Unmanaged.passUnretained(e)
    }

    /// 映射的目标屏幕区域
    func targetRect() -> CGRect {
        var r: CGRect
        if let d = config.display, let s = screens.first(where: { $0.id == d }) { r = s.bounds }
        else { r = ScreenInfo.union(screens) }
        if let p = config.portion, p.count == 4 {
            r = CGRect(x: r.minX + p[0] * r.width, y: r.minY + p[1] * r.height, width: p[2] * r.width, height: p[3] * r.height)
        }
        if config.forceProportions == true {
            let a = config.area ?? [0, 0, 1, 1]
            let aspect = (a[2] * PenPosition.size.width) / max(0.001, a[3] * PenPosition.size.height)
            if r.width / r.height > aspect {
                let w = r.height * aspect
                r = CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height)
            } else {
                let h = r.width / aspect
                r = CGRect(x: r.minX, y: r.midY - h / 2, width: r.width, height: h)
            }
        }
        return r
    }

    func target(_ nx: Double, _ ny: Double) -> CGPoint {
        let a = config.area ?? [0, 0, 1, 1]
        let u = min(1, max(0, (nx - a[0]) / max(0.001, a[2])))
        let v = min(1, max(0, (ny - a[1]) / max(0.001, a[3])))
        let r = targetRect()
        return CGPoint(x: r.minX + u * (r.width - 1), y: r.minY + v * (r.height - 1))
    }
}
