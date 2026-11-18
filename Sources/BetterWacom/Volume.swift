import AudioToolbox
import CoreAudio

/// 直接读写默认输出设备的主音量（比系统音量键的 1/16 精细得多）
enum SystemVolume {
    /// 默认输出设备每秒最多查一次（快转时每格都查会多出很多跨进程调用）
    private static var cached: (AudioDeviceID, TimeInterval)?
    private static let lock = NSLock()

    private static func defaultDevice() -> AudioDeviceID? {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let (id, t) = cached, now - t < 1 { lock.unlock(); return id }
        lock.unlock()
        guard let id = queryDefaultDevice() else { return nil }
        lock.lock(); cached = (id, now); lock.unlock()
        return id
    }

    private static func queryDefaultDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return s == noErr ? id : nil
    }

    private static var volumeAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static var volume: Float? {
        guard let dev = defaultDevice() else { return nil }
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &volumeAddr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static var isMuted: Bool {
        guard let dev = defaultDevice() else { return false }
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &size, &m) == noErr && m != 0
    }

    /// 设置音量，返回实际生效的值；输出设备不支持时返回 nil
    @discardableResult
    static func set(_ value: Float, checkMute: Bool = true) -> Float? {
        guard let dev = defaultDevice() else { return nil }
        var v = min(max(value, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectSetPropertyData(dev, &volumeAddr, 0, nil, size, &v) == noErr else { return nil }
        if v > 0, checkMute, isMuted {
            var m = UInt32(0)
            AudioObjectSetPropertyData(dev, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
        return v
    }
}
