import AppKit
import Carbon.HIToolbox

// MARK: - 动作的显示文字

extension Action {
    static let mediaNames: [(String, String)] = [
        ("volumeUp", L("音量 +")), ("volumeDown", L("音量 −")), ("mute", L("静音")),
        ("play", L("播放 / 暂停")), ("next", L("下一首")), ("previous", L("上一首")),
        ("brightnessUp", L("亮度 +")), ("brightnessDown", L("亮度 −")),
    ]

    /// 简短描述，例如 "⇧⌘C"、"向下滚动"
    var summary: String {
        switch type {
        case "key":
            guard let k = key else { return L("未设置快捷键") }
            return KeyMap.modsGlyph(mods) + KeyMap.glyph(k)
        case "scroll":
            let dy = self.dy ?? 0, dx = self.dx ?? 0
            if dy > 0 { return L("向上滚动") }
            if dy < 0 { return L("向下滚动") }
            if dx > 0 { return L("向左滚动") }
            if dx < 0 { return L("向右滚动") }
            return L("滚动")
        case "media":
            return Self.mediaNames.first { $0.0 == media }?.1 ?? L("媒体键")
        case "volume":
            let pct = Int(((step ?? 0.01) * 100).rounded())
            return pct >= 0 ? LF("音量 +%@%%", "\(pct)") : LF("音量 −%@%%", "\(-pct)")
        case "sequence":
            let s = (steps ?? []).map(\.summary)
            return s.isEmpty ? L("未设置序列") : s.joined(separator: " → ")
        case "app":
            guard let b = bundleID else { return L("未选择 App") }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                return LF("打开 %@", FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            }
            return LF("打开 %@", b)
        case "shell":
            return (command ?? "").isEmpty ? L("运行命令") : LF("运行：%@", command!)
        case "dialMode":
            return L("切换波轮模式")
        case "dragAdjust":
            return (step ?? 2) >= 0 ? L("数值增大") : L("数值减小")
        case "displayPresets":
            return L("色彩模式切换")
        case "audioOutputs":
            return L("切换声音输出")
        case "click":
            let names = [L("左键"), L("右键"), L("中键"), L("后退"), L("前进")]
            let n = names[safe: button ?? 0] ?? L("点击")
            return (count ?? 1) >= 2 ? L("双击") : n + L("单击")
        case "displayToggle":
            return L("显示切换")
        case "none":
            return L("禁用")
        default:
            return type
        }
    }

    /// 主标题：有自定义名称用名称，没有就用 summary
    var title: String {
        if let l = label, !l.isEmpty { return L(l) }   // 内置预设名会显示为当前语言
        return summary
    }

    /// 副标题：有自定义名称时显示具体按键
    var subtitle: String? {
        guard let l = label, !l.isEmpty, type != "none" else { return nil }
        var s = summary
        if type == "key", hold == true { s += L(" · 按住") }
        return s
    }

    var symbol: String {
        switch type {
        case "key": return "command"
        case "sequence": return "list.number"
        case "scroll": return "scroll"
        case "volume": return "speaker.wave.2"
        case "media":
            switch media ?? "" {
            case "volumeUp", "volumeDown", "mute": return "speaker.wave.2"
            case "brightnessUp", "brightnessDown": return "sun.max"
            default: return "playpause"
            }
        case "dragAdjust": return "arrow.left.and.right"
        case "displayPresets": return "display"
        case "audioOutputs": return "hifispeaker"
        case "app": return "app.badge"
        case "shell": return "terminal"
        case "dialMode": return "dial.medium"
        case "click": return "cursorarrow.click"
        case "displayToggle": return "display.2"
        default: return "nosign"
        }
    }

    /// 切换动作类型时生成一个新动作，保留名称
    static func fresh(_ type: String, label: String?) -> Action {
        var a: Action
        switch type {
        case "key": a = Action(type: "key")
        case "scroll": a = .scroll(dy: -40)
        case "media": a = .media("volumeUp")
        case "shell": a = Action(type: "shell", command: "")
        case "dialMode": a = .dialMode(1)
        case "volume": a = .volume(0.01)
        case "sequence": a = Action(type: "sequence", steps: [])
        case "app": a = Action(type: "app")
        default: a = Action(type: "none")
        }
        a.label = label
        return a
    }
}

// MARK: - 按键名 / 符号

extension KeyMap {
    private static let aliases: Set<String> = ["enter", "esc", "backspace", "command", "option", "alt", "control"]

    private static let reverse: [Int: String] = {
        var r: [Int: String] = [:]
        let names = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
                     "0","1","2","3","4","5","6","7","8","9","-","=","[","]","\\",";","'",",",".","/","`",
                     "space","return","tab","escape","delete","forwarddelete","left","right","up","down",
                     "home","end","pageup","pagedown","cmd","shift","opt","ctrl"]
        for n in names { if let c = code(n) { r[Int(c)] = n } }
        for i in 1...20 { if let c = code("f\(i)") { r[Int(c)] = "f\(i)" } }
        // 右侧修饰键
        r[kVK_RightCommand] = "cmd"; r[kVK_RightShift] = "shift"
        r[kVK_RightOption] = "opt"; r[kVK_RightControl] = "ctrl"
        return r
    }()

    static func name(for keyCode: UInt16) -> String? { reverse[Int(keyCode)] }

    static func glyph(_ key: String) -> String {
        switch key.lowercased() {
        case "space": return "space"
        case "return", "enter": return "↩"
        case "tab": return "⇥"
        case "escape", "esc": return "esc"
        case "delete", "backspace": return "⌫"
        case "forwarddelete": return "⌦"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "home": return "↖"
        case "end": return "↘"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        case "cmd", "command": return "⌘"
        case "shift": return "⇧"
        case "opt", "option", "alt": return "⌥"
        case "ctrl", "control": return "⌃"
        default: return key.uppercased()
        }
    }

    /// 拆成一个个键帽，用于界面显示
    static func keycaps(_ mods: [String]?, _ key: String?) -> [String] {
        let set = Set((mods ?? []).map { normalize($0) })
        var caps = ["ctrl", "opt", "shift", "cmd"].filter(set.contains).map(glyph)
        if let key { caps.append(glyph(key)) }
        return caps
    }

    static func modsGlyph(_ mods: [String]?) -> String {
        let set = Set((mods ?? []).map { normalize($0) })
        return ["ctrl", "opt", "shift", "cmd"].filter(set.contains).map(glyph).joined()
    }

    static func normalize(_ m: String) -> String {
        switch m.lowercased() {
        case "command": return "cmd"
        case "option", "alt": return "opt"
        case "control": return "ctrl"
        default: return m.lowercased()
        }
    }

    static func mods(from flags: NSEvent.ModifierFlags) -> [String] {
        var m: [String] = []
        if flags.contains(.control) { m.append("ctrl") }
        if flags.contains(.option) { m.append("opt") }
        if flags.contains(.shift) { m.append("shift") }
        if flags.contains(.command) { m.append("cmd") }
        return m
    }
}
