// 文件职责：验证应用显示名解析（AppDisplayName）与 bundle 本地化名字收集（BundleLocalization）：plist key 的优先级与平台后缀、语言代码的展开与别名、loctable/strings/no.lproj 的读取顺序。
// 分层：测试 harness（无 XCTest，直接用 `swiftc` 编译）；在临时目录里自造 bundle，累计失败后以退出码 1 结束。
import Foundation

/// 应用名解析测试 harness 的入口类型。
@main
struct AppNameTest {
    /// harness 入口：在临时目录造出各种 bundle 形态，逐项断言并向 stdout 打印 PASS/FAIL。
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("gearmac-app-name-\(UUID().uuidString)")

        var failures = 0

        /// 断言辅助：成立打印 PASS，否则打印 FAIL 并累计失败数。
        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        /// 在磁盘上造一个真实的 bundle：`installedAppName` 会像扫描时那样读取 plist。
        func makeApp(_ fileName: String, info: [String: Any]) -> Bundle? {
            let url = root.appendingPathComponent(fileName)
            let contents = url.appendingPathComponent("Contents")
            try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
            return Bundle(url: url)
        }

        check(
            "a blank display name is not a name",
            AppDisplayName.named("") == nil && AppDisplayName.named("   ") == nil
                && AppDisplayName.named("\n\t") == nil)
        check("a missing value is not a name", AppDisplayName.named(nil) == nil)
        check("a non-string value is not a name", AppDisplayName.named(42) == nil)
        check("a name is trimmed", AppDisplayName.named("  Paw  ") == "Paw")

        check(
            "a blank display name falls back to CFBundleName",
            AppDisplayName.inInfo(["CFBundleDisplayName": "", "CFBundleName": "RapidAPI"])
                == "RapidAPI")
        check(
            "a present display name still wins",
            AppDisplayName.inInfo(["CFBundleDisplayName": "Shown", "CFBundleName": "Internal"])
                == "Shown")
        check(
            "an info dictionary naming nothing yields nil",
            AppDisplayName.inInfo(["CFBundleDisplayName": " ", "CFBundleName": ""]) == nil)
        // Image Playground 的 loctable 两个 key 都带，而 CFBundle 会读带平台后缀的那一个。
        check(
            "the macOS variant of a key wins over the bare key",
            AppDisplayName.inInfo([
                "CFBundleDisplayName-macos": "Image Playground",
                "CFBundleDisplayName": "Playground", "CFBundleName": "Image Playground"
            ]) == "Image Playground")
        check(
            "a blank macOS variant falls through to the bare key",
            AppDisplayName.inInfo([
                "CFBundleDisplayName-macos": "", "CFBundleDisplayName": "Playground"
            ]) == "Playground")
        check(
            "a macOS variant of CFBundleName still loses to a real display name",
            AppDisplayName.inInfo([
                "CFBundleDisplayName": "Shown", "CFBundleName-macos": "Internal"
            ]) == "Shown")

        // RapidAPI 4.5.5 正是这样：显示名为空白、`CFBundleName` 真实存在，还带着 Paw 的旧 bundle id。
        let rapidAPI = makeApp(
            "RapidAPI.app",
            info: [
                "CFBundleDisplayName": "", "CFBundleName": "RapidAPI",
                "CFBundleIdentifier": "com.luckymarmot.Paw"
            ])
        check(
            "a bundle with a blank display name is named by CFBundleName",
            rapidAPI?.installedAppName == "RapidAPI")

        let unnamed = makeApp("Mystery.app", info: ["CFBundleIdentifier": "com.example.mystery"])
        check(
            "a bundle naming itself nowhere falls back to its filename",
            unnamed?.installedAppName == "Mystery")

        let blankBoth = makeApp(
            "Ghost.app",
            info: [
                "CFBundleDisplayName": "  ", "CFBundleName": "",
                "CFBundleIdentifier": "com.example.ghost"
            ])
        check(
            "two blank keys still fall back to the filename",
            blankBoth?.installedAppName == "Ghost")

