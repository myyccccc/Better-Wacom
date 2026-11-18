import Foundation

/// 取本地化文案（键为简体中文原文，翻译在 Resources/<lang>.lproj/Localizable.strings）
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// 带参数的本地化文案，参数统一用 %@
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

/// App 内可选的界面语言：代码 + 该语言自己的名称（不用国旗）
enum AppLanguage {
    static let all: [(String, String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어"),
        ("es", "Español (España)"), ("es-419", "Español (Latinoamérica)"), ("fr", "Français"), ("de", "Deutsch"),
        ("pt-BR", "Português (Brasil)"), ("pt-PT", "Português (Portugal)"), ("it", "Italiano"), ("nl", "Nederlands"),
        ("ru", "Русский"), ("ar", "العربية"),
    ]

    /// 空字符串 = 跟随系统
    static var current: String {
        get { (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]).flatMap { UserDefaults.standard.object(forKey: "BWLanguage") != nil ? $0.first : nil } ?? "" }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                UserDefaults.standard.removeObject(forKey: "BWLanguage")
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                UserDefaults.standard.set(newValue, forKey: "BWLanguage")
            }
        }
    }

    /// 重新启动自己，让新语言生效
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", url.path]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
    }
}
