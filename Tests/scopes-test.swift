// 文件职责：SearchScopes（应用搜索范围枚举与路径规范化）的独立测试 harness，验证 .app 扫描深度、嵌套/嵌入应用、版本排序、范围顺序与去重，以及波浪号展开与缩写。
// 分层：测试 harness；在临时目录内构造目录树，不触碰真实 /Applications。
import Foundation

/// 独立运行的测试入口：逐项断言后以失败数决定退出码。
@main
struct ScopesTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("gearmac-scopes-\(UUID().uuidString)")

        var failures = 0

        /// 断言：条件为真则打印 PASS，否则打印 FAIL 并计数。
        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        /// 确保目录存在（必要时创建中间目录）。
        func makeDir(_ url: URL) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        /// 构造一个带 Info.plist 的假 .app bundle，可指定版本号。
        func makeApp(_ url: URL, version: String) {
            let contents = url.appendingPathComponent("Contents")
            makeDir(contents)
            let plist = ["CFBundleIdentifier": "com.example.app", "CFBundleShortVersionString": version]
            let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
        }

        // 两个直接子应用、一个非 app 文件、一个隐藏应用、一个嵌套应用、一个两层深的应用。
        let apps = root.appendingPathComponent("Apps")
        makeDir(apps.appendingPathComponent("Alpha.app"))
        makeDir(apps.appendingPathComponent("Beta.app"))
        makeDir(apps.appendingPathComponent("Notes.txt"))
        makeDir(apps.appendingPathComponent(".Hidden.app"))
        let vendor = apps.appendingPathComponent("Vendor")
        makeDir(vendor.appendingPathComponent("Nested.app"))
        let deep = vendor.appendingPathComponent("Deeper")
        makeDir(deep.appendingPathComponent("TooDeep.app"))

        let found = SearchScopes.appBundles(in: [apps.path]).map(\.lastPathComponent)
        check(
            "direct and one-level-nested .app children are indexed",
            Set(found) == ["Alpha.app", "Beta.app", "Nested.app"])
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("bundles nested two levels deep are not indexed", !found.contains("TooDeep.app"))
        check(
            "a deeply nested folder works as its own scope",
            SearchScopes.appBundles(in: [deep.path]).map(\.lastPathComponent) == ["TooDeep.app"])

        // 范围可以是单个 bundle：Finder 就是这样作为默认范围提供的。
        check(
            "an .app scope is indexed directly",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Alpha.app").path])
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Gone.app").path]).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            SearchScopes.appBundles(in: [root.appendingPathComponent("Nope").path, deep.path])
                .map(\.lastPathComponent) == ["TooDeep.app"])

        // Xcode 把 Instruments 和 Simulator 放在自己的 bundle 内部。
        let tools = root.appendingPathComponent("Tools")
        let xcode = tools.appendingPathComponent("Xcode.app")
        makeDir(xcode.appendingPathComponent("Contents/Applications/Instruments.app"))
        makeDir(xcode.appendingPathComponent("Contents/Developer/Applications/Simulator.app"))
        makeDir(xcode.appendingPathComponent("Contents/Frameworks/Helper.app"))
        let embedded = Set(SearchScopes.appBundles(in: [tools.path]).map(\.lastPathComponent))
        check(
            "apps embedded in a bundle's application folders are indexed",
            embedded == ["Xcode.app", "Instruments.app", "Simulator.app"])
        check(
            "an .app scope also yields its embedded apps",
            Set(SearchScopes.appBundles(in: [xcode.path]).map(\.lastPathComponent)) == embedded)

        /// 在指定子目录下构造若干假应用并返回其扫描顺序。
        func listing(_ folder: String, versions: [String: String]) -> [String] {
            let url = root.appendingPathComponent(folder)
            for (name, version) in versions {
                makeApp(url.appendingPathComponent(name), version: version)
            }
            return SearchScopes.appBundles(in: [url.path]).map(\.lastPathComponent)
        }

        // 名称镜像排列，确保任何固定的文件系统顺序都不会侥幸同时通过两项检查。
        check(
            "a folder lists its newest version first, compared as numbers",
            listing("Rising", versions: ["A.app": "9.4", "B.app": "26.6", "C.app": "27.0"])
                == ["C.app", "B.app", "A.app"])
        check(
            "the newest version leads whatever its name",
            listing("Falling", versions: ["A.app": "27.0", "B.app": "26.6", "C.app": "9.4"])
                == ["A.app", "B.app", "C.app"])

        check(
            "equal versions fall back to Finder's name order",
            listing("Ties", versions: ["Xcode-beta.app": "26.0", "Xcode.app": "26.0"])
                == ["Xcode.app", "Xcode-beta.app"])

        let unreadable = root.appendingPathComponent("Unreadable")
        makeDir(unreadable.appendingPathComponent("Aardvark.app"))
        makeApp(unreadable.appendingPathComponent("Zebra.app"), version: "1.0")
        check(
            "a bundle with no version sorts after one that has a version",
            SearchScopes.appBundles(in: [unreadable.path]).map(\.lastPathComponent)
                == ["Zebra.app", "Aardvark.app"])

        check(
            "an earlier scope still wins over a newer version in a later one",
            SearchScopes.appBundles(in: [
                root.appendingPathComponent("Rising/A.app").path,
                root.appendingPathComponent("Rising").path
            ]).map(\.lastPathComponent).first == "A.app")

        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [deep.path, apps.path]).map(\.lastPathComponent).first
                == "TooDeep.app")
        check(
            "overlapping scopes yield each app once, at its first scope's position",
            SearchScopes.appBundles(in: [xcode.path, tools.path, deep.path, vendor.path])
                .map(\.lastPathComponent)
                == ["Xcode.app", "Instruments.app", "Simulator.app", "TooDeep.app", "Nested.app"])

        let home = fm.homeDirectoryForCurrentUser.path
        check(
            "expand resolves a tilde",
            SearchScopes.expand("~/Applications") == home + "/Applications")
        check(
            "abbreviate restores the tilde",
            SearchScopes.abbreviate(home + "/Applications") == "~/Applications")
        check(
            "tilde survives a round trip",
            SearchScopes.abbreviate(SearchScopes.expand("~/Applications")) == "~/Applications")
        check(
            "expand leaves an absolute path alone",
            SearchScopes.expand("/Applications") == "/Applications")
        check(
            "a trailing slash is trimmed",
            SearchScopes.abbreviate("/Applications/") == "/Applications")
        check("root survives trimming", SearchScopes.abbreviate("/") == "/")

        check(
            "normalize dedups after abbreviating",
            SearchScopes.normalize([
                "/Applications", "/Applications/", home + "/Applications", "~/Applications"
            ])
                == ["/Applications", "~/Applications"])
        check("normalize preserves order", SearchScopes.normalize(["/B", "/A"]) == ["/B", "/A"])
        check("normalize drops blanks", SearchScopes.normalize(["  ", "/A"]) == ["/A"])
        check(
            "defaults are already normalized",
            SearchScopes.normalize(SearchScopes.defaults) == SearchScopes.defaults)

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