        /// 把 Mac 的偏好语言列表展开成 Apple 资源查找用的候选代码序列。
        func codes(_ preferred: [String]) -> [String] {
            BundleLocalization.indexedLanguages(preferred)
        }
        check(
            "a Simplified Chinese Mac looks up the zh_CN Apple actually keys by",
            codes(["zh-Hans-CN"]).contains("zh_CN"))
        check(
            "a script-bearing tag also reads the zh-Hans folder most apps ship, before its region",
            codes(["zh-Hans-US"])
                == ["zh-Hans-US", "zh_Hans_US", "zh-Hans", "zh_Hans", "zh-US", "zh_US", "zh", "en"])
        check(
            "a script-only tag maximizes to reach the same key",
            codes(["zh-Hans"]).contains("zh_CN"))
        check(
            "Traditional Chinese resolves to its own region, not the mainland's",
            codes(["zh-Hant-TW"]).contains("zh_TW") && !codes(["zh-Hant-TW"]).contains("zh_CN"))
        check(
            "English stays last so a Chinese reader still types \"Calendar\"",
            codes(["zh-Hans-CN"]).last == "en")
        check(
            "Portuguese keeps its exact, underscore and bare-language forms",
            codes(["pt-BR"]) == ["pt-BR", "pt_BR", "pt", "en"])
        check(
            "Bokmål reads Apple's no key after an explicit nb localization",
            codes(["nb-NO"]) == ["nb-NO", "nb_NO", "nb", "no", "en"])
        check(
            "a bare Bokmål preference also reaches no",
            codes(["nb"]) == ["nb", "no", "en"])
        check(
            "repeated Norwegian preferences never repeat a resource lookup",
            codes(["nb-NO", "nb", "no"]) == ["nb-NO", "nb_NO", "nb", "no", "en"])
        check(
            "Nynorsk does not acquire the Bokmål resource alias",
            codes(["nn-NO"]) == ["nn-NO", "nn_NO", "nn", "en"])

        /// 走完整条路径：只在 loctable 里有翻译的 bundle，按扫描时的读法读取。
        func makeLocalizedApp(_ fileName: String, table: [String: Any]) -> URL {
            let url = root.appendingPathComponent(fileName)
            let resources = url.appendingPathComponent("Contents/Resources")
            try? fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(
                fromPropertyList: table, format: .xml, options: 0)
            try? data?.write(to: resources.appendingPathComponent("InfoPlist.loctable"))
            return url
        }

        /// 扫描自身的调用方式：应用没有翻译名时，它的名字就是它在磁盘上的文件名。
        func names(_ url: URL, _ preferred: [String], region: String? = "en") -> [String] {
            BundleLocalization.names(
                for: url, base: url.deletingPathExtension().lastPathComponent,
                developmentRegion: region, languages: codes(preferred))
        }

        let calculator = makeLocalizedApp(
            "Calculator.app",
            table: [
                "no": ["CFBundleDisplayName": "Kalkulator"],
                "de": ["CFBundleDisplayName": "Rechner"]
            ])
        check(
            "a Bokmål Mac displays the no translation and keeps English searchable",
            names(calculator, ["nb-NO"]) == ["Kalkulator", "Calculator"])
        check(
            "a more preferred language still outranks Norwegian",
            names(calculator, ["de-DE", "nb-NO"]) == ["Rechner", "Kalkulator", "Calculator"])
        check(
            "an English Mac does not index Norwegian translations",
            names(calculator, ["en-US"]) == ["Calculator"])
        check(
            "a no translation replaces the base name of a Norwegian-developed bundle",
            names(calculator, ["nb-NO"], region: "no") == ["Kalkulator"]
                && names(calculator, ["nb-NO"], region: "nb") == ["Kalkulator"])
        check(
            "a no preference also recognizes its canonical development language",
            names(calculator, ["no"], region: "no") == ["Kalkulator"])

        let norwegianBase = makeLocalizedApp(
            "Notater.app", table: ["de": ["CFBundleName": "Notizen"]])
        check(
            "an untranslated Norwegian base name stays ahead of less preferred languages",
            names(norwegianBase, ["nb-NO", "de-DE"], region: "no") == ["Notater", "Notizen"])
        check(
            "a translated earlier language still outranks the Norwegian base name",
            names(norwegianBase, ["de-DE", "nb-NO"], region: "nb") == ["Notizen", "Notater"])

        let norwegianStrings = root.appendingPathComponent("NorwegianStrings.app")
        let no = norwegianStrings.appendingPathComponent("Contents/Resources/no.lproj")
        try? fm.createDirectory(at: no, withIntermediateDirectories: true)
        try? Data("\"CFBundleDisplayName\" = \"Norsk navn\";\n".utf8)
            .write(to: no.appendingPathComponent("InfoPlist.strings"))
        check(
            "the Norwegian alias also reads no.lproj strings",
            names(norwegianStrings, ["nb-NO"]) == ["Norsk navn", "NorwegianStrings"])

