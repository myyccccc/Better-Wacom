import AppKit
import CoreGraphics

/// 波轮调节鼠标下的数值：在当前鼠标位置模拟「按住左键左右拖动」。
/// 达芬奇的数值框（Temp、Tint、对比度……）都是左右拖动调节，这样不用知道具体是哪个参数。
/// - 连续转动期间左键一直按住，只发拖动增量（不会每格产生一次撤销记录，也最跟手）
/// - 停手 0.4 秒后松开左键（慢转时也不会每格都松开一次），并把鼠标放回原位
/// - 单次拖动走得太远（接近屏幕边缘）时，会松开、回到原位再接着拖
final class DragAdjuster {
    static let shared = DragAdjuster()
    private let queue = DispatchQueue(label: "BetterWacom.drag", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: Double = 0
    private var running = false
    private let source = CGEventSource(stateID: .hidSystemState)
    private static let idleRelease: TimeInterval = 0.4
    private static let maxTravel: CGFloat = 300

    /// px：本次要拖动的像素（正数向右）
    func add(_ px: Double) {
        lock.lock()
        pending += px
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { self.run() } }
    }

    private func take() -> CGFloat {
        lock.lock(); defer { lock.unlock() }
        let whole = pending.rounded(.towardZero)
        pending -= whole
        return CGFloat(whole)
    }

    private func post(_ type: CGEventType, _ p: CGPoint, dx: CGFloat = 0) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        if type == .leftMouseDragged { e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx)) }
        e.post(tap: .cghidEventTap)
    }

    private func run() {
        let origin = CGEvent(source: nil)?.location ?? .zero
        var x = origin.x
        post(.leftMouseDown, origin)
        usleep(6_000)
        var idleSince = ProcessInfo.processInfo.systemUptime
        while true {
            let d = take()
            if d != 0 {
                if abs(x + d - origin.x) > Self.maxTravel {
                    // 走太远：松开 → 回原位 → 重新按下，继续拖
                    post(.leftMouseUp, CGPoint(x: x, y: origin.y))
                    CGWarpMouseCursorPosition(origin)
                    usleep(6_000)
                    post(.leftMouseDown, origin)
                    usleep(6_000)
                    x = origin.x
                }
                x += d
                post(.leftMouseDragged, CGPoint(x: x, y: origin.y), dx: d)
                idleSince = ProcessInfo.processInfo.systemUptime
                usleep(3_000)
            } else if ProcessInfo.processInfo.systemUptime - idleSince > Self.idleRelease {
                lock.lock()
                if abs(pending) >= 1 { lock.unlock(); continue }
                pending = 0
                running = false
                lock.unlock()
                post(.leftMouseUp, CGPoint(x: x, y: origin.y))
                CGWarpMouseCursorPosition(origin)
                CGAssociateMouseAndMouseCursorPosition(1)
                return
            } else {
                usleep(3_000)
            }
        }
    }
}
