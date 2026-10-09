// 文件职责：定义表情/符号选择器的领域模型，包括分类、分类筛选、网格缩放与列数、肤色以及词条结构，并提供生成数据集与本地化关键词的解析。
// 分层：Model；纯值类型与纯函数，不依赖 AppKit/SwiftUI，也不做磁盘读取。
import Foundation

/// 网格分区的展示顺序；raw value 是生成数据集使用的紧凑编码。
enum EmojiCategory: String, CaseIterable, Sendable {
    case smileysAndPeople = "sp"
    case animalsAndNature = "an"
    case foodAndDrink = "fd"
    case activity = "ac"
    case travelAndPlaces = "tp"
    case objects = "ob"
    case symbols = "sy"
    case flags = "fl"
    case arrows = "xa"
    case currency = "xc"
    case math = "xm"
    case shapesAndPunctuation = "xs"
    case cjk = "xj"
    case keysAndTechnical = "xk"

    /// 分区标题。
    var title: String {
        switch self {
        case .smileysAndPeople: return "Smileys & People"
        case .animalsAndNature: return "Animals & Nature"
        case .foodAndDrink: return "Food & Drink"
        case .activity: return "Activity"
        case .travelAndPlaces: return "Travel & Places"
        case .objects: return "Objects"
        case .symbols: return "Symbols"
        case .flags: return "Flags"
        case .arrows: return "Arrows"
        case .currency: return "Currency"
        case .math: return "Math"
        case .shapesAndPunctuation: return "Shapes & Punctuation"
        case .cjk: return "CJK Symbols"
        case .keysAndTechnical: return "Keys & Technical"
        }
    }

    /// 分区图标使用的 SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .smileysAndPeople: "face.smiling"
        case .animalsAndNature: "pawprint"
        case .foodAndDrink: "pizza.slice"
        case .activity: "gamecontroller"
        case .travelAndPlaces: "paperplane"
        case .objects: "lightbulb"
        case .symbols: "number.sign"
        case .flags: "flag"
        case .arrows: "arrow.up.right"
        case .currency: "dollarsign"
        case .math: "squareroot"
        case .shapesAndPunctuation: "triangle"
        case .cjk: "globe"
        case .keysAndTechnical: "command"
        }
    }

    /// 在 Actions 中给选中字符的命名；Unicode 后面的几类属于符号集合。
    /// 英文命名保留给尚未迁移的调用点与测试，界面请改用 `localizedItemTitle(_:)`。
    var itemTitle: String {
        switch self {
        case .symbols, .arrows, .currency, .math, .shapesAndPunctuation, .cjk,
            .keysAndTechnical:
            "Symbol"
        default:
            "Emoji"
        }
    }

    /// 按界面语言给出的分类标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: EmojiKey =
            switch self {
            case .smileysAndPeople: .categorySmileysAndPeople
            case .animalsAndNature: .categoryAnimalsAndNature
            case .foodAndDrink: .categoryFoodAndDrink
            case .activity: .categoryActivity
            case .travelAndPlaces: .categoryTravelAndPlaces
            case .objects: .categoryObjects
            case .symbols: .categorySymbols
            case .flags: .categoryFlags
            case .arrows: .categoryArrows
            case .currency: .categoryCurrency
            case .math: .categoryMath
            case .shapesAndPunctuation: .categoryShapesAndPunctuation
            case .cjk: .categoryCJK
            case .keysAndTechnical: .categoryKeysAndTechnical
            }
        return L10n.string(key, language: language)
    }

    /// 按界面语言给出的动作名词（表情/符号）。
    func localizedItemTitle(_ language: AppLanguage) -> String {
        L10n.string(
            itemTitle == "Symbol" ? EmojiKey.nounSymbol : EmojiKey.nounEmoji, language: language)
    }
}

/// 选择器当前展示哪个分区；`.all` 保留整个目录的完整有序概览。
enum EmojiCategoryFilter: Hashable, Sendable {
    case all
    case pinned
    case frequentlyUsed
    case category(EmojiCategory)

    /// 全部筛选项：全部/已固定/常用在前，后接各分类。
    static let allCases: [Self] =
        [.all, .pinned, .frequentlyUsed] + EmojiCategory.allCases.map(Self.category)

    /// 筛选项标题（英文）；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .all: "All Categories"
        case .pinned: "Pinned"
        case .frequentlyUsed: "Frequently Used"
        case .category(let category): category.title
        }
    }

    /// 按界面语言给出的筛选项标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .all: return L10n.string(EmojiKey.filterAll, language: language)
        case .pinned: return L10n.string(EmojiKey.filterPinned, language: language)
        case .frequentlyUsed: return L10n.string(EmojiKey.filterFrequentlyUsed, language: language)
        case .category(let category): return category.localizedTitle(language)
        }
    }

    /// 筛选项图标使用的 SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .all: "square.grid.3x3.square"
        case .pinned: "pin"
        case .frequentlyUsed: "clock"
        case .category(let category): category.systemImage
        }
    }
}

/// ⌘0 / ⌘+ / ⌘-：放大后单元格更少、更大。
enum EmojiGridZoom: Sendable {
    case actualSize
    case zoomIn
    case zoomOut
}