        let nb = calculator.appendingPathComponent("Contents/Resources/nb.lproj")
        try? fm.createDirectory(at: nb, withIntermediateDirectories: true)
        try? Data("\"CFBundleDisplayName\" = \"Bokmål-kalkulator\";\n".utf8)
            .write(to: nb.appendingPathComponent("InfoPlist.strings"))
        check(
            "an explicit nb folder wins over Apple's no table",
            names(calculator, ["nb-NO"]) == ["Bokmål-kalkulator", "Kalkulator", "Calculator"])
        check(
            "an explicit nb translation suppresses the development base across the alias",
            names(calculator, ["nb-NO"], region: "no") == ["Bokmål-kalkulator", "Kalkulator"])
        check(
            "development fallback waits for nb even when no was preferred first",
            names(calculator, ["no", "nb"], region: "nb") == ["Kalkulator", "Bokmål-kalkulator"])

        let bokmalOnly = makeLocalizedApp(
            "BokmalOnly.app", table: ["nb": ["CFBundleName": "Bokmålsnavn"]])
        check(
            "a missing no alias never reinstates a base name replaced under nb",
            names(bokmalOnly, ["nb-NO"], region: "no") == ["Bokmålsnavn"])
        check(
            "an empty no lookup waits for a later nb translation before inserting the base",
            names(bokmalOnly, ["no", "nb"], region: "nb") == ["Bokmålsnavn"])

        let monitor = makeLocalizedApp(
            "Activity Monitor.app",
            table: [
                "zh_CN": ["CFBundleName": "活动监视器"],
                "zh_TW": ["CFBundleName": "活動監視器"],
                "en": ["CFBundleName": "Activity Monitor"]
            ])
        check(
            "a loctable app is found by its Chinese name, English still indexed",
            names(monitor, ["zh-Hans-CN"]) == ["活动监视器", "Activity Monitor"])
        check(
            "an English Mac indexes only the English name",
            names(monitor, ["en-US"]) == ["Activity Monitor"])

        // 微信只在 `zh-Hans.lproj` 里给自己命名，而偏好 `zh-Hans-US` 的 Mac 以前永远走不到这个目录。
        let weChat = root.appendingPathComponent("WeChat.app")
        let hans = weChat.appendingPathComponent("Contents/Resources/zh-Hans.lproj")
        try? fm.createDirectory(at: hans, withIntermediateDirectories: true)
        try? Data("\"CFBundleDisplayName\" = \"微信\";\n".utf8)
            .write(to: hans.appendingPathComponent("InfoPlist.strings"))
        check(
            "a strings-only app is found by the name in its zh-Hans folder",
            names(weChat, ["zh-Hans-US", "en-US"]) == ["微信", "WeChat"])

        // Tips.app 带了除自己以外所有语言：`en` 正是 Apple 的 loctable 里唯一省略的 key。
        let tips = makeLocalizedApp(
            "Tips.app", table: ["ru": ["CFBundleName": "Советы"], "de": ["CFBundleName": "Tipps"]])
        check(
            "an untranslated name outranks a language the user reads less well",
            names(tips, ["en-US", "ru-RU"]) == ["Tips", "Советы"])
        check(
            "the language a Mac actually prefers still wins over the untranslated name",
            names(tips, ["ru-RU"]) == ["Советы", "Tips"])
        check(
            "a language nobody asked for is never indexed",
            !names(tips, ["en-US", "ru-RU"]).contains("Tipps"))

        // Safari 的 `CFBundleDevelopmentRegion` 至今写作 "English"，而不是 "en"。
        check(
            "a pre-BCP-47 development region names the same language",
            names(tips, ["en-US", "ru-RU"], region: "English") == ["Tips", "Советы"])
        check(
            "a bundle claiming no region leaves its name last, still searchable",
            names(tips, ["en-US", "ru-RU"], region: nil) == ["Советы", "Tips"])

        // Print Center 只带 `en_GB` 而没有 `en`；文件名本来就是它已有的英文名。
        let printCenter = makeLocalizedApp(
            "Print Center.app", table: ["en_GB": ["CFBundleName": "Print Centre"]])
        check(
            "a regional spelling never relabels the app the file name already names",
            names(printCenter, ["en-US"]).first == "Print Center")

        // VoiceMemos.app 在磁盘上任何地方都没给自己命名，因此 `en` 承载了用户看到的那个名字。
        let memos = makeLocalizedApp(
            "VoiceMemos.app",
            table: ["en": ["CFBundleName": "Voice Memos"], "ru": ["CFBundleName": "Диктофон"]])
        check(
            "a translated English name replaces the file name it was written for",
            names(memos, ["en-US", "ru-RU"]) == ["Voice Memos", "Диктофон"])

        let trackpad = makeLocalizedApp(
            "TrackpadExtension.appex", table: ["en": ["CFBundleDisplayName": "Trackpad"]])
        check(
            "an identifier its own table renames is never indexed",
            names(trackpad, ["en-US", "ru-RU"]) == ["Trackpad"])

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
