import SwiftUI

/// 动作目录：分组方式参照 Wacom Center 的 Actions 面板
struct CatalogItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// 需要进一步设置（进入第二级）
    var editable = false
    let make: () -> Action
    var matches: (Action) -> Bool
}

struct CatalogGroup: Identifiable {
    let id: String
    let title: String
    let items: [CatalogItem]
}

enum ActionCatalog {
    private static func key(_ id: String, _ title: String, _ symbol: String, _ k: String, _ mods: [String] = []) -> CatalogItem {
        CatalogItem(id: id, title: title, symbol: symbol,
                    make: { .key(k, mods, title) },
                    matches: { $0.type == "key" && $0.key == k && Set($0.mods ?? []) == Set(mods) && $0.hold != true })
    }
    private static func media(_ id: String, _ title: String, _ symbol: String, _ m: String) -> CatalogItem {
        CatalogItem(id: id, title: title, symbol: symbol, make: { var a = Action.media(m); a.label = title; return a },
                    matches: { $0.type == "media" && $0.media == m })
    }
    private static func click(_ id: String, _ title: String, _ symbol: String, _ b: Int, _ n: Int = 1) -> CatalogItem {
        CatalogItem(id: id, title: title, symbol: symbol,
                    make: { Action(type: "click", button: b, count: n == 1 ? nil : n, label: title) },
                    matches: { $0.type == "click" && ($0.button ?? 0) == b && ($0.count ?? 1) == n })
    }

    static let shortcut = CatalogItem(id: "shortcut", title: L("快捷键"), symbol: "command", editable: true,
                                      make: { Action(type: "key") }, matches: { $0.type == "key" && !isModifierOnly($0) })
    static let modifier = CatalogItem(id: "modifier", title: L("修饰键"), symbol: "shift", editable: true,
                                      make: { Action(type: "key", key: "shift", hold: true) }, matches: { isModifierOnly($0) })
    static let sequence = CatalogItem(id: "sequence", title: L("连续快捷键"), symbol: "list.number", editable: true,
                                      make: { Action(type: "sequence", steps: []) }, matches: { $0.type == "sequence" })
    static let fineVolume = CatalogItem(id: "volume", title: L("精细音量"), symbol: "speaker.wave.2", editable: true,
                                        make: { .volume(0.01) }, matches: { $0.type == "volume" })
    static let scroll = CatalogItem(id: "scroll", title: L("滚动"), symbol: "scroll", editable: true,
                                    make: { .scroll(dy: -40) }, matches: { $0.type == "scroll" })
    static let app = CatalogItem(id: "app", title: L("打开 App"), symbol: "app.badge", editable: true,
                                 make: { Action(type: "app") }, matches: { $0.type == "app" })
    static let shell = CatalogItem(id: "shell", title: L("运行命令"), symbol: "terminal", editable: true,
                                   make: { Action(type: "shell", command: "") }, matches: { $0.type == "shell" })
    static let dialMode = CatalogItem(id: "dialMode", title: L("波轮切换"), symbol: "dial.medium", editable: true,
                                      make: { .dialMode(1) }, matches: { $0.type == "dialMode" })
    static let dragAdjust = CatalogItem(id: "dragAdjust", title: L("调节数值"), symbol: "slider.horizontal.3", editable: true,
                                        make: { Action(type: "dragAdjust", step: 2) }, matches: { $0.type == "dragAdjust" })
    static let displayPresets = CatalogItem(id: "displayPresets", title: L("色彩模式切换"), symbol: "display",
                                            make: { Action(type: "displayPresets", label: L("色彩模式切换")) },
                                            matches: { $0.type == "displayPresets" })
    static let audioOutputs = CatalogItem(id: "audioOutputs", title: L("切换声音输出"), symbol: "hifispeaker", editable: true,
                                          make: { Action(type: "audioOutputs", label: L("切换声音输出")) },
                                          matches: { $0.type == "audioOutputs" })
    static let displayToggle = CatalogItem(id: "displayToggle", title: L("显示切换"), symbol: "display.2",
                                           make: { Action(type: "displayToggle") }, matches: { $0.type == "displayToggle" })

    static func isModifierOnly(_ a: Action) -> Bool {
        a.type == "key" && a.hold == true && ["cmd", "shift", "opt", "ctrl"].contains(a.key ?? "")
    }