/// 用户可选的网格密度。缩放只影响当前选择器会话。
enum EmojiGridColumns: Int, CaseIterable, Identifiable, Sendable {
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10

    static let `default`: Self = .eight

    var id: Int { rawValue }

    /// 按界面语言给出的列数标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        String(format: L10n.string(EmojiKey.settingsColumnsFormat, language: language), rawValue)
    }

    /// 缩放无变化时返回 nil：已在默认列数，或已在六列或十列。
    func applying(_ zoom: EmojiGridZoom, default defaultColumns: Self) -> Self? {
        let next: Self? =
            switch zoom {
            case .actualSize: defaultColumns
            case .zoomIn: Self(rawValue: rawValue - 1)
            case .zoomOut: Self(rawValue: rawValue + 1)
            }
        return next == self ? nil : next
    }
}

/// Fitzpatrick 肤色偏好；`modifier` 是追加到支持肤色表情后的标量。
enum EmojiSkinTone: String, CaseIterable, Identifiable, Sendable {
    case none, light, mediumLight, medium, mediumDark, dark

    var id: String { rawValue }

    /// 对应肤色修饰符标量；默认肤色为 nil。
    var modifier: Unicode.Scalar? {
        switch self {
        case .none: return nil
        case .light: return Unicode.Scalar(0x1F3FB)
        case .mediumLight: return Unicode.Scalar(0x1F3FC)
        case .medium: return Unicode.Scalar(0x1F3FD)
        case .mediumDark: return Unicode.Scalar(0x1F3FE)
        case .dark: return Unicode.Scalar(0x1F3FF)
        }
    }

    /// 肤色标题（英文）；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .none: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium Dark"
        case .dark: return "Dark"
        }
    }

    /// 按界面语言给出的肤色标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: EmojiKey =
            switch self {
            case .none: .toneDefault
            case .light: .toneLight
            case .mediumLight: .toneMediumLight
            case .medium: .toneMedium
            case .mediumDark: .toneMediumDark
            case .dark: .toneDark
            }
        return L10n.string(key, language: language)
    }

    /// 选择器色标：用该肤色渲染的挥手手势。
    var sample: String { EmojiCatalog.applyTone(self, to: "👋") }
}

/// 一个表情或符号；`glyph` 是基础（未着色）形式，同时充当 ID。
struct EmojiEntry: Identifiable, Hashable, Sendable {
    let glyph: String
    let name: String
    let category: EmojiCategory
    let supportsSkinTone: Bool
    let keywords: String  // 以逗号连接的关键词；大多数符号为空

    var id: String { glyph }
    /// 首字母大写的展示名称。
    var displayName: String { name.capitalized }

    /// 按指定肤色渲染；不支持肤色或默认肤色时返回基础字形。
    func display(tone: EmojiSkinTone) -> String {
        guard supportsSkinTone, tone != .none else { return glyph }
        return EmojiCatalog.applyTone(tone, to: glyph)
    }
}

/// 表情目录的组装与查询入口。
enum EmojiCatalog {
    /// 基础标量 + 肤色修饰符；会剔除 VS16，因为修饰符本身已足以构成 emoji（UTS #51）。
    static func applyTone(_ tone: EmojiSkinTone, to glyph: String) -> String {
        guard let modifier = tone.modifier else { return glyph }
        var scalars = String.UnicodeScalarView(glyph.unicodeScalars.filter { $0.value != 0xFE0F })
        scalars.append(modifier)
        return String(scalars)
    }

    /// 解析生成的 `glyph|name|category|tone|keywords` 记录，跳过格式不完整的行。
    nonisolated static func parse(_ raw: String, localized: [String] = []) -> [EmojiEntry] {
        let localizedTerms = terms(in: localized)
        var result: [EmojiEntry] = []
        result.reserveCapacity(2200)
        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, let category = EmojiCategory(rawValue: String(fields[2]))
            else { continue }
            let glyph = String(fields[0])
            var keywords = String(fields[4])
            for pack in localizedTerms[glyph] ?? [] {
                if !keywords.isEmpty { keywords += "," }
                keywords += pack
            }
            result.append(
                EmojiEntry(
                    glyph: glyph, name: String(fields[1]), category: category,
                    supportsSkinTone: fields[3] == "1", keywords: keywords))
        }
        return result
    }

    /// 把各语言包展开为「字形 -> 关键词列表」的索引。
    private nonisolated static func terms(in packs: [String]) -> [String: [Substring]] {
        var result: [String: [Substring]] = [:]
        for pack in packs {
            for line in pack.split(separator: "\n") {
                let fields = line.split(separator: "|", maxSplits: 1)
                guard fields.count == 2 else { continue }
                result[String(fields[0]), default: []].append(fields[1])
            }
        }
        return result
    }

    /// 按 Mac 可读语言各取一个语言包；"en" 是目录本身，也是匹配器无匹配时的答案。
    nonisolated static func keywordLanguages(available: [String], preferred: [String]) -> [String] {
        let candidates = ["en"] + available
        var result: [String] = []
        for language in preferred {
            guard
                let match = Bundle.preferredLocalizations(
                    from: candidates, forPreferences: [language]
                ).first,
                match != "en", !result.contains(match)
            else { continue }
            result.append(match)
        }
        return result
    }
}
