import SwiftUI

/// 设置面板（右上角齿轮）
struct SettingsPanel: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("showDockIcon") private var showDockIcon = false
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("外观", selection: $model.appearance) {
                        Text("自动").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                    LanguageRow()
                }

                Section("运行") {
                    Toggle("开机自动启动", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = $0; LaunchAgent.setLaunchAtLogin($0) }))
                    Toggle("在菜单栏显示图标", isOn: $showMenuBarIcon)
                    Toggle("在 Dock 显示图标", isOn: Binding(
                        get: { showDockIcon },
                        set: { showDockIcon = $0; Preferences.applyDockIcon() }))
                    LabeledContent("关闭窗口后继续在后台运行") {
                        Button("退出 Better Wacom") { model.engine.reset(wait: true); NSApp.terminate(nil) }
                    }
                }

                Section("设备") {
                    LabeledContent("按键位置") {
                        Button(model.config.layout == nil ? L("开始校准") : L("重新校准")) { model.showCalibration = true }
                            .disabled(!model.connected)
                    }
                    Toggle("波轮方向反转", isOn: Binding(
                        get: { model.config.invertDials ?? false },
                        set: { v in model.store.mutate { $0.invertDials = v } }))
                    Toggle("暂停所有自定义", isOn: $model.paused)
                }

                PresetFavoritesSection()
                AudioOutputFavoritesSection()

                Section("权限") {
                    LabeledContent("辅助功能") {
                        if model.trusted {
                            Label("已开启", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("去开启") { openAccessibilitySettings() }
                        }
                    }
                }

                Section {
                    HStack {
                        Button("在访达中显示配置") { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.url]) }
                        Spacer()
                        Button("恢复默认按键", role: .destructive) { confirmReset = true }
                    }
                } footer: {
                    Text("Better Wacom 1.0").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 560)
        .confirmationDialog("所有按键和波轮恢复为默认？", isPresented: $confirmReset) {
            Button("恢复默认", role: .destructive) { model.store.resetToDefault(); model.engine.reset() }
        }
    }
}

/// 账户：本机用户 + iCloud 云盘同步
struct AccountPanel: View {
    @EnvironmentObject var model: AppModel

    private var initials: String {
        let n = NSFullUserName()
        return String(n.prefix(1)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .overlay(Text(initials).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSFullUserName()).font(.headline)
                    Text(model.cloudAvailable ? L("iCloud 云盘") : L("未开启 iCloud 云盘")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("自动同步设置", isOn: $model.cloudAuto)
                .toggleStyle(.switch)
                .disabled(!model.cloudAvailable)
            HStack {
                Button("上传") { model.uploadToCloud() }
                Button("从云端恢复") { model.restoreFromCloud() }
            }
            .disabled(!model.cloudAvailable)
            if let d = model.cloudLast {
                Text(LF("上次同步 %@", d.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 280)
    }
}

/// 按键位置校准（从设置或启动通知进入）
struct CalibrationSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            PadCanvas(pulse: model.calibrationTarget)
                .frame(maxWidth: 720)

            if let c = model.calibration {
                let steps = AppModel.calibrationSteps
                VStack(spacing: 10) {
                    Text(steps[safe: c.step]?.0 ?? "")
                        .font(.system(size: 17, weight: .medium))
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: c.step)
                    ProgressView(value: Double(c.step), total: Double(steps.count))
                        .frame(width: 260)
                }
            } else if !model.calibrationDone {
                Button("开始") { model.startCalibration() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.connected)
            }

            HStack {
                Spacer()
                Button(model.calibration == nil ? L("关闭") : L("取消")) {
                    model.cancelCalibration()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 780)
        .overlay { ToastView() }
        .onAppear { model.calibrationDone = false; if model.connected { model.startCalibration() } }
        .onDisappear { if model.calibration != nil { model.cancelCalibration() } }
    }
}

/// 语言：跟随系统或手动选择，切换后重新启动生效
struct LanguageRow: View {
    @State private var lang = AppLanguage.current
    @State private var changed = false

    var body: some View {
        Picker("语言", selection: $lang) {
            Text("跟随系统").tag("")
            ForEach(AppLanguage.all, id: \.0) { code, name in Text(verbatim: name).tag(code) }
        }
        .onChange(of: lang) { _, v in AppLanguage.current = v; changed = true }
        if changed {
            Button("重新启动以应用语言") { AppLanguage.relaunch() }
        }
    }
}

/// 设置 → 色彩模式：勾选按住「色彩模式切换」键时可选的显示器预设
struct PresetFavoritesSection: View {
    @EnvironmentObject var model: AppModel
    @State private var presets: [DisplayPresets.Preset] = []

    private var chosen: Set<String> { Set(model.config.displayPresets ?? DisplayPresets.defaultFavorites) }

    var body: some View {
        Section {
            if presets.isEmpty {
                Text("这台 Mac 连接的显示器没有色彩预设").foregroundStyle(.secondary)
            }
            ForEach(presets, id: \.self) { p in
                Toggle(p.name, isOn: Binding(
                    get: { chosen.contains(p.name) },
                    set: { on in
                        var c = chosen
                        if on { c.insert(p.name) } else { c.remove(p.name) }
                        // 保持系统列表顺序
                        let ordered = presets.map(\.name).filter { c.contains($0) }
                        model.store.mutate { $0.displayPresets = ordered }
                    }))
            }
        } header: {
            Text("色彩模式")
        } footer: {
            Text("按住设为「色彩模式切换」的按键，转动任一波轮选择，松开即切换").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { presets = DisplayPresets.all() }
    }
}

/// 设置里的「声音输出」：勾选长按音量键时列出哪些输出设备
struct AudioOutputFavoritesSection: View {
    var body: some View {
        Section {
            AudioOutputChecklist()
        } header: {
            Text("声音输出")
        } footer: {
            Text("长按设为「切换声音输出」的按键（默认是右环上下键），转动任一波轮选择，松开即切换。蓝牙耳机要先连上才会出现在列表里").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 声音输出设备勾选列表（没连接的已勾选设备也保留显示）。设置面板和动作编辑器共用
struct AudioOutputChecklist: View {
    @EnvironmentObject var model: AppModel
    @State private var connected: [String] = []

    /// 当前勾选的名称：用户没选过时按默认规则（有线耳机、Beats）
    private var chosen: [String] {
        model.config.audioOutputs ?? connected.filter(AudioOutputs.isDefaultFavorite)
    }

    /// 连着的设备 + 已勾选但现在没连的设备
    private var rows: [String] { connected + chosen.filter { !connected.contains($0) } }

    var body: some View {
        ForEach(rows, id: \.self) { name in
            Toggle(isOn: Binding(
                get: { chosen.contains(name) },
                set: { on in
                    var c = chosen
                    if on { if !c.contains(name) { c.append(name) } } else { c.removeAll { $0 == name } }
                    let ordered = rows.filter { c.contains($0) }
                    model.store.mutate { $0.audioOutputs = ordered }
                })) {
                if connected.contains(name) {
                    Text(name)
                } else {
                    Text(name) + Text("  ") + Text(L("未连接")).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { connected = AudioOutputs.all().map(\.name) }
    }
}
