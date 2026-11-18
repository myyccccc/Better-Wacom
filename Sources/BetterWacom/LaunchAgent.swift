import AppKit
import Darwin

/// 开机（登录）自启动 + 意外退出自动重启。
/// 用 ~/Library/LaunchAgents 下的 launchd 配置：
/// - RunAtLoad：登录时自动打开
/// - KeepAlive.SuccessfulExit = false：崩溃或被杀掉会自动重新打开；从菜单里「退出」（正常退出）则不会
enum LaunchAgent {
    static let label = "com.denis.BetterWacom"
    /// 是否由 launchd 拉起（开机自启动 / 崩溃后重启 / 重新打包后重启）
    static let launchedByLaunchd = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static let showSettingsNote = Notification.Name("com.denis.BetterWacom.showSettings")

    /// 同一时间只保留一个实例：已有实例在跑，就请它显示设置窗口，然后退出自己。
    /// 按可执行文件路径找（由 launchd 拉起的实例不一定登记在 LaunchServices 里）
    static func ensureSingleInstance() {
        guard let exe = Bundle.main.executablePath else { return }
        let me = getpid()
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var path = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 && pid != me {
            if proc_pidpath(pid, &path, UInt32(path.count)) > 0, String(cString: path) == exe {
                if !launchedByLaunchd {
                    DistributedNotificationCenter.default().postNotificationName(showSettingsNote, object: nil,
                                                                                 userInfo: nil, deliverImmediately: true)
                }
                exit(0)
            }
        }
    }

    /// 开机自动启动开关。不用 bootout（会把正在运行的实例一起结束），用 enable / disable 决定下次登录是否启动
    static func setLaunchAtLogin(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Preferences.loginKey)
        DispatchQueue.global(qos: .utility).async {
            launchctl([on ? "enable" : "disable", "gui/\(getuid())/\(label)"])
            if on { install() }
        }
    }

    static func install() {
        guard let exe = Bundle.main.executablePath, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 5,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let fm = FileManager.default
        let old = (try? Data(contentsOf: plistURL)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? NSDictionary
        if old != (plist as NSDictionary) {
            try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL)
            }
            // 配置变了：重新登记（不会影响当前这个实例）
            launchctl(["bootout", "gui/\(getuid())/\(label)"])
        }
        launchctl([Preferences.launchAtLogin ? "enable" : "disable", "gui/\(getuid())/\(label)"])
        if Preferences.launchAtLogin, !isLoaded { launchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) }
    }

    private static var isLoaded: Bool { launchctl(["print", "gui/\(getuid())/\(label)"]) == 0 }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
