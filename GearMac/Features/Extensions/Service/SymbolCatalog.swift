// 文件职责：加载并检索系统 SF Symbols 目录（CoreGlyphs.bundle），并提供 GearMac 自带图标与推荐分类。
// 分层：Service；依赖 AppKit 校验符号可用性；读取全部为可选，失败时回退到内置策展列表。
import AppKit

/// 一组符号；`id` 就是 CoreGlyphs 的 key，两个合成分组除外。
struct SymbolCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    /// 选择性推荐符号分组。
    static let suggested = SymbolCategory(id: "gearmac.suggested", title: "Suggested")
    /// 全部符号分组。
    static let all = SymbolCategory(id: "gearmac.all", title: "All Symbols")
    /// GearMac 自带符号分组。
    static let bundled = SymbolCategory(id: "gearmac.bundled", title: "GearMac")
}

/// 运行时从 `CoreGlyphs.bundle` 读取；每次读取都是可选的，并带有策展回退。
struct SymbolCatalog: Sendable {
    let symbols: [String]
    let categories: [SymbolCategory]

    private let byCategory: [String: [String]]
    private let searchTerms: [String: [String]]

    /// 自带图标：系统根本没有 bluetooth 符号（无论是限制还是其他原因）。
    static let bundledGlyphs = ["bluetooth", "BrandGitHub", "BrandDiscord", "BrandX"]

    /// 判断某个符号是否为 GearMac 自带图标。
    static func isBundled(_ symbol: String) -> Bool { bundledGlyphs.contains(symbol) }

    /// 应用自带图标的搜索词，因为它们不带任何 CoreGlyphs 元数据。
    private nonisolated static let bundledTerms: [String: [String]] = [
        "bluetooth": ["bluetooth", "wireless", "pair", "device"],
        "BrandGitHub": ["github", "git", "repository", "code", "brand"],
        "BrandDiscord": ["discord", "chat", "community", "brand"],
        "BrandX": ["x", "twitter", "social", "brand"]
    ]

    /// 选择器默认展示的内容：滚动八千个图标绝不是选图标的办法。
    static let suggested =
        bundledGlyphs + [
            // 状态与电源
            "bolt.fill", "cup.and.saucer.fill", "moon.fill", "sun.max.fill", "power", "battery.100",
            "eye.fill", "bell.fill", "sparkles", "wand.and.stars",
            // 时间
            "calendar", "clock.fill", "timer", "hourglass", "alarm.fill",
            // 文本与文档
            "doc.text.fill", "text.alignleft", "checklist", "list.bullet", "note.text",
            "folder.fill", "tray.full.fill", "archivebox.fill", "book.fill", "bookmark.fill",
            // 通讯
            "envelope.fill", "message.fill", "paperplane.fill", "phone.fill", "video.fill",
            "person.2.fill", "bubble.left.and.bubble.right.fill",
            // 媒体
            "music.note", "speaker.wave.2.fill", "headphones", "photo.fill", "camera.fill",
            "play.fill", "pause.fill", "paintbrush.fill", "theatermasks.fill",
            // 开发者
            "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill",
            "wrench.and.screwdriver.fill", "ant.fill", "cpu", "memorychip", "externaldrive.fill",
            "server.rack", "shippingbox.fill",
            // 系统与网络
            "gearshape.fill", "slider.horizontal.3", "network", "globe", "link", "wifi",
            "display", "keyboard", "cursorarrow.rays", "square.grid.2x2.fill",
            // 安全与金融
            "lock.fill", "key.fill", "shield.fill", "creditcard.fill", "cart.fill", "banknote.fill",
            // 数据
            "chart.bar.fill", "chart.pie.fill", "function", "number", "brain",
            // 地点与事物
            "star.fill", "heart.fill", "flag.fill", "tag.fill", "map.fill", "location.fill",
            "airplane", "car.fill", "leaf.fill", "flame.fill", "drop.fill", "snowflake",
            "cloud.fill", "gift.fill", "trash.fill", "arrow.triangle.2.circlepath"
        ]

    /// 仅策展集合：既作为回退，也是真实目录加载完成前选择器展示的内容。
    static let fallback = SymbolCatalog(
        symbols: suggested.filter {
            isBundled($0) || NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        },
        categories: [.suggested, .bundled],
        byCategory: [:],
        searchTerms: [:])

