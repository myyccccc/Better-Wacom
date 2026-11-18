import Foundation

/// 一个动作。用 type 区分种类，其余字段按需填写。
///   key       快捷键        key: "z", mods: ["cmd","shift","opt","ctrl"], hold: 按住实体键时一直按着
///   sequence  连续快捷键    steps: [key 动作…]
///   scroll    滚动          dx, dy（像素）, mods: 滚动时按住的修饰键
///   volume    精细音量      step: 每格变化（0.01 = 1%），正数调高
///   media     媒体键        media: volumeUp / play / next …
///   app       打开 App      bundleID
///   shell     运行命令      command
///   dialMode  切换波轮模式  dial: 1 或 2
///   click     鼠标点击      button, count
///   displayToggle 显示切换  在「显示切换」列表里的显示器之间轮换映射
///   dragAdjust 调节数值     在鼠标所在位置模拟左右拖动（达芬奇等软件的数值框），step 为每格像素，正数向右（增大）
///   displayPresets 色彩模式 按住时弹出显示器预设列表，转波轮选择，松开切换
///   audioOutputs 声音输出  按住时弹出收藏的声音输出设备，转波轮选择，松开切换
///   none      禁用
struct Action: Codable, Equatable {
    var type: String
    var key: String?
    var mods: [String]?
    var hold: Bool?
    var dx: Int?
    var dy: Int?
    var step: Double?
    var media: String?
    var bundleID: String?
    var command: String?
    var steps: [Action]?
    var dial: Int?
    /// click：0 左键 1 右键 2 中键 3 后退 4 前进；count 为连击次数
    var button: Int?
    var count: Int?
    /// scroll：true 时按滚轮「格」滚动（dx / dy 为格数），用于 Capture One 这类按格识别滚轮的软件
    var lines: Bool?
    /// 在标签 / 提示里显示的名字（可选）
    var label: String?

    static func key(_ k: String, _ mods: [String] = [], _ label: String? = nil, hold: Bool? = nil) -> Action {
        Action(type: "key", key: k, mods: mods.isEmpty ? nil : mods, hold: hold, label: label)
    }
    static func scroll(dx: Int = 0, dy: Int = 0) -> Action {
        Action(type: "scroll", dx: dx == 0 ? nil : dx, dy: dy == 0 ? nil : dy)
    }
    static func volume(_ step: Double) -> Action { Action(type: "volume", step: step) }
    static func media(_ m: String) -> Action { Action(type: "media", media: m) }
    static func dialMode(_ d: Int) -> Action { Action(type: "dialMode", dial: d) }
    static let disabled = Action(type: "none")
}

struct DialMode: Codable, Equatable {
    var name: String
    var cw: Action   // 顺时针
    var ccw: Action  // 逆时针
    /// 转得越快，每格触发次数越多
    var accelerate: Bool?
}

struct DialConfig: Codable, Equatable {
    var modes: [DialMode]
}

struct Profile: Codable, Equatable {
    var name: String
    /// 键为按键硬件编号 "1"…"10"；长按动作的键为 "3L" 这样的形式
    var buttons: [String: Action]?
    /// 键为波轮硬件编号 "1"、"2"
    var dials: [String: DialConfig]?
}

/// 物理位置 → 硬件编号。由「按键位置」校准得到
struct PadLayout: Codable, Equatable {
    /// 左键环：上、外侧、下、内侧
    var leftKeys: [Int]
    /// 右键环：上、外侧、下、内侧
    var rightKeys: [Int]
    var leftToggle: Int
    var rightToggle: Int
    /// 波轮硬件编号（1 = byte4，2 = byte5）
    var leftDial: Int
    var rightDial: Int

    static let guess = PadLayout(leftKeys: [1, 2, 3, 4], rightKeys: [5, 6, 7, 8],
                                 leftToggle: 9, rightToggle: 10, leftDial: 1, rightDial: 2)

    var positions: [(PadTarget, Int)] {
        leftKeys.enumerated().map { (.leftKey($0.offset), $0.element) }
            + rightKeys.enumerated().map { (.rightKey($0.offset), $0.element) }
            + [(.leftToggle, leftToggle), (.rightToggle, rightToggle)]
    }
}

/// 映射：笔在板面上的位置 → 屏幕位置（由 Better Wacom 计算，不改官方驱动）
struct MappingConfig: Codable, Equatable {
    /// false 时完全交给官方驱动
    var enabled: Bool = false
    /// nil = 所有显示器；否则为显示器 ID
    var display: UInt32?
    /// 显示器的一部分（归一化 x, y, w, h），nil 为整块
    var portion: [Double]?
    var forceProportions: Bool?
    /// 板面区域（归一化 x, y, w, h），nil 为整块
    var area: [Double]?
    /// 「显示切换」轮换的显示器（nil 代表所有显示器）；为空时用全部显示器
    var toggle: [UInt32]?
}

