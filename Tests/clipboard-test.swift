// 文件职责：剪贴板存储（ClipboardStore）的独立测试 harness，覆盖置顶、保留策略、类型过滤、持久化、导入导出与默认动作等行为。
// 分层：测试 harness；直接编译真实源码而非副本，断言失败时以非零退出码结束。
import Foundation

/// 剪贴板存储与条目行为的主测试套件，`main()` 顺序执行全部用例并汇总通过/失败数。
@main
@MainActor
struct ClipboardTests {
    static var failures = 0
    static var passes = 0

    /// 测试入口：依次运行全部用例，打印通过率，失败时以退出码 1 结束。
    static func main() {
        pinOrder()
        unpinRejoinsAsNewest()
        pasteLeavesPinsAlone()
        pinsSurvivePruningAndTheWindow()
        pinsLeadFilteredSearches()
        pinnedSlotResolutionUsesVisiblePins()
        landingSkipsThePins()
        textFormClassification()
        colorParsing()
        colorFormatting()
        colorSpaceConversions()
        colorFormatsRoundTrip()
        typeFilterSplitsTheHistory()
        typeFilterJoinsTheSearchMemo()
        persistence()
        exportSeesPastTheMemoryWindow()
        importedImagesArriveOnce()
        multiFileCopyMakesOneRowEach()
        referencedFilesOutliveTheirRows()
        filePathsAreNeverATextForm()
        fileEntriesAreFoundByNameAndFolder()
        fileKindClassification()
        importedFilesArriveOncePerPath()
        defaultActionChords()
        plainTextSkipsTheFile()
        offersTextExtraction()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - 用例

    /// 置顶按置顶顺序堆叠，最早的置顶在最前，与条目本身的新旧无关。
    static func pinOrder() {
        withStore { store, _ in
            store.addText("oldest", sourceBundleID: nil)
            store.addText("middle", sourceBundleID: nil)
            store.addText("newest", sourceBundleID: nil)

            store.togglePinned(item(store, "oldest"))
            expect(texts(store) == ["oldest", "newest", "middle"], "first pin leads the list")

            store.togglePinned(item(store, "middle"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "second pin joins below the first, and does not sort by recency")

            store.togglePinned(item(store, "newest"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "pins hold pin order, not the recency order they had in the history")
        }
    }

    /// 取消置顶会把该行作为今天最新的条目重新插入，而不是回到原来的位置。
    static func unpinRejoinsAsNewest() {
        withStore { store, _ in
            store.addText("a", sourceBundleID: nil)
            store.addText("b", sourceBundleID: nil)
            store.addText("c", sourceBundleID: nil)
            let before = item(store, "a").createdAt

            store.togglePinned(item(store, "a"))
            store.togglePinned(item(store, "a"))

            expect(texts(store) == ["a", "c", "b"], "unpinned row leads the history")
            expect(!item(store, "a").isPinned, "pin stamp cleared")
            expect(item(store, "a").createdAt > before, "unpin re-recencies the row")
        }
    }

    /// 粘贴一个置顶条目不得打乱「置顶」区域。
    static func pasteLeavesPinsAlone() {
        withStore { store, _ in
            store.addText("one", sourceBundleID: nil)
            store.addText("two", sourceBundleID: nil)
            store.togglePinned(item(store, "one"))
            store.togglePinned(item(store, "two"))
            let stamp = item(store, "one").createdAt

            store.promote(item(store, "one"))

            expect(texts(store) == ["one", "two"], "promote leaves a pinned row in place")
            expect(item(store, "one").createdAt == stamp, "promote does not rewrite a pinned row")

            store.addText("three", sourceBundleID: nil)
            store.addText("four", sourceBundleID: nil)
            store.promote(item(store, "three"))
            expect(
                texts(store) == ["one", "two", "three", "four"],
                "an unpinned row still promotes to the head of the history")
        }
    }

    /// 保留策略会扫掉置顶条目周边的一切，但永远不会扫掉置顶本身。
    static func pinsSurvivePruningAndTheWindow() {
        withStore { store, dir in
            // 比用例的 1 天保留期更旧，但在导入时默认的保留窗口之内。
            let old = Date().addingTimeInterval(-2 * 86_400)
            _ = store.importEntries([
                entry("ancient-pinned", at: old),
                entry("ancient-loose", at: old.addingTimeInterval(1)),
                entry("fresh", at: Date())
            ])
            store.togglePinned(item(store, "ancient-pinned"))

            store.maxAge = 86_400
            store.enforceLimits()
            expect(
                Set(texts(store)) == ["ancient-pinned", "fresh"],
                "pruning skips pinned rows and takes the rest")

            // 重新打开：即使它远在保留窗口之外，置顶也必须回来。
            let reopened = ClipboardStore(directory: dir)
            reopened.maxAge = 86_400
            reopened.load()
            expect(
                Set(texts(reopened)) == ["ancient-pinned", "fresh"],
                "a pin outlives retention across a relaunch")
        }
    }

    /// 即使 FTS 语句的 LIMIT 碰不到，置顶条目也必须领跑过滤后的搜索。
    static func pinsLeadFilteredSearches() {
        withStore { store, _ in
            var seed: [ClipboardItem] = []
            let base = Date().addingTimeInterval(-10_000)
            // 被置顶的命中项是 260 个匹配中最旧的，而 FTS 语句止步于 200。
            seed.append(entry("needle in the haystack", at: base))
            for i in 1...259 {
                seed.append(entry("haystack filler \(i)", at: base.addingTimeInterval(Double(i))))
            }
            _ = store.importEntries(seed)
            store.togglePinned(item(store, "needle in the haystack"))

            let results = store.search("haystack", filter: .all)
            expect(results.count > 200, "FTS results plus the pinned block")
            expect(
                results.first?.text == "needle in the haystack",
                "the pinned match leads the filtered results")
            expect(
                results.filter(\.isPinned).count == 1, "the pinned row is not duplicated")

            // 低于 trigram 阈值：走回退路径。
            let short = store.search("ne", filter: .all)
            expect(
                short.first?.text == "needle in the haystack",
                "the pinned match leads the fallback search too")
        }
    }

    /// 插槽选择取自查询/过滤后的可见置顶块，而不是全部置顶项。
    static func pinnedSlotResolutionUsesVisiblePins() {
        withStore { store, _ in
            store.addText("alpha one", sourceBundleID: nil)
            store.addText("beta two", sourceBundleID: nil)
            store.addText("beta three", sourceBundleID: nil)
            store.addText("plain text", sourceBundleID: nil)

            store.togglePinned(item(store, "alpha one"))
            store.togglePinned(item(store, "beta two"))
            store.togglePinned(item(store, "beta three"))

            expect(
                store.pinnedItem(at: 0, in: "", filter: .all)?.text == "alpha one",
                "slot 1 maps to the first pinned row")
            expect(
                store.pinnedItem(at: 2, in: "", filter: .all)?.text == "beta three",
                "slot 3 maps to the third pinned row")
            expect(
                store.pinnedItem(at: 3, in: "", filter: .all) == nil,
                "missing pinned slot returns nil")

            expect(
                store.pinnedItem(at: 0, in: "beta", filter: .all)?.text == "beta two",
                "query narrows the pinned block before slot mapping")
            expect(
                store.pinnedItem(at: 1, in: "beta", filter: .all)?.text == "beta three",
                "slot mapping follows visible pinned order under query")
            expect(
                store.pinnedItem(at: 2, in: "beta", filter: .all) == nil,
                "query can remove pinned slots from reach")

            expect(
                store.pinnedItem(at: 0, in: "", filter: .link) == nil,
                "filter applies before pinned slot mapping")
        }
    }

    /// 空查询重置时会越过置顶项落到最新剪贴；键入查询时则落在它的第一个匹配上。
    static func landingSkipsThePins() {
        withStore { store, _ in
            store.addText("alpha one", sourceBundleID: nil)
            store.addText("beta two", sourceBundleID: nil)
            store.addText("https://example.com", sourceBundleID: nil)
            store.addText("beta three", sourceBundleID: nil)
            expect(
                store.landingIndex(in: "", filter: .all) == 0, "no pins: the newest clip is row 0")

            store.togglePinned(item(store, "alpha one"))
            store.togglePinned(item(store, "beta two"))
            let landing = store.landingIndex(in: "", filter: .all)
            expect(landing == 2, "nothing typed: the landing passes both pins")
            expect(
                store.search("", filter: .all)[landing].text == "beta three",
                "and lands on the most recent copy")
            expect(store.landingIndex(in: "  ", filter: .all) == 2, "a blank query is no query")
            expect(
                store.landingIndex(in: "beta", filter: .all) == 0,
                "a typed query lands on its first match, even a pinned one")
            expect(
                store.landingIndex(in: "", filter: .text) == 2,
                "a filter still passes the pins it shows")
            expect(
                store.landingIndex(in: "", filter: .link) == 0,
                "and lands on its first row when it shows none")

            store.togglePinned(item(store, "https://example.com"))
            store.togglePinned(item(store, "beta three"))
            expect(
                store.landingIndex(in: "", filter: .all) == 0,
                "an all-pinned list has no clip to pass to, so it stays on row 0")
        }
    }

    /// 链接/地址分类器，包括那些绝不能读作链接的文件名。
    static func textFormClassification() {
        let links = [
            "https://apple.com", "http://apple.com/path?q=1", "apple.com", "apple.com/store",
            "www.Apple.com", "vscode://file/tmp/x", "docs.google.com", "bit.ly/abc"
        ]
        for text in links {
            expect(form(text) == .link, "\(text) is a link")
        }

        let addresses = ["hi@apple.com", "mailto:hi@apple.com", "first.last@mail.example.co.uk"]
        for text in addresses {
            expect(form(text) == .email, "\(text) is an address")
        }

        let plain = [
            // 与真实 TLD 撞名的扩展名，正是需要那份 TLD 集合的全部理由。
            "report.pdf", "index.html", "App.swift", "data.json", "Safari.app", "image.png",
            "hello world", "visit apple.com today", "3.14", "", "   ", "no-dot-at-all",
            "two@at@signs.com", "@apple.com", "hi@localhost", "line one\nline two"
        ]
        for text in plain {
            expect(form(text) == .plain, "\(String(text.prefix(20))) is plain text")
        }

        // 颜色是一种独立形式，即使写成带空格的写法也优先于正文分支。
        for text in ["#FF5733", "#0f0", "rgb(255, 87, 51)", "hsl(11, 100%, 60%)"] {
            expect(form(text) == .color, "\(text) is a colour")
        }

        // 超过扫描上限，因此多兆字节的复制永远不会被逐字检索 scheme。
        expect(
            form("https://apple.com/" + String(repeating: "a", count: 4096)) == .plain,
            "an over-long token is plain by definition")

        expect(
            ClipboardItem(imagePath: "/tmp/x.png", sourceBundleID: nil).textForm == nil,
            "an image has no text form")
    }

    /// 解析器接受的所有写法，以及它必须拒绝的近似写法。
    static func colorParsing() {
        let cases: [(String, ColorValue)] = [
            ("#FF5733", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
            // 简写是把每位数字重复一遍，而不是补一个零。
            ("#0f0", ColorValue(red: 0, green: 1, blue: 0)),
            ("#0f08", ColorValue(red: 0, green: 1, blue: 0, alpha: 136 / 255)),
            ("rgb(255, 87, 51)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
            ("rgb(0 255 0 / 0.5)", ColorValue(red: 0, green: 1, blue: 0, alpha: 0.5)),
            ("rgba(255,87,51,0.5)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255, alpha: 0.5)),
            ("hsl(120, 100%, 50%)", ColorValue(red: 0, green: 1, blue: 0)),
            ("hsl(10.6deg 100% 60%)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
            // 颜色选择器交给扩展的写法，以及它的百分比色度。
            ("oklch(62.7955% 0.257683 29.2338)", ColorValue(red: 1, green: 0, blue: 0)),
            ("oklch(0.627955 64.42% 29.2338deg / 0.5)", ColorValue(red: 1, green: 0, blue: 0, alpha: 0.5))
        ]
        for (text, expected) in cases {
            guard let parsed = ColorValue.parse(text) else {
                expect(false, "\(text) parses")
                continue
            }
            expect(near(parsed, expected), "\(text) resolves to its components")
        }

        // 字节级拒绝发生在任何修剪之前，因此它的形状也在此固定。
        for text in ["#FF5733 and more", "rgb(255, 87, 51) plus", "(255, 87, 51)", "#", "rgb"] {
            expect(ColorValue.parse(text) == nil, "\(text) is not a colour")
        }

        // 十六进制形状的单词与位数不对的写法都绝不能读作颜色。
        let rejected = [
            "#GGGGGG", "#12345", "#", "report.pdf", "rgb(1, 2)", "rgb(1, 2, 3", "hsl(1, 2, 3, 4, 5)",
            "cmyk(0, 1, 1, 0)", "255, 87, 51", "#" + String(repeating: "f", count: 96),
            // 非有限字面量能被解析为 Double，而每种写法都终结于一个 `Int(_:)`。
            "rgb(nan, 0, 0)", "hsl(inf, 100%, 50%)", "rgb(1e400, 0, 0)", "rgba(0, 0, 0, nan)",
            // CSS 把 HSL 通道写作百分比；写成 `100` 就会被夹成白色。
            "hsl(120, 100, 50)", "hsl(120 100 50)", "hsla(120, 100, 50, 1)",
            // 参数列表是逐个计数的，所以其中的空洞是畸形而不是被丢弃。
            "rgb(255,,87,51)", "rgb(255,87,51,)", "rgb(255, 87)", "rgb()", "rgb(1,2,3,4,5)",
            // 两种拼法从不混用，因此逗号写法不得同时携带斜杠。
            "rgb(1/2, 3, 4)", "rgb(255, 87, 51 / 0.5)", "rgb(0 255 0 / 0.5 / 1)", "rgb(/0.5)",
            // 斜杠两侧分别计数：拉平就会把 alpha 读成蓝色通道。
            "rgb(0 255 / 0.5)", "hsl(120 100% / 50%)", "rgb(0 / 255 0)", "rgb(0 255 0 0)",
            // `Double` 会读入 CSS 从不写的 Swift 字面量，而 `isHexDigit` 会读入全角字符。
            "rgb(0x10, 0, 0)", "rgb(1e2, 0, 0)", "rgb(+255, 0, 0)", "#\u{ff46}\u{ff46}\u{ff46}"
        ]
        for text in rejected {
            expect(ColorValue.parse(text) == nil, "\(String(text.prefix(20))) is not a colour")
        }

        // 在 CSS Color 4 下 `rgba()` 是 `rgb()` 的别名，因此两者的 alpha 都是可选的。
        for text in [
            "rgba(255, 87, 51)", "rgb(255, 87, 51, 0.5)", "hsla(120, 100%, 50%)",
            "hsl(120, 100%, 50%, 0.5)", "hsl(120, 100%, 50%, 50%)", "rgb(0 255 0)",
            // CSS 把所有空白同等对待，而复制来的声明会跨行。
            "rgb(255,\n87,\n51)", "rgb(0\n255\n0)"
        ] {
            expect(ColorValue.parse(text) != nil, "\(String(text.prefix(20))) is a colour")
        }

        // 舍入会让亮度为 1 的颜色残留约 1e-16 的色度，其饱和度除数恰好为 0。
        guard let almostWhite = ColorValue.parse("rgb(100%, 100%, 99.99999999999999%)") else {
            expect(false, "an almost-white colour parses")
            return
        }
        expect(
            ColorFormat.offered(for: almostWhite).allSatisfy { !$0.string(for: almostWhite).isEmpty },
            "every notation of an almost-white colour states a value rather than trapping")
        expect(
            almostWhite.hsl.saturation.isFinite, "a zero-span lightness reports no saturation")

        // 四位的简写像三位形式重复其余部分一样，重复它的 alpha 数字。
        expect(
            ColorValue.parse("#0f0f").map { ColorFormat.hexWithAlpha.string(for: $0) }
                == "#00FF00FF",
            "#0f0f is opaque green")
        expect(
            ColorValue.parse("#000000FF")?.hasAlpha == false,
            "an alpha that rounds back to opaque is opaque, so no alpha row is offered")

        // HSL 换算的两个方向必须一致，否则复制出的值会漂移。
        let round = ColorValue(red: 0.2, green: 0.6, blue: 0.9)
        let hsl = round.hsl
        expect(
            near(
                ColorValue(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness),
                round),
            "HSL round-trips back to the same sRGB components")
    }

    /// 每种写法读出来是什么，以及不透明颜色会被提供哪些写法。
    static func colorFormatting() {
        guard let color = ColorValue.parse("#FF5733") else {
            expect(false, "the fixture parses")
            return
        }
        expect(ColorFormat.hex.string(for: color) == "#FF5733", "hex is uppercase")
        expect(
            ColorFormat.rgba.string(for: color) == "rgba(255, 87, 51, 1)", "rgba states channels")
        // 保留一位小数，因为整数度数在往回换算时最多会差 5/255。
        expect(
            ColorFormat.hsl.string(for: color) == "hsl(10.6deg, 100%, 60%)",
            "hsl keeps the precision that survives a round trip")
        // 精确的通道会去掉末尾的零，而不是读作 `0.210`。
        expect(
            ColorFormat.oklch.string(for: color) == "oklch(68% 0.21 33.7deg)",
            "oklch states three decimals of chroma")
        expect(
            !ColorFormat.offered(for: color).contains(.hslWithAlpha),
            "an opaque colour is offered no alpha-bearing duplicate")

        guard let translucent = ColorValue.parse("rgba(255, 87, 51, 0.5)") else {
            expect(false, "the translucent fixture parses")
            return
        }
        expect(
            ColorFormat.offered(for: translucent) == ColorFormat.allCases,
            "a colour with alpha is offered every notation")
        expect(
            ColorFormat.hexWithAlpha.string(for: translucent) == "#FF573380",
            "alpha is the fourth hex channel")
        expect(
            ColorFormat.primary(for: translucent) == .hexWithAlpha,
            "the notation ↵ copies keeps a translucent colour whole")
        expect(ColorFormat.primary(for: color) == .hex, "an opaque colour copies as plain hex")
    }

    /// CSS Color 4 色彩空间：拿一个中性色与一个已知色去比对它们必然产生的值。
    static func colorSpaceConversions() {
        guard let grey = ColorValue.parse("#DDDDDD"), let orange = ColorValue.parse("#FF5733")
        else {
            expect(false, "the fixtures parse")
            return
        }
        // 中性色没有色相，而 `atan2` 在两次舍入误差上仍会报出一个色相。
        expect(ColorFormat.oklch.string(for: grey) == "oklch(89.8% 0 0deg)", "nor an Oklch hue")
        // Oklab 的轴只到约 ±0.4，写成一位小数会把大多数颜色报成零。
        expect(
            ColorFormat.oklch.string(for: orange) == "oklch(68% 0.21 33.7deg)", "and Oklch with it")

        // CSS4 拼法把 alpha 放在斜杠之后，没有 alpha 时则什么都不写。
        guard let translucent = ColorValue.parse("rgba(0, 255, 0, 0.5)") else {
            expect(false, "the translucent fixture parses")
            return
        }
        expect(
            ColorFormat.oklch.string(for: translucent) == "oklch(86.6% 0.295 142.5deg / 0.5)",
            "a slash carries alpha")
        expect(
            ColorFormat.oklch.string(for: orange) == "oklch(68% 0.21 33.7deg)",
            "and an opaque colour states none")
        expect(
            ColorFormat.offered(for: orange).count == ColorFormat.allCases.count - 2,
            "only the two alpha-named spellings are dropped from an opaque colour")
    }

    /// 每种被提供的写法都必须能重新解析回它自己的颜色：一次扫查损失与丢失的 alpha。
    static func colorFormatsRoundTrip() {
        var checked = 0
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 29) {
                for blue in stride(from: 0, through: 255, by: 43) {
                    for alpha in [255, 128] {
                        let color = ColorValue(
                            red: Double(red) / 255, green: Double(green) / 255,
                            blue: Double(blue) / 255, alpha: Double(alpha) / 255)
                        for format in ColorFormat.offered(for: color) {
                            // `oklch()` 能重新解析，但写的位数太少，落不回具体通道。
                            guard format != .oklch else { continue }
                            let text = format.string(for: color)
                            guard let back = ColorValue.parse(text) else {
                                expect(false, "\(text) re-parses")
                                return
                            }
                            // 不含 alpha 的写法按设计就是不透明拼法。
                            guard near(back, color, matchingAlpha: back.hasAlpha == color.hasAlpha)
                            else {
                                expect(false, "\(text) states the colour it came from")
                                return
                            }
                            checked += 1
                        }
                    }
                }
            }
        }
        expect(checked > 500, "the sweep actually covered the notations")
    }

    /// 每种写法给出的都是 8 位通道，因此通道级一致就是一致。
    static func near(_ lhs: ColorValue, _ rhs: ColorValue, matchingAlpha: Bool = true) -> Bool {
        var channels = [(lhs.red, rhs.red), (lhs.green, rhs.green), (lhs.blue, rhs.blue)]
        if matchingAlpha { channels.append((lhs.alpha, rhs.alpha)) }
        return channels.allSatisfy { abs($0 - $1) < 1.0 / 255 }
    }

    /// 每个过滤器只返回它自己那一类，同时置顶项仍领跑整块。
    static func typeFilterSplitsTheHistory() {
        withStore { store, _ in
            store.addText("just some prose", sourceBundleID: nil)
            store.addText("https://apple.com", sourceBundleID: nil)
            store.addText("hi@apple.com", sourceBundleID: nil)
            store.addText("second.link.dev", sourceBundleID: nil)
            store.addText("#FF5733", sourceBundleID: nil)
            store.addText("rgb(0 255 0 / 0.5)", sourceBundleID: nil)

            expect(texts(store).count == 6, "every entry under All Types")
            expect(texts(store, filter: .text) == ["just some prose"], "text excludes links")
            expect(
                texts(store, filter: .color) == ["rgb(0 255 0 / 0.5)", "#FF5733"],
                "a colour is its own type, in whichever notation it was written")
            expect(
                texts(store, filter: .link) == ["second.link.dev", "https://apple.com"],
                "links stay newest-first")
            expect(texts(store, filter: .email) == ["hi@apple.com"], "addresses on their own")
            expect(texts(store, filter: .image).isEmpty, "no images were captured")

            store.togglePinned(item(store, "https://apple.com"))
            expect(
                texts(store, filter: .link) == ["https://apple.com", "second.link.dev"],
                "a pinned link leads its filtered block")
        }
    }

    /// 搜索缓存也以过滤器为键：同一查询、新过滤器就得到不同的行。
    static func typeFilterJoinsTheSearchMemo() {
        withStore { store, _ in
            store.addText("shared token prose", sourceBundleID: nil)
            store.addText("shared-token.com", sourceBundleID: nil)

            expect(store.search("shared", filter: .all).count == 2, "both match the query")
            expect(
                store.search("shared", filter: .link).map(\.text) == ["shared-token.com"],
                "the same query under a link filter is not served from the wider memo")
            expect(
                store.search("shared", filter: .text).map(\.text) == ["shared token prose"],
                "and switching filters again re-runs rather than reusing")
            expect(store.search("shared", filter: .all).count == 2, "back to both")
        }
    }

    /// 置顶标记及其顺序在重新打开后依然保留。
    static func persistence() {
        withStore { store, dir in
            store.addText("first", sourceBundleID: nil)
            store.addText("second", sourceBundleID: nil)
            store.addText("third", sourceBundleID: nil)
            store.togglePinned(item(store, "third"))
            store.togglePinned(item(store, "first"))

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(
                texts(reopened) == ["third", "first", "second"],
                "pin order is restored from disk, not recomputed from recency")

            reopened.togglePinned(item(reopened, "third"))
            expect(texts(reopened) == ["first", "third", "second"], "unpin after a reload")

            reopened.clearAll()
            expect(texts(reopened) == ["first"], "Clear History spares the pin")

            let afterClear = ClipboardStore(directory: dir)
            afterClear.load()
            expect(texts(afterClear) == ["first"], "and the unpinned rows are gone from disk")
        }
    }

    /// 备份会读整张表，而不是读到内存窗口就停的 `items`。
    static func exportSeesPastTheMemoryWindow() {
        withStore { store, _ in
            let total = 1_200
            store.importEntries(
                (0..<total).map {
                    ClipboardItem(
                        id: UUID(), kind: .text, text: "entry \($0)", imagePath: nil,
                        createdAt: Date().addingTimeInterval(TimeInterval($0 - total)),
                        sourceBundleID: nil)
                })
            expect(store.items.count < total, "the resident window holds back some of the history")

            var streamed = 0
            var seen = Set<String>()
            ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { item in
                streamed += 1
                if let text = item.text { seen.insert(text) }
            }
            expect(streamed == total, "the export streams every row, not just the window")
            expect(seen.count == total, "every row arrives exactly once")
        }
    }

    /// 同一份备份导入两次，不得为每张图片留一份副本。
    static func importedImagesArriveOnce() {
        withStore { store, dir in
            let staging = dir.appendingPathComponent("staged", isDirectory: true)
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let blob = staging.appendingPathComponent("blob.png")
            let staged = ClipboardItem(imagePath: blob.path, sourceBundleID: nil)

            for pass in 1...2 {
                try? Data("png".utf8).write(to: blob)
                let inserted = ClipboardStore.importStoredItems(
                    inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir, [staged])
                expect(inserted == (pass == 1 ? 1 : 0), "pass \(pass) inserts \(2 - pass) row(s)")
            }
            store.load()
            expect(store.items.count == 1, "the second import adds no row")
            let images =
                (try? FileManager.default.contentsOfDirectory(atPath: store.imagesDir.path)) ?? []
            expect(images == ["blob.png"], "and no second copy of the blob")
        }
    }

    /// 每个文件一行，并且最先复制的文件领跑历史。
    static func multiFileCopyMakesOneRowEach() {
        withStore { store, _ in
            store.addFiles(["/tmp/a.png", "/tmp/b.mov", "/tmp/c.pdf"], sourceBundleID: nil)
            expect(store.items.count == 3, "three files make three rows")
            expect(
                store.items.map(\.filePath) == ["/tmp/c.pdf", "/tmp/b.mov", "/tmp/a.png"],
                "and the reader inserts them newest-last")
            store.addFiles(["/tmp/c.pdf"], sourceBundleID: nil)
            expect(store.items.count == 3, "re-copying the leading file adds no row")
        }
    }

    /// 最关键的一条：仅仅被引用的文件永远不该由我们删除。
    static func referencedFilesOutliveTheirRows() {
        withStore { store, dir in
            let outside = dir.appendingPathComponent("original.txt")
            try? Data("keep me".utf8).write(to: outside)
            store.addFiles([outside.path], sourceBundleID: nil)

            store.remove(store.items[0])
            expect(
                FileManager.default.fileExists(atPath: outside.path),
                "removing a row leaves the referenced file on disk")

            store.addFiles([outside.path], sourceBundleID: nil)
            store.maxAge = -1
            store.enforceLimits()
            expect(store.items.isEmpty, "a retention cut takes the row")
            expect(
                FileManager.default.fileExists(atPath: outside.path),
                "but never the referenced file")

            store.maxAge = 86_400
            store.addFiles([outside.path], sourceBundleID: nil)
            store.clearAll()
            expect(
                FileManager.default.fileExists(atPath: outside.path),
                "and Clear History leaves it too")
        }
    }

    /// 路径不是正文：它绝不能被归为链接、颜色或地址。
    static func filePathsAreNeverATextForm() {
        let item = ClipboardItem(filePath: "/Users/me/apple.com/#FF5733.txt", sourceBundleID: nil)
        expect(item.textForm == nil, "a file entry has no text form")
        expect(item.colorValue == nil, "and parses as no colour")
        expect(!ClipboardFilter.link.matches(item), "so Links Only never shows it")
        expect(!ClipboardFilter.text.matches(item), "nor does Text Only")
        expect(ClipboardFilter.file.matches(item), "only Files Only does")
    }

    /// 路径存在 `text` 里，因此 trigram 索引能按文件名或文件夹找到文件。
    static func fileEntriesAreFoundByNameAndFolder() {
        withStore { store, _ in
            store.addFiles(["/Users/me/Downloads/Quarterly Report.pdf"], sourceBundleID: nil)
            expect(store.search("report", filter: .all).count == 1, "FTS finds it by name")
            expect(store.search("downloads", filter: .all).count == 1, "and by folder")
            expect(store.search("re", filter: .all).count == 1, "the sub-trigram fallback too")
        }
    }

    /// 按扩展名/目录标记判断文件类型。
    static func fileKindClassification() {
        expect(ClipboardFileKind.of(path: "/a/b.mov") == .movie, "a .mov is a movie")
        expect(ClipboardFileKind.of(path: "/a/b.png") == .image, "a .png is an image")
        expect(ClipboardFileKind.of(path: "/a/b.pdf") == .pdf, "a .pdf is a PDF")
        expect(ClipboardFileKind.of(path: "/a/b.m4a") == .audio, "an .m4a is audio")
        expect(ClipboardFileKind.of(path: "/a/README") == .other, "a bare name is not a folder")
        expect(ClipboardFileKind.of(path: "/a/b", isDirectory: true) == .folder, "a folder is one")
    }

    /// `importKey` 必须按路径区分文件行，否则所有文件会撞成同一行。
    static func importedFilesArriveOncePerPath() {
        withStore { store, _ in
            let a = ClipboardItem(filePath: "/tmp/one.pdf", sourceBundleID: nil)
            let b = ClipboardItem(filePath: "/tmp/two.pdf", sourceBundleID: nil)
            expect(store.importEntries([a, b]) == 2, "two distinct paths import as two rows")
            expect(store.importEntries([a]) == 0, "and re-importing one adds nothing")
            expect(
                store.items.allSatisfy { $0.imagePath == nil },
                "an imported file row is never adopted into imagesDir")
        }
    }

    /// 默认动作占据 ↵ 与粘贴的快捷键；Paste 与 Copy 默认则保留各自原有的组合。
    static func defaultActionChords() {
        let text = ClipboardItem(text: "hello", sourceBundleID: nil)
        let file = ClipboardItem(filePath: "/Users/me/report.pdf", sourceBundleID: nil)
        let image = ClipboardItem(imagePath: "/tmp/shot.png", sourceBundleID: nil)
        let expected: [ClipboardDefaultAction: [ClipboardDefaultAction]] = [
            .paste: [.paste, .copy, .pastePlainText],
            .copy: [.copy, .paste, .pastePlainText],
            .pastePlainText: [.pastePlainText, .copy, .paste]
        ]
        for (defaultAction, actions) in expected {
            for item in [text, file] {
                expect(
                    ClipboardChord.allCases.map { defaultAction.action(for: $0, on: item) } == actions,
                    "\(defaultAction) orders ↵, ⌘↵, ⌃⌘↵ as \(actions) on a \(item.kind) entry")
            }
            let imageActions = ClipboardChord.allCases.map { defaultAction.action(for: $0, on: image) }
            let paste: ClipboardDefaultAction = defaultAction == .copy ? .copy : .paste
            expect(imageActions.first == paste, "\(defaultAction) on an image never pastes plain")
            expect(imageActions.last == .some(nil), "and ⌃⌘↵ has nothing to run on it")
        }
    }

    /// 「纯文本」取各类型的自身文本：文本取文本、文件取路径、图片则没有。
    static func plainTextSkipsTheFile() {
        expect(ClipboardItem(text: "hi", sourceBundleID: nil).plainText == "hi", "text is itself")
        expect(
            ClipboardItem(filePath: "/a/b.pdf", sourceBundleID: nil).plainText == "/a/b.pdf",
            "a file is its path")
        expect(
            ClipboardItem(imagePath: "/a/b.png", sourceBundleID: nil).plainText == nil,
            "an image has no plain text")
    }

    /// Copy Text（复制文本）只对图片回答：捕获的 blob 或图片文件，绝不是文本或 PDF。
    static func offersTextExtraction() {
        expect(
            ClipboardItem(imagePath: "/tmp/shot.png", sourceBundleID: nil).offersTextExtraction,
            "a captured image offers Copy Text")
        expect(
            !ClipboardItem(
                id: UUID(), kind: .image, text: nil, imagePath: nil, createdAt: Date(),
                sourceBundleID: nil
            ).offersTextExtraction,
            "an image entry without its blob does not")
        expect(
            !ClipboardItem(text: "hello", sourceBundleID: nil).offersTextExtraction,
            "a text entry does not")
        expect(
            ClipboardItem(filePath: "/Users/me/shot.png", sourceBundleID: nil)
                .offersTextExtraction,
            "an image file copied in Finder offers Copy Text")
        expect(
            !ClipboardItem(filePath: "/Users/me/notes.txt", sourceBundleID: nil)
                .offersTextExtraction,
            "a text file does not")
        expect(
            !ClipboardItem(filePath: "/Users/me/report.pdf", sourceBundleID: nil)
                .offersTextExtraction,
            "a PDF stays a background-indexing capability")
    }

    // MARK: - Harness（测试辅助）

    /// 在一个新建临时目录上运行 `body`，结束后拆除该目录。
    static func withStore(_ body: (ClipboardStore, URL) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ClipboardStore(directory: dir), dir)
    }

    /// 新建一个唯一的临时目录供测试使用。
    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "gearmac-clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 把文本包成剪贴板条目后取其文本形式分类。
    static func form(_ text: String) -> ClipboardItem.TextForm? {
        ClipboardItem(text: text, sourceBundleID: nil).textForm
    }

    /// 构造一个指定时间与文本的测试用剪贴板条目。
    static func entry(_ text: String, at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: date,
            sourceBundleID: nil)
    }

    /// 以空查询搜索存储并取出其中的文本。
    static func texts(_ store: ClipboardStore, filter: ClipboardFilter = .all) -> [String] {
        store.search("", filter: filter).compactMap(\.text)
    }

    /// 按文本取出存储中的条目，找不到则直接判失败退出。
    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            fail("no entry named \(text)")
            exit(1)
        }
        return match
    }

    /// 断言辅助：条件成立则通过数加一。
    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    /// 记录一次失败并打印其标签。
    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