    /// 读取并过滤系统目录。不在主 actor 上执行：它会解析约 700 KB 的 plist。
    nonisolated static func load() -> SymbolCatalog {
        let base = URL(
            fileURLWithPath:
                "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

        func plist<T>(_ name: String, as type: T.Type) -> T? {
            guard let data = try? Data(contentsOf: base.appendingPathComponent(name)),
                let value = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil)
            else { return nil }
            return value as? T
        }

        guard let order = plist("symbol_order.plist", as: [String].self), !order.isEmpty else {
            return fallback
        }
        // Apple 为自己产品保留了约 600 个符号；用它们做标注属于误用该商标。
        let restricted = Set(
            (plist("symbol_restrictions.strings", as: [String: String].self) ?? [:]).keys)
        let categoriesBySymbol = plist("symbol_categories.plist", as: [String: [String]].self) ?? [:]
        let search = plist("symbol_search.plist", as: [String: [String]].self) ?? [:]

        let systemSymbols = order.filter { !restricted.contains($0) && !isLocaleVariant($0) }
        guard !systemSymbols.isEmpty else { return fallback }
        // 应用自带图标排在最前，使系统缺失的图标成为最先被提供的一项。
        let symbols = bundledGlyphs + systemSymbols

        var byCategory: [String: [String]] = [:]
        for symbol in symbols {
            for category in categoriesBySymbol[symbol] ?? [] where categoryTitles[category] != nil {
                byCategory[category, default: []].append(symbol)
            }
        }
        // 采用 Apple 自己的顺序，跳过那些描述渲染模式而不是主题的分组。
        let ordered = (plist("categories.plist", as: [[String: String]].self) ?? [])
            .compactMap { $0["key"] }
            .filter { byCategory[$0]?.isEmpty == false }
            .compactMap { key in categoryTitles[key].map { SymbolCategory(id: key, title: $0) } }

        return SymbolCatalog(
            symbols: symbols,
            categories: [.suggested, .bundled, .all] + ordered,
            byCategory: byCategory,
            searchTerms: search.merging(bundledTerms) { system, _ in system })
    }

    /// 返回指定分类下的符号。
    func symbols(in category: SymbolCategory) -> [String] {
        switch category.id {
        case SymbolCategory.suggested.id: return Self.suggested
        case SymbolCategory.bundled.id: return Self.bundledGlyphs
        case SymbolCategory.all.id: return symbols
        default: return byCategory[category.id] ?? []
        }
    }

    /// 每个词都必须命中符号名或搜索词，因此 "coffee" 能找到 `cup.and.saucer`。
    func search(_ query: String, in category: SymbolCategory) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." })
        guard !words.isEmpty else { return symbols(in: category) }
        // 搜索就是搜索：除非用户限定了分类，否则会遍历全部符号。
        let pool = category.id == SymbolCategory.suggested.id ? symbols : symbols(in: category)
        return pool.filter { symbol in
            let haystack = symbol.replacingOccurrences(of: ".", with: " ")
            return words.allSatisfy { word in
                haystack.contains(word)
                    || (searchTerms[symbol] ?? []).contains { $0.lowercased().contains(word) }
            }
        }
    }

    /// 已存在符号的本地化变体：上千个近似重复，在这里全是噪声。
    private nonisolated static func isLocaleVariant(_ symbol: String) -> Bool {
        let suffixes: Set<String> = [
            "ar", "he", "hi", "ja", "ko", "th", "zh", "my", "km", "mn", "ne", "si", "ta", "te",
            "kn", "ml", "gu", "pa", "or", "bn", "ur", "am", "el", "ru", "sr", "rtl", "ltr"
        ]
        return symbol.split(separator: ".").contains { suffixes.contains(String($0)) }
    }

    /// 不在表中的都是渲染模式分组，不是可浏览的主题。
    private nonisolated static let categoryTitles: [String: String] = [
        "communication": "Communication", "weather": "Weather", "maps": "Maps",
        "objectsandtools": "Objects & Tools", "devices": "Devices",
        "cameraandphotos": "Camera & Photos", "gaming": "Gaming",
        "connectivity": "Connectivity", "transportation": "Transportation",
        "automotive": "Automotive", "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security", "human": "People", "home": "Home",
        "fitness": "Fitness", "nature": "Nature", "editing": "Editing",
        "textformatting": "Text Formatting", "media": "Media", "keyboard": "Keyboard",
        "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
        "arrows": "Arrows", "indices": "Indices", "math": "Math"
    ]
}
