// 文件职责：验证 SymbolCatalog 的加载、去重、分类与搜索，断言形状级不变量。
// 分层：测试 harness；直接读取本机 CoreGlyphs，因此只断言形状而非精确数量。

import AppKit

/// 符号目录的独立测试 harness（直接运行，不依赖 XCTest）。
@main
@MainActor
struct SymbolTests {
    static var failures = 0
    static var passes = 0

    /// 运行全部断言，并据此设置进程退出码。
    static func main() {
        let catalog = SymbolCatalog.load()

        check("the system catalog loads", catalog.symbols.count > 1_000, "got \(catalog.symbols.count)")
        check(
            "it's more than the curated set",
            catalog.symbols.count > SymbolCatalog.suggested.count * 10)
        check("no duplicates", Set(catalog.symbols).count == catalog.symbols.count)

        // 应用自带的符号是资源图片——系统无法绘制的那批。
        let unrenderable = catalog.symbols.prefix(400)
            .filter { !SymbolCatalog.isBundled($0) }
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("the first 400 all render", unrenderable.isEmpty, "got \(unrenderable.prefix(5))")

        // 内置符号不得与系统符号名重名，否则资源图片会遮蔽系统符号。
        let colliding = SymbolCatalog.bundledGlyphs.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
        check(
            "bundled marks name nothing the system already has", colliding.isEmpty,
            "got \(colliding)")

        // Apple 保留的符号不得出现在候选中。
        for reserved in ["icloud", "applelogo", "airplayvideo"] where catalog.symbols.contains(reserved) {
            fail("reserved symbol offered", detail: reserved)
        }
        check("reserved marks are filtered", !catalog.symbols.contains("icloud"))

        // 区域变体只是已列出符号的近似重复项。
        let locale = catalog.symbols.filter { $0.hasSuffix(".ar") || $0.hasSuffix(".rtl") }
        check("locale variants are filtered", locale.isEmpty, "got \(locale.prefix(5))")

        // 分类：两个合成分类加上真实主题分类，每个都非空。
        check("suggested is first", catalog.categories.first == .suggested)
        // 接下来是应用自带符号：系统目录里没有的那些。
        check("the bundled marks are second", catalog.categories.dropFirst().first == .bundled)
        check("all symbols is third", catalog.categories.dropFirst(2).first == .all)
        check(
            "every bundled mark is offered",
            SymbolCatalog.bundledGlyphs.allSatisfy(catalog.symbols.contains))
        check(
            "and they lead the suggested set",
            Array(SymbolCatalog.suggested.prefix(SymbolCatalog.bundledGlyphs.count))
                == SymbolCatalog.bundledGlyphs)
        // 系统完全没有蓝牙字形，这正是应用自带一个的原因。
        check(
            "bluetooth is reachable",
            catalog.search("bluetooth", in: .all).contains("bluetooth"))
        check("subject categories exist", catalog.categories.count > 10)
        let empty = catalog.categories.filter { catalog.symbols(in: $0).isEmpty }
        check("no empty category", empty.isEmpty, "got \(empty.map(\.title))")
        check(
            "rendering-mode buckets are not categories",
            !catalog.categories.contains { $0.id == "multicolor" || $0.id == "variable" })

        // 搜索：按名称、按系统自带搜索词，以及跨词匹配。
        check(
            "'coffee' finds the cup", catalog.search("coffee", in: .all).contains("cup.and.saucer"),
            "got \(catalog.search("coffee", in: .all).prefix(5))")
        check(
            "name search works", catalog.search("cup.and.saucer", in: .all).contains("cup.and.saucer"))
        check(
            "words can be given in any order",
            catalog.search("saucer cup", in: .all).contains("cup.and.saucer"))
        check("nonsense matches nothing", catalog.search("zzzqqq", in: .all).isEmpty)
        check(
            "an empty query is the whole category",
            catalog.search("", in: .all).count == catalog.symbols.count)
        // 从「建议」出发搜索会查找全部内容：88 个精选符号不构成索引。
        check(
            "search escapes the suggested set",
            catalog.search("thermometer", in: .suggested).count > 1)

        // 当 CoreGlyphs 不在预期位置时，兜底目录顶上。
        check("the fallback is usable", !SymbolCatalog.fallback.symbols.isEmpty)
        check(
            "the fallback is the curated set",
            SymbolCatalog.fallback.symbols.allSatisfy(SymbolCatalog.suggested.contains))
        check(
            "every curated symbol renders",
            SymbolCatalog.fallback.symbols.count == SymbolCatalog.suggested.count,
            "\(SymbolCatalog.suggested.count - SymbolCatalog.fallback.symbols.count) missing")

        print(
            failures == 0 ? "\nAll \(passes) checks passed." : "\n\(failures) failure(s), \(passes) passed.")
        exit(failures == 0 ? 0 : 1)
    }

    /// 断言条件成立；失败时记录并打印描述与详情。
    static func check(_ desc: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            fail(desc, detail: detail)
        }
    }

    /// 记录一次失败并打印描述与详情。
    static func fail(_ desc: String, detail: String) {
        failures += 1
        print("FAIL  \(desc)  \(detail)")
    }
}
