import AppKit
import CoreAudio
import SwiftUI

/// 声音输出设备（系统设置 → 声音 → 输出）。按设备名称记收藏：蓝牙耳机断开后重连，名称不变。只在主线程调用。
enum AudioOutputs {
    struct Device: Hashable { let id: AudioDeviceID; let name: String; let transport: UInt32 }

    /// 用户没选时的默认收藏：有线耳机 + 名字里带 Beats 的设备
    static func isDefaultFavorite(_ name: String) -> Bool {
        name == "External Headphones" || name == "外置耳机" || name.localizedCaseInsensitiveContains("Beats")
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ sel: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr, let s = v?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func uint32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = address(sel)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v
    }

    /// 当前可用的输出设备（系统顺序，去掉隐藏和虚拟设备）
    static func all() -> [Device] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var sa = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var ss: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ss) == noErr, ss > 0 else { return nil }
            guard uint32(id, kAudioDevicePropertyIsHidden) == 0,
                  uint32(id, kAudioDevicePropertyTransportType) != kAudioDeviceTransportTypeVirtual,
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: id, name: name, transport: uint32(id, kAudioDevicePropertyTransportType))
        }
    }

    static var currentName: String? {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &id) == noErr else { return nil }
        return string(id, kAudioObjectPropertyName)
    }

    /// 勾选的设备里当前连着的。用户勾选过就严格只列勾选的；还没勾选过时按默认规则，不足两个列出全部
    static func favorites(_ chosen: [String]?) -> [Device] {
        let list = all()
        if let chosen { return list.filter { chosen.contains($0.name) } }
        let picked = list.filter { isDefaultFavorite($0.name) }
        return picked.count >= 2 ? picked : list
    }

    /// 切换默认输出（提示音也跟着走，和在系统设置里选一样）
    @discardableResult
    static func apply(_ name: String) -> Bool {
        guard var id = all().first(where: { $0.name == name })?.id else { return false }
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        let ok = AudioObjectSetPropertyData(system, &a, 0, nil, size, &id) == noErr
        var b = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        AudioObjectSetPropertyData(system, &b, 0, nil, size, &id)
        return ok
    }

    /// 设备名去掉「USB - 」这类前缀做标题，连接方式做说明，按设备类型配图标
    static func pickerItem(_ d: Device) -> PickerItem {
        var title = d.name
        for prefix in ["USB - ", "USB-"] where title.hasPrefix(prefix) { title = String(title.dropFirst(prefix.count)) }
        let via: String? = {
            switch d.transport {
            case kAudioDeviceTransportTypeUSB: return "USB"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return L("蓝牙")
            case kAudioDeviceTransportTypeBuiltIn: return L("内建")
            case kAudioDeviceTransportTypeHDMI: return "HDMI"
            case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
            case kAudioDeviceTransportTypeThunderbolt: return L("雷雳")
            case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
            default: return nil
            }
        }()
        let n = d.name.lowercased()
        let (symbol, tint): (String, Color) =
            n.contains("beats pill") ? ("beats.pill.fill", .red) :
            n.contains("beats") ? ("beats.headphones", .red) :
            n.contains("airpods max") ? ("airpodsmax", .gray) :
            n.contains("airpods pro") ? ("airpods.pro", .gray) :
            n.contains("airpods") ? ("airpods", .gray) :
            n.contains("headphone") || n.contains("耳机") ? ("headphones", .blue) :
            n.contains("display") ? ("display", .indigo) :
            n.contains("mac studio") ? ("macstudio.fill", .gray) :
            n.contains("macbook") ? ("laptopcomputer", .gray) :
            n.contains("homepod") ? ("homepod.fill", .gray) :
            d.transport == kAudioDeviceTransportTypeAirPlay ? ("airplayaudio", .blue) :
            d.transport == kAudioDeviceTransportTypeBluetooth || d.transport == kAudioDeviceTransportTypeBluetoothLE ? ("headphones", .blue) :
            ("hifispeaker.fill", .orange)
        return PickerItem(name: d.name, title: title, detail: via, symbol: symbol, tint: tint)
    }

    /// 长按音量键：弹出收藏的输出设备，转波轮选择，松开切换
    static func showPicker(favorites chosen: [String]?) {
        let list = favorites(chosen).map(pickerItem)
        guard !list.isEmpty else {
            HUD.shared.show(symbol: "hifispeaker", title: L(chosen == nil ? "没有可用的声音输出设备" : "勾选的声音输出设备都没有连接"))
            return
        }
        let header = PickerHeader(title: L("声音输出"), subtitle: nil, symbol: "speaker.wave.3.fill",
                                  colors: [Color(red: 1, green: 0.32, blue: 0.42), Color(red: 0.92, green: 0.15, blue: 0.3)])
        PresetPicker.shared.begin(tag: "声音输出", header: header, items: list, active: currentName) { name in
            apply(name)
            return currentName
        }
    }
}
