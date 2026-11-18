import SwiftUI

/// 编辑一个动作。action 为 nil 表示「跟随通用设置」（仅当 inheritedSummary 不为 nil 时可选）
struct ActionEditor: View {
    @EnvironmentObject var model: AppModel
    var title: String? = nil
    @Binding var action: Action?
    var inheritedSummary: String? = nil
    var allowDialMode = false
    var noneLabel = L("禁用")

    /// 第二级：正在设置的目录项
    @State private var editing: CatalogItem?
    @State private var expanded: Set<String> = []

    private var groups: [CatalogGroup] { ActionCatalog.groups(allowDialMode: allowDialMode) }
    private var current: CatalogItem? { ActionCatalog.item(for: action, in: groups) }

    /// 修改当前动作的某个字段
    private func edit(_ change: (inout Action) -> Void) {
        guard var a = action else { return }
        change(&a)
        action = a
    }

    var body: some View {
        list
            .onAppear {
                expanded = ["rec"]
                if let c = current, let g = groups.first(where: { $0.items.contains { $0.id == c.id } }) {
                    expanded.insert(g.id)
                    if c.editable { editing = c }
                }
            }
    }

    // MARK: 第一级：分组列表

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title).font(.headline).padding(.horizontal, 12).padding(.bottom, 6)
                }
                ForEach(groups) { g in
                    GroupHeader(title: g.title, open: expanded.contains(g.id)) {
                        if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
                    }
                    if expanded.contains(g.id) {
                        ForEach(g.items) { item in
                            let open = editing?.id == item.id && current?.id == item.id
                            ItemRow(symbol: item.symbol, title: item.title,
                                    detail: current?.id == item.id && item.editable && !open ? action.map { model.summary(of: $0) } : nil,
                                    selected: current?.id == item.id, chevron: item.editable, open: open) { choose(item) }
                            if open { inlineEditor(item) }
                        }
                    }
                }
                GroupHeader(title: L("其他"), open: true) {}
                    .allowsHitTesting(false)
                if let s = inheritedSummary {
                    ItemRow(symbol: "arrow.turn.left.up", title: L("跟随通用设置"), detail: s, selected: action == nil, chevron: false) { action = nil }
                }
                ItemRow(symbol: "xmark", title: noneLabel, detail: nil,
                        selected: action?.type == "none" || (action == nil && inheritedSummary == nil), chevron: false) {
                    action = Action(type: "none")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(maxHeight: .infinity)
    }

    private func choose(_ item: CatalogItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if item.editable {
                if current?.id != item.id { action = item.make(); editing = item }
                else { editing = editing?.id == item.id ? nil : item }
            } else {
                action = item.make()
                editing = nil
            }
        }
    }

    // MARK: 展开在行下方的设置

    private func inlineEditor(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let a = action {
                if item.id == "modifier" { modifierSection } else { detail(a) }
                TextField("名称", text: Binding(
                    get: { action?.label ?? "" },
                    set: { v in edit { $0.label = v.isEmpty ? nil : v } }
                ), prompt: Text("名称（可选）"))
                .textFieldStyle(.roundedBorder)
            }
        }
        .controlSize(.small)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.leading, 30)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// 修饰键：按住实体键时一直按住所选修饰键
    private var modifierSection: some View {
        let all: [(String, String)] = [("cmd", "⌘"), ("shift", "⇧"), ("opt", "⌥"), ("ctrl", "⌃")]
        let on = Set([action?.key].compactMap { $0 } + (action?.mods ?? []))
        return Section {
            HStack(spacing: 8) {
                ForEach(all, id: \.0) { k, g in
                    let isOn = on.contains(k)
                    Button {
                        var s = on
                        if isOn { s.remove(k) } else { s.insert(k) }
                        let ordered = all.map(\.0).filter { s.contains($0) }
                        guard let first = ordered.first else { return }
                        edit { $0.key = first; $0.mods = ordered.count > 1 ? Array(ordered.dropFirst()) : nil; $0.hold = true }
                    } label: {
                        Text(g).font(.system(size: 17, weight: .medium))
                            .frame(width: 52, height: 40)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isOn ? Color.accentColor : Color.primary.opacity(0.06)))
                            .foregroundStyle(isOn ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Text("按住实体键时保持按下").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detail(_ a: Action) -> some View {
        switch a.type {
        case "key":
            Section {
                LabeledContent("快捷键") {
                    ShortcutRecorder(key: Binding(get: { action?.key }, set: { v in edit { $0.key = v } }),
                                     mods: Binding(get: { action?.mods }, set: { v in edit { $0.mods = v } }))
                }
                Toggle("按住实体键时保持按下", isOn: Binding(
                    get: { action?.hold ?? false }, set: { v in edit { $0.hold = v ? true : nil } }))
            }

        case "sequence":
            Section {
                ForEach(Array((a.steps ?? []).enumerated()), id: \.offset) { i, step in
                    HStack {
                        Text("\(i + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                        ShortcutRecorder(
                            key: Binding(get: { action?.steps?[safe: i]?.key }, set: { v in edit { $0.steps?[i].key = v } }),
                            mods: Binding(get: { action?.steps?[safe: i]?.mods }, set: { v in edit { $0.steps?[i].mods = v } }))
                        Spacer()
                        Button { edit { $0.steps?.remove(at: i) } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    edit { $0.steps = ($0.steps ?? []) + [Action(type: "key")] }
                } label: {
                    Label("添加一步", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled((a.steps?.count ?? 0) >= 8)
            }

        case "volume":
            Section {
                Picker("方向", selection: Binding(
                    get: { (action?.step ?? 0.01) >= 0 },
                    set: { up in edit { $0.step = abs($0.step ?? 0.01) * (up ? 1 : -1) } })) {
                    Text("调高").tag(true)
                    Text("调低").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper(value: Binding(
                    get: { Int((abs(action?.step ?? 0.01) * 100).rounded()) },
                    set: { v in edit { $0.step = Double(v) / 100 * (($0.step ?? 0.01) >= 0 ? 1 : -1) } }),
                        in: 1...10) {
                    LabeledContent("每次变化", value: "\(Int((abs(a.step ?? 0.01) * 100).rounded()))%")
                }
            }

        case "dragAdjust":
            Section {
                Picker("方向", selection: Binding(
                    get: { (action?.step ?? 2) >= 0 },
                    set: { up in edit { $0.step = abs($0.step ?? 2) * (up ? 1 : -1) } })) {
                    Text("增大（向右拖）").tag(true)
                    Text("减小（向左拖）").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper(value: Binding(
                    get: { Int(abs(action?.step ?? 2).rounded()) },
                    set: { v in edit { $0.step = Double(v) * (($0.step ?? 2) >= 0 ? 1 : -1) } }),
                        in: 1...20) {
                    LabeledContent("每格移动", value: LF("%@ 像素", "\(Int(abs(a.step ?? 2).rounded()))"))
                }
            } footer: {
                Text("鼠标停在数值上转动波轮，等于按住它左右拖动；慢转微调，快转幅度更大").font(.caption).foregroundStyle(.secondary)
            }

        case "scroll":
            Section {
                Picker("方向", selection: scrollDirection) {
                    Image(systemName: "arrow.up").tag(0)
                    Image(systemName: "arrow.down").tag(1)
                    Image(systemName: "arrow.left").tag(2)
                    Image(systemName: "arrow.right").tag(3)
                }
                .pickerStyle(.segmented)
                Stepper(value: scrollAmount, in: 10...400, step: 10) {
                    LabeledContent("每次滚动", value: LF("%@ 像素", "\(scrollAmount.wrappedValue)"))
                }
            }

        case "media":
            Section {
                Picker("媒体键", selection: Binding(get: { action?.media ?? "play" }, set: { v in edit { $0.media = v } })) {
                    ForEach(Action.mediaNames, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

        case "app":
            Section {
                LabeledContent("App") {
                    HStack(spacing: 8) {
                        if let b = a.bundleID, let icon = model.icon(for: b) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            Text(model.summary(of: a).replacingOccurrences(of: LF("打开 %@", ""), with: ""))
                        }
                        Button(a.bundleID == nil ? L("选择…") : L("更换…")) {
                            if let b = pickApp() { edit { $0.bundleID = b } }
                        }
                    }
                }
            }

        case "shell":
            Section {
                TextField("命令", text: Binding(get: { action?.command ?? "" }, set: { v in edit { $0.command = v } }),
                          prompt: Text("shortcuts run \"我的快捷指令\""))
                    .font(.system(.body, design: .monospaced))
            }

        case "audioOutputs":
            VStack(alignment: .leading, spacing: 6) {
                AudioOutputChecklist()
            }

        case "dialMode":
            Section {
                Picker("波轮", selection: Binding(get: { action?.dial ?? model.layout.leftDial }, set: { v in edit { $0.dial = v } })) {
                    Text("左波轮").tag(model.layout.leftDial)
                    Text("右波轮").tag(model.layout.rightDial)
                }
                .pickerStyle(.segmented)
            }

        default:
            EmptyView()
        }
    }

    private func pickApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    // 滚动方向：0 上 1 下 2 左 3 右
    private var scrollDirection: Binding<Int> {
        Binding(
            get: {
                let dy = action?.dy ?? 0, dx = action?.dx ?? 0
                return dy > 0 ? 0 : dy < 0 ? 1 : dx > 0 ? 2 : 3
            },
            set: { d in setScroll(direction: d, amount: scrollAmount.wrappedValue) }
        )
    }

    private var scrollAmount: Binding<Int> {
        Binding(
            get: { max(abs(action?.dy ?? 0), abs(action?.dx ?? 0), 10) },
            set: { amt in setScroll(direction: scrollDirection.wrappedValue, amount: amt) }
        )
    }

    private func setScroll(direction d: Int, amount: Int) {
        edit { a in
            a.dx = nil; a.dy = nil
            switch d {
            case 0: a.dy = amount
            case 1: a.dy = -amount
            case 2: a.dx = amount
            default: a.dx = -amount
            }
        }
    }
}

private struct GroupHeader: View {
    let title: String
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: open)
    }
}

private struct ItemRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let selected: Bool
    let chevron: Bool
    var open = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.white : .secondary)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 6)
                if let detail {
                    Text(detail).font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary)
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.6))
                } else if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(selected ? Color.white : .primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor : hover ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 点击后按下组合键即可录入；单独按一下修饰键会录成该修饰键本身
struct ShortcutRecorder: View {
    @Binding var key: String?
    @Binding var mods: [String]?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var liveMods: [String] = []
    @State private var peakMods: [String] = []

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 3) {
                if recording {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text(liveMods.isEmpty ? L("按下快捷键…") : KeyMap.modsGlyph(liveMods) + "…")
                        .font(.system(size: 12))
                } else if let k = key {
                    ForEach(Array(KeyMap.keycaps(mods, k).enumerated()), id: \.offset) { _, c in Keycap(text: c) }
                } else {
                    Text("点击录制").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 120, minHeight: 24)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: recording ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        liveMods = []
        peakMods = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if e.type == .flagsChanged {
                let m = KeyMap.mods(from: e.modifierFlags)
                if m.count > peakMods.count { peakMods = m }
                liveMods = m
                if m.isEmpty, peakMods.count == 1 {
                    key = peakMods[0]
                    mods = nil
                    stop()
                }
                return nil
            }
            guard let name = KeyMap.name(for: e.keyCode) else { NSSound.beep(); return nil }
            let m = KeyMap.mods(from: e.modifierFlags)
            key = name
            mods = m.isEmpty ? nil : m
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
        liveMods = []
    }
}
