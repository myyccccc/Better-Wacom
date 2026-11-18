import Foundation
import IOKit.hid

/// 解析后的一帧控制面板状态（来自 report id 0x11）
struct PadFrame: Equatable {
    /// bit0..7 = byte1 的 8 个键（按键 1–8），bit8..9 = byte3 的 2 个键（按键 9–10）
    var buttons: UInt16
    /// 两个波轮本帧的相对增量（7 位有符号数）
    var dial1: Int
    var dial2: Int
}

enum PadParser {
    static let reportID: UInt32 = 0x11
    static let buttonCount = 10

    /// 7 位补码：0x01 = +1，0x7F = -1
    static func signed7(_ b: UInt8) -> Int {
        let v = Int(b & 0x7F)
        return v >= 0x40 ? v - 0x80 : v
    }

    static func parse(_ r: UnsafePointer<UInt8>, _ len: Int) -> PadFrame? {
        guard len >= 6, r[0] == 0x11 else { return nil }
        let buttons = UInt16(r[1]) | (UInt16(r[3] & 0x03) << 8)
        return PadFrame(buttons: buttons, dial1: signed7(r[4]), dial2: signed7(r[5]))
    }
}

/// 非独占、只读地监听 Wacom 设备。不会 seize，也不会向设备写任何数据。
/// HID 回调跑在独立的高优先级线程上，界面再忙也不会拖慢按键和波轮。
/// onFrame / onConnectionChange 在这个后台线程上调用。
final class DeviceService {
    var onFrame: ((PadFrame) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private let lock = NSLock()
    private var connectedCount = 0
    private static let bufferSize = 256
    private var thread: Thread?
    private var reportCount = 0

    func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in
            self?.setup()
            CFRunLoopRun()
        }
        t.name = "BetterWacom.HID"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    private func setup() {
        // 只匹配按键 / 波轮所在的 Generic Desktop 接口（page 0x01）；
        // 不打开 Wacom 驱动自己通信用的私有接口（0xFFD1），避免干扰官方驱动
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x056A, kIOHIDPrimaryUsagePageKey: 0x01]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<DeviceService>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<DeviceService>.fromOpaque(ctx!).takeUnretainedValue().detach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        // kIOHIDOptionsTypeNone：普通打开，官方驱动照常工作
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess { NSLog("BetterWacom: IOHIDManagerOpen 失败 0x%x", r) }
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        EventLog.add(String(format: "HID 打开结果 0x%x，输入监控权限 %@", r,
                            access == kIOHIDAccessTypeGranted ? "已授权" : access == kIOHIDAccessTypeDenied ? "被拒绝" : "未决定"))
    }

    var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return connectedCount > 0 }

    private func attach(_ device: IOHIDDevice) {
        // 控制面板数据在 Generic Desktop（page 0x01）接口上
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        EventLog.add("发现 Wacom 接口 page 0x\(String(page, radix: 16)) usage 0x\(String(usage, radix: 16))")
        guard page == 0x01, buffers[device] == nil else { return }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.bufferSize)
        buffers[device] = buf
        lock.lock(); connectedCount = buffers.count; lock.unlock()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, Self.bufferSize, { ctx, _, _, _, id, report, len in
            let me = Unmanaged<DeviceService>.fromOpaque(ctx!).takeUnretainedValue()
            me.reportCount += 1
            if me.reportCount <= 3 { EventLog.add("收到报告 id 0x\(String(id, radix: 16)) 长度 \(len)") }
            guard id == PadParser.reportID, let frame = PadParser.parse(report, len) else { return }
            me.onFrame?(frame)
        }, ctx)
        onConnectionChange?(true)
    }

    private func detach(_ device: IOHIDDevice) {
        if let buf = buffers.removeValue(forKey: device) { buf.deallocate() }
        lock.lock(); connectedCount = buffers.count; lock.unlock()
        onConnectionChange?(isConnected)
    }
}

/// 笔在板面上的最新位置（归一化 0…1，左上为原点）
enum PenPosition {
    static var x: Double = 0.5
    static var y: Double = 0.5
    static var stamp: TimeInterval = 0
    /// 板面物理尺寸（毫米），用于强制比例
    static let size = CGSize(width: 263, height: 148)
}