struct PenConfig: Codable, Equatable {
    /// 笔尖手感：-1 最软 … 0 官方 … 1 最硬
    var feel: Double = 0
}

struct AppConfig: Codable {
    var invertDials: Bool?
    var mapping: MappingConfig?
    var pen: PenConfig?
    /// 一键接管：屏蔽 Wacom 驱动发出的键盘 / 滚动事件，由 Better Wacom 处理
    var takeover: Bool?
    var layout: PadLayout?
    /// 按住「色彩模式」键时可选的显示器预设（按名称）；nil = 默认的几个常用预设
    var displayPresets: [String]?
    /// 按住「声音输出」键时可选的输出设备（按名称）；nil = 有线耳机和 Beats
    var audioOutputs: [String]?
    /// "default" 为通用设置，其余键为 App 的 Bundle ID
    var profiles: [String: Profile]

    var padLayout: PadLayout { layout ?? .guess }
}

final class ConfigStore: ObservableObject {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Better Wacom", isDirectory: true)
    static let url = dir.appendingPathComponent("config.json")

    @Published private(set) var config: AppConfig = ConfigStore.defaultConfig {
        didSet { snapLock.lock(); snapshot = config; snapLock.unlock() }
    }
    /// 给后台引擎线程读的副本（主线程改配置时不会和读取冲突）
    private let snapLock = NSLock()
    private var snapshot: AppConfig = ConfigStore.defaultConfig
    var current: AppConfig { snapLock.lock(); defer { snapLock.unlock() }; return snapshot }
    @Published private(set) var lastError: String?