    static func groups(allowDialMode: Bool) -> [CatalogGroup] {
        var rec: [CatalogItem] = [shortcut, key("undo", L("撤销"), "arrow.uturn.backward", "z", ["cmd"]), modifier]
        if allowDialMode { rec.append(dialMode) }
        rec += [dragAdjust, key("zoomIn", L("放大"), "plus.magnifyingglass", "=", ["cmd"]), key("zoomOut", L("缩小"), "minus.magnifyingglass", "-", ["cmd"]), fineVolume]
        var tablet: [CatalogItem] = []
        if allowDialMode { tablet.append(dialMode); tablet.append(displayPresets); tablet.append(audioOutputs) }
        return [
            CatalogGroup(id: "rec", title: L("推荐"), items: rec),
            CatalogGroup(id: "click", title: L("点击"), items: [
                click("left", L("左键单击"), "cursorarrow.click", 0),
                click("right", L("右键单击"), "contextualmenu.and.cursorarrow", 1),
                click("middle", L("中键单击"), "computermouse", 2),
                click("double", L("双击"), "cursorarrow.click.2", 0, 2),
                click("back", L("后退"), "chevron.backward", 3),
                click("forward", L("前进"), "chevron.forward", 4),
            ]),
            CatalogGroup(id: "keyboard", title: L("键盘"), items: [
                shortcut, modifier, sequence,
                key("undo", L("撤销"), "arrow.uturn.backward", "z", ["cmd"]),
                key("redo", L("重做"), "arrow.uturn.forward", "z", ["cmd", "shift"]),
                key("cut", L("剪切"), "scissors", "x", ["cmd"]),
                key("copy", L("复制"), "doc.on.doc", "c", ["cmd"]),
                key("paste", L("粘贴"), "doc.on.clipboard", "v", ["cmd"]),
                key("all", L("全选"), "selection.pin.in.out", "a", ["cmd"]),
                key("save", L("保存"), "square.and.arrow.down", "s", ["cmd"]),
            ]),
            CatalogGroup(id: "nav", title: L("导航"), items: [
                scroll, dragAdjust,
                key("zoomIn", L("放大"), "plus.magnifyingglass", "=", ["cmd"]),
                key("zoomOut", L("缩小"), "minus.magnifyingglass", "-", ["cmd"]),
                key("mission", L("调度中心"), "rectangle.3.group", "up", ["ctrl"]),
                key("appswitch", L("切换 App"), "square.stack", "tab", ["cmd"]),
                key("spaceL", L("左边的桌面"), "arrow.left.square", "left", ["ctrl"]),
                key("spaceR", L("右边的桌面"), "arrow.right.square", "right", ["ctrl"]),
                key("spotlight", L("聚焦搜索"), "magnifyingglass", "space", ["cmd"]),
                key("shot", L("截图"), "camera.viewfinder", "5", ["cmd", "shift"]),
            ]),
            CatalogGroup(id: "media", title: L("媒体"), items: [
                fineVolume,
                media("vup", L("音量 +"), "speaker.plus", "volumeUp"),
                media("vdown", L("音量 −"), "speaker.minus", "volumeDown"),
                media("mute", L("静音"), "speaker.slash", "mute"),
                media("play", L("播放 / 暂停"), "playpause", "play"),
                media("next", L("下一首"), "forward", "next"),
                media("prev", L("上一首"), "backward", "previous"),
                media("bup", L("亮度 +"), "sun.max", "brightnessUp"),
                media("bdown", L("亮度 −"), "sun.min", "brightnessDown"),
            ]),
            CatalogGroup(id: "tablet", title: L("平板"), items: tablet),
            CatalogGroup(id: "apps", title: L("应用程序"), items: [app, shell]),
        ].filter { !$0.items.isEmpty }
    }

    /// 当前动作对应的目录项：先找预设，再找通用项
    static func item(for a: Action?, in groups: [CatalogGroup]) -> CatalogItem? {
        guard let a, a.type != "none" else { return nil }
        let all = groups.flatMap(\.items)
        if let preset = all.first(where: { !$0.editable && $0.matches(a) }) { return preset }
        if isModifierOnly(a) { return modifier }
        return all.first { $0.editable && $0.matches(a) }
    }
}
