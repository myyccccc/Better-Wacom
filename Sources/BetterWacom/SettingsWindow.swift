import AppKit
import SwiftUI

/// 设置窗口由 AppKit 直接管理：不管软件是开机在后台启动、还是从访达打开，都能随时打开。
/// 关闭窗口只是隐藏，软件继续在后台运行。
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        let w = window ?? make()
        window = w
        Preferences.applyDockIcon(windowOpen: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView()
            .environmentObject(AppModel.shared)
            .frame(minWidth: 760, minHeight: 500))
        // 让 SettingsView 里的 .toolbar 修饰符照常生效
        host.sceneBridgingOptions = [.toolbars, .title]
        let w = NSWindow(contentViewController: host)
        w.title = "Better Wacom"
        w.identifier = NSUserInterfaceItemIdentifier("settings")
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // 透明标题栏：顶部一行（型号、账户、设置）画在标题栏位置，和红绿灯同一行
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.toolbarStyle = .unified
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setContentSize(NSSize(width: 960, height: 600))
        w.center()
        w.setFrameAutosaveName("BetterWacomSettings")
        return w
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { Preferences.applyDockIcon(windowOpen: false) }
    }

    var isOpen: Bool { window?.isVisible == true }
}

/// 后台运行相关的偏好（设置面板里可改）
enum Preferences {
    static let menuBarKey = "showMenuBarIcon"
    static let dockKey = "showDockIcon"
    static let loginKey = "launchAtLogin"

    static var showDockIcon: Bool { UserDefaults.standard.bool(forKey: dockKey) }
    static var launchAtLogin: Bool { UserDefaults.standard.object(forKey: loginKey) as? Bool ?? true }

    /// Dock 图标：用户打开了「在 Dock 显示图标」才显示（窗口开着时也不强行显示）
    static func applyDockIcon(windowOpen: Bool = SettingsWindow.shared.isOpen) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if windowOpen { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}
