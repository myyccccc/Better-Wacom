import SwiftUI

/// 开发用：BetterWacom --snapshot <输出.png> 把界面离屏渲染成图片
enum Snapshot {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let j = args.firstIndex(of: "--shoot"), j + 1 < args.count { shoot(args[j + 1]); exit(0) }
        if let j = args.firstIndex(of: "--shoot-audio"), j + 1 < args.count {
            // 动作面板里「切换声音输出」展开后的设备勾选列表
            let model = AppModel.shared
            model.store.load()
            let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 760),
                               styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: ActionEditor(action: .constant(Action(type: "audioOutputs", label: L("切换声音输出"))),
                                                            allowDialMode: true)
                .frame(width: 380, height: 760)
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(model))
            win.contentView = host
            win.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l\(win.windowNumber)", args[j + 1]]
            try? p.run(); p.waitUntilExit()
            exit(0)
        }
        if let k = args.firstIndex(of: "--test-key"), k + 1 < args.count {
            // 测试：1 秒后发出和波轮一样的按键（如 opt+up）
            let parts = args[k + 1].split(separator: "+").map(String.init)
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            let n = Int(args.dropFirst(k + 2).first ?? "1") ?? 1
            ActionRunner.pressRepeated(Action.key(parts.last!, Array(parts.dropLast())), count: n)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1 + Double(n) * 0.02))
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            exit(0)
        }
        if args.contains("--test-volume") {
            // 模拟右波轮快速转动：先 +5 格、再 −5 格，打印前后音量
            ActionRunner.trusted = AXIsProcessTrusted()
            let v0 = SystemVolume.volume ?? -1
            for _ in 0..<5 { ActionRunner.changeVolume(by: 0.02); RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let v1 = SystemVolume.volume ?? -1
            for _ in 0..<5 { ActionRunner.changeVolume(by: -0.02); RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let v2 = SystemVolume.volume ?? -1
            print("trusted=\(ActionRunner.trusted) before=\(v0) up=\(v1) down=\(v2)")
            exit(0)
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        KeysStage.snapshot = true
        let model = AppModel.shared
        model.store.load()
        for (name, page) in [("keys", AnyView(KeysStage(editing: .constant(nil), hover: .constant(nil)))), ("pen", AnyView(PenPage())), ("dials", AnyView(VStack(spacing: 0) { DialsContent(); Spacer() }))] {
            for scheme in [ColorScheme.dark, .light] {
                let view = page
                    .environmentObject(model)
                    .frame(width: 960, height: 640)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                let r = ImageRenderer(content: view)
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: args[i + 1] + "-\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        exit(0)
    }

    /// 用真实窗口逐页截图（包含系统控件）
    @MainActor
    static func shoot(_ prefix: String) {
        KeysStage.snapshot = true
        UserDefaults.standard.set(true, forKey: "welcomeShown")
        let model = AppModel.shared
        model.store.load()
        // --profile <Bundle ID>：拍某个 App 的配置（默认拍「通用」）
        let args = CommandLine.arguments
        if let k = args.firstIndex(of: "--profile"), k + 1 < args.count { model.selectedProfile = args[k + 1] }
        func wait(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
        func save(_ v: NSView, _ name: String) {
            guard let w = v.window else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l\(w.windowNumber)", "\(prefix)-\(name).png"]
            try? p.run(); p.waitUntilExit()
        }
        for (appearance, tag) in [(NSAppearance.Name.darkAqua, "dark"), (.aqua, "light")] {
            NSApp.appearance = NSAppearance(named: appearance)
            let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1120, height: 740),
                               styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            win.titlebarAppearsTransparent = true
            let host = NSHostingView(rootView: SettingsView().environmentObject(model))
            win.contentView = host
            win.orderFrontRegardless()
            let saved = model.store.config.mapping
            for page in Page.allCases {
                model.page = page
                if page == .mapping {
                    model.setMapping { $0.enabled = true; $0.area = [0.08, 0.12, 0.62, 0.7]; $0.forceProportions = true }
                } else if saved != model.store.config.mapping {
                    model.store.mutate { $0.mapping = saved }
                }
                wait(1.6)
                save(host, "\(page.rawValue)-\(tag)")
            }
            // 按键页 + 展开的动作面板
            ExpressKeysPage.initialEditing = .leftToggle
            model.page = .pen; wait(0.3); model.page = .keys
            wait(1.6)
            save(host, "panel-\(tag)")
            ExpressKeysPage.initialEditing = nil
            win.close()

            // 动作面板（第一级列表 + 第二级快捷键设置）
            let panelWin = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 560),
                                    styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            var a: Action? = .key("z", ["cmd"], "撤销")
            let editor = ButtonEditor(button: model.layout.leftKeys[0], positionName: "左环 · 上")
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(model)
            _ = a; a = nil
            let ph = NSHostingView(rootView: editor)
            panelWin.contentView = ph
            panelWin.setContentSize(ph.fittingSize)
            panelWin.orderFrontRegardless()
            wait(1.2)
            save(ph, "actions-\(tag)")
            panelWin.close()
        }
    }
}
