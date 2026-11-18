import SwiftUI

struct DialsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
        ScrollView { DialsContent() }
        }
    }
}

struct DialsContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
            VStack(alignment: .leading, spacing: 18) {

                HStack(alignment: .top, spacing: 20) {
                    DialColumn(title: L("左波轮"), dial: model.layout.leftDial, target: .leftDial)
                        .frame(maxWidth: .infinity)
                    DialColumn(title: L("右波轮"), dial: model.layout.rightDial, target: .rightDial)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
    }
}

struct DialColumn: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let dial: Int
    let target: PadTarget

    private var inherited: Bool { !model.isDefaultProfile && model.ownDial(dial) == nil }
    private var modes: [DialMode] { model.effectiveDial(dial) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dial.medium")
                    .foregroundStyle(model.flashing.contains(target) ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: model.flashing.contains(target))
                Text(title).font(.headline)
                Spacer()
                if !inherited {
                    Button {
                        var m = modes
                        m.append(DialMode(name: L("新模式"), cw: .scroll(dy: -30), ccw: .scroll(dy: 30), accelerate: true))
                        model.setDial(dial, m)
                    } label: {
                        Label("添加模式", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(modes.count >= 6)
                }
            }

            if inherited {
                HStack {
                    Label("跟随通用设置", systemImage: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("为此 App 自定义") { model.setDial(dial, model.defaultDial(dial)) }
                }
                .font(.callout)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            } else if !model.isDefaultProfile {
                Button("恢复为跟随通用") { model.setDial(dial, nil) }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            ForEach(Array(modes.enumerated()), id: \.offset) { i, _ in
                ModeCard(index: i, dial: dial, editable: !inherited, canDelete: modes.count > 1)
            }
            .opacity(inherited ? 0.55 : 1)
            .disabled(inherited)
        }
    }
}

struct ModeCard: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let dial: Int
    let editable: Bool
    let canDelete: Bool

    private var mode: DialMode? { model.effectiveDial(dial)[safe: index] }

    private func update(_ change: (inout DialMode) -> Void) {
        var m = model.effectiveDial(dial)
        guard m.indices.contains(index) else { return }
        change(&m[index])
        model.setDial(dial, m)
    }

    var body: some View {
        if let mode {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LF("模式 %@", "\(index + 1)"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if editable {
                        Menu {
                            Button("上移") { move(-1) }.disabled(index == 0)
                            Button("下移") { move(1) }.disabled(index == model.effectiveDial(dial).count - 1)
                            Divider()
                            Button("删除", role: .destructive) {
                                var m = model.effectiveDial(dial); m.remove(at: index); model.setDial(dial, m)
                            }
                            .disabled(!canDelete)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                TextField("模式名称", text: Binding(get: { L(mode.name) }, set: { v in update { $0.name = v } }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                Divider()
                DirectionRow(label: L("顺时针"), symbol: "arrow.clockwise", action: mode.cw) { a in update { $0.cw = a } }
                DirectionRow(label: L("逆时针"), symbol: "arrow.counterclockwise", action: mode.ccw) { a in update { $0.ccw = a } }
                Toggle(isOn: Binding(get: { mode.accelerate ?? false }, set: { v in update { $0.accelerate = v ? true : nil } })) {
                    Label("加速", systemImage: "hare")
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.callout)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )
        }
    }

    private func move(_ d: Int) {
        var m = model.effectiveDial(dial)
        let j = index + d
        guard m.indices.contains(j) else { return }
        m.swapAt(index, j)
        model.setDial(dial, m)
    }
}

struct DirectionRow: View {
    @EnvironmentObject var model: AppModel
    let label: String
    let symbol: String
    let action: Action
    let onChange: (Action) -> Void
    @State private var editing = false

    var body: some View {
        HStack {
            Label(label, systemImage: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Button { editing = true } label: {
                HStack(spacing: 4) {
                    Text(model.title(of: action)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $editing, arrowEdge: .trailing) {
                ActionEditor(
                    title: label,
                    action: Binding(get: { action }, set: { onChange($0 ?? .disabled) })
                )
            }
        }
        .font(.callout)
    }
}
