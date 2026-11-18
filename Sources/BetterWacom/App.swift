import SwiftUI

@main
struct BetterWacomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // 不用 @StateObject 观察 AppModel：按键 / 波轮会频繁改它的状态，App 层每次都重算所有场景，
    // 加上菜单栏图标的 isInserted 绑定会陷入无限刷新而崩溃。界面状态由各个 View 自己观察。
    private let model = AppModel.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        // 用户按住 ⌘ 把图标拖出菜单栏时只隐藏图标，软件继续运行（不绑定的话 SwiftUI 会直接退出整个 App）
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuContent().environmentObject(model)
        } label: {
            MenuBarLabel().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshot.runIfRequested()
        LaunchAgent.ensureSingleInstance()
        AppModel.shared.start()
        DispatchQueue.global(qos: .utility).async { LaunchAgent.install() }
        // 在后台运行；Dock 图标按设置决定（默认不显示）。关掉窗口也不退出
        Preferences.applyDockIcon(windowOpen: false)
        // 开机 / 后台启动（由 launchd 拉起）时不弹窗口；手动打开时显示设置窗口
        if !LaunchAgent.launchedByLaunchd { SettingsWindow.shared.show() }
        // 另一个实例（例如在访达里又打开了一次）请求显示设置窗口
        DistributedNotificationCenter.default().addObserver(forName: LaunchAgent.showSettingsNote, object: nil, queue: .main) { _ in
            SettingsWindow.shared.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 菜单栏图标隐藏后，在 Finder / 启动台里再次打开 App：弹出设置窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Image(nsImage: Logo.menuBarImage)
            .opacity(model.paused ? 0.4 : 1)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("launchAtLogin") private var launchAtLogin = true

    var body: some View {
        Text(model.connected ? L("已连接 Intuos Pro M") : L("未检测到数位板"))
        if !model.trusted {
            Button("⚠️ 需要辅助功能权限…") { openAccessibilitySettings() }
        }
        Divider()
        Toggle("暂停", isOn: $model.paused)
            .keyboardShortcut("p")
        Toggle("波轮方向反转", isOn: Binding(
            get: { model.config.invertDials ?? false },
            set: { v in model.store.mutate { $0.invertDials = v } }))
        Divider()
        // 菜单打开时才读取，列表总是最新的
        let presets = DisplayPresets.all()
        if !presets.isEmpty {
            let active = DisplayPresets.activeName
            Menu("色彩模式") {
                ForEach(presets, id: \.self) { p in
                    Toggle(p.name, isOn: Binding(get: { p.name == active }, set: { _ in DisplayPresets.apply(p.name) }))
                }
            }
        }
        let outputs = AudioOutputs.all()
        if !outputs.isEmpty {
            let current = AudioOutputs.currentName
            Menu("声音输出") {
                ForEach(outputs, id: \.self) { d in
                    Toggle(d.name, isOn: Binding(get: { d.name == current }, set: { _ in AudioOutputs.apply(d.name) }))
                }
            }
        }
        Divider()
        Toggle("开机自动启动", isOn: Binding(
            get: { launchAtLogin },
            set: { launchAtLogin = $0; LaunchAgent.setLaunchAtLogin($0) }))
        Button("打开设置…") { SettingsWindow.shared.show() }
            .keyboardShortcut(",")
        Divider()
        Button("退出 Better Wacom") { model.engine.reset(wait: true); NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}