    /// 上次读到 / 写入的文件修改时间，用来发现外部改动（手动编辑、iCloud 恢复等）
    private var diskStamp: Date?

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func load() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.url.path) {
            try? fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            save(Self.defaultConfig)
        }
        diskStamp = Self.modificationDate()
        do {
            config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: Self.url))
            lastError = nil
        } catch {
            // 读不出来时先把原文件另存一份：之后界面上任何修改都会写回 config.json，
            // 不备份的话用户原来的整套设置会被内存里的默认配置覆盖掉
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            let backup = Self.dir.appendingPathComponent("config.json.broken-\(f.string(from: Date()))")
            try? fm.copyItem(at: Self.url, to: backup)
            lastError = LF("配置文件有误，已另存为 %@：%@", backup.lastPathComponent, error.localizedDescription)
            NSLog("BetterWacom: %@", lastError!)
        }
    }

    /// 软件运行时 config.json 被外部改了（手动编辑等）：重新读入，免得之后被内存里的旧配置整个覆盖。
    /// 新内容解析失败时保留当前配置，不备份也不覆盖，等文件修好再读。主线程调用。
    func reloadIfChangedOnDisk() {
        guard let stamp = Self.modificationDate(), stamp != diskStamp else { return }
        diskStamp = stamp
        guard let data = try? Data(contentsOf: Self.url) else { return }
        do {
            let c = try JSONDecoder().decode(AppConfig.self, from: data)
            if (try? JSONEncoder().encode(c)) != (try? JSONEncoder().encode(config)) { config = c }
            lastError = nil
        } catch {
            lastError = LF("配置文件有误：%@", error.localizedDescription)
        }
    }

    /// 修改配置并立即写回磁盘
    func mutate(_ change: (inout AppConfig) -> Void) {
        var c = config
        change(&c)
        config = c
        save(c)
        onSave?()
    }

    /// 整体替换（从云端恢复时使用）
    func replace(_ c: AppConfig) {
        config = c
        save(c)
    }

    var onSave: (() -> Void)?

    func resetToDefault() {
        var c = Self.defaultConfig
        if let l = config.layout { c = Self.remap(c, from: .guess, to: l); c.layout = l }
        c.invertDials = config.invertDials
        config = c
        save(c)
    }

    private func save(_ c: AppConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // 原子写入：先写临时文件再替换，写到一半崩溃也不会留下半个配置文件
        try? enc.encode(c).write(to: Self.url, options: .atomic)
        diskStamp = Self.modificationDate()
    }

    /// 某个按键（slot 为 "3" 或长按 "3L"）在当前 App 下的动作
    func action(slot: String, bundleID: String?) -> Action? {
        let config = current
        if let b = bundleID, let a = config.profiles[b]?.buttons?[slot] { return a }
        return config.profiles["default"]?.buttons?[slot]
    }

    func dial(_ n: Int, bundleID: String?) -> (String, DialConfig)? {
        let config = current
        let k = String(n)
        if let b = bundleID, let d = config.profiles[b]?.dials?[k], !d.modes.isEmpty { return (b, d) }
        if let d = config.profiles["default"]?.dials?[k], !d.modes.isEmpty { return ("default", d) }
        return nil
    }

    /// 校准后把按「物理位置」写的设置搬到新的硬件编号上
    static func remap(_ c: AppConfig, from old: PadLayout, to new: PadLayout) -> AppConfig {
        var c = c
        let oldPos = Dictionary(uniqueKeysWithValues: old.positions.map { ($0.0, $0.1) })
        let newPos = Dictionary(uniqueKeysWithValues: new.positions.map { ($0.0, $0.1) })
        var hwMap: [Int: Int] = [:]
        for (pos, o) in oldPos { if let n = newPos[pos] { hwMap[o] = n } }
        let dialMap = [old.leftDial: new.leftDial, old.rightDial: new.rightDial]

        for key in c.profiles.keys {
            if let b = c.profiles[key]?.buttons {
                var nb: [String: Action] = [:]
                for (slot, var a) in b {
                    let isLong = slot.hasSuffix("L")
                    guard let o = Int(isLong ? String(slot.dropLast()) : slot) else { continue }
                    let n = hwMap[o] ?? o
                    if a.type == "dialMode", let d = a.dial { a.dial = dialMap[d] ?? d }
                    nb["\(n)\(isLong ? "L" : "")"] = a
                }
                c.profiles[key]?.buttons = nb
            }
            if let d = c.profiles[key]?.dials {
                var nd: [String: DialConfig] = [:]
                for (k, v) in d { if let o = Int(k) { nd[String(dialMap[o] ?? o)] = v } }
                c.profiles[key]?.dials = nd
            }
        }
        return c
    }

    // MARK: - 默认配置（按「猜测布局」的硬件编号书写）

    static var defaultConfig: AppConfig {
        let def = Profile(
            name: L("通用"),
            buttons: [
                "9": .key("f1", [], L("截图")),
                "10": .dialMode(2),
                "1": .key("z", ["cmd"], L("撤销")),
                "2": .key("z", ["cmd", "shift"], L("重做")),
                "3": .key("c", ["cmd"], L("复制")),
                "4": .key("v", ["cmd"], L("粘贴")),
                "5": .key("up", ["ctrl"], L("调度中心")),
                "6": .key("space", ["cmd"], L("聚焦搜索")),
                "7": .key("tab", ["cmd"], L("切换 App")),
                "8": .key("s", ["cmd"], L("保存")),
            ],
            dials: [
                "1": DialConfig(modes: [
                    DialMode(name: L("滚动"), cw: .scroll(dy: -30), ccw: .scroll(dy: 30), accelerate: true),
                    DialMode(name: L("缩放"), cw: .key("=", ["cmd"]), ccw: .key("-", ["cmd"])),
                ]),
                "2": DialConfig(modes: [
                    DialMode(name: L("音量"), cw: .volume(0.01), ccw: .volume(-0.01), accelerate: true),
                    DialMode(name: L("屏幕亮度"), cw: .media("brightnessUp"), ccw: .media("brightnessDown")),
                ]),
            ]
        )

        let lightroom = Profile(
            name: "Lightroom Classic",
            buttons: [
                "1": .key("z", ["cmd"], L("撤销")),
                "2": .key("left", [], L("上一张")),
                "3": .key("z", ["cmd", "shift"], L("重做")),
                "4": .key("right", [], L("下一张")),
                "5": .key("p", [], L("标记留用")),
                "6": .key("\\", [], L("前后对比")),
                "7": .key("x", [], L("标记排除")),
                "8": .key("space", [], L("抓手"), hold: true),
            ],
            dials: [
                "1": DialConfig(modes: [
                    DialMode(name: L("笔刷大小"), cw: .key("]"), ccw: .key("[")),
                    DialMode(name: L("笔刷羽化"), cw: .key("]", ["shift"]), ccw: .key("[", ["shift"])),
                ]),
            ]
        )

        let resolve = Profile(
            name: "DaVinci Resolve",
            buttons: [
                "1": .key("b", ["cmd"], L("切割")),
                "2": .key("i", [], L("入点")),
                "3": .key("delete", ["shift"], L("波纹删除")),
                "4": .key("o", [], L("出点")),
                "5": .key("space", [], L("播放 / 暂停")),
                "6": .key("m", [], L("标记")),
                "7": .key("z", ["cmd"], L("撤销")),
                "8": .key("z", ["cmd", "shift"], L("重做")),
            ],
            dials: [
                "1": DialConfig(modes: [
                    DialMode(name: L("逐帧"), cw: .key("right"), ccw: .key("left"), accelerate: true),
                    DialMode(name: L("时间线缩放"), cw: .key("=", ["cmd"]), ccw: .key("-", ["cmd"])),
                    DialMode(name: L("剪辑点"), cw: .key("down"), ccw: .key("up")),
                ]),
            ]
        )

        return AppConfig(invertDials: false, takeover: false, layout: nil, profiles: [
            "default": def,
            "com.adobe.LightroomClassicCC7": lightroom,
            "com.blackmagic-design.DaVinciResolve": resolve,
        ])
    }
}
