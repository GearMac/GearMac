// 文件职责：统一决定一个条目可被搜索到的名称集合（名称、备选标题、副标题、关键字），并产出折叠后的 `SearchProfile`。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 统一决定条目可搜索名称的唯一位置，对所有条目类型一视同仁。
enum EntryNaming {
    /// 生产者所掌握的、关于其条目名称的全部信息。
    struct Sources: Sendable, Hashable {
        var name: String
        /// 与标题一同参与排序：翻译名、重命名后的文件、代码片段关键字。
        var alternateTitles: [String] = []
        /// 条目的来源，展示在其旁边：例如扩展的标题。
        var subtitle: String?
        /// 仅用于被搜索命中，不参与排序：如声明的名称、扩展的关键字。
        var keywords: [String] = []

        init(name: String) { self.name = name }
    }

    /// 由名称等原始信息构建出折叠后的搜索档案，是评分所读的唯一名称来源。
    static func profile(for sources: Sources) -> SearchProfile {
        let title = SearchText(sources.name, transliterated: true)
        // 仅折叠不做音译：这些要与用户原样输入的查询比较。
        let alternates = usable(sources.alternateTitles, rejecting: [sources.name])
            .map { SearchText($0, transliterated: false) }
        let subtitle = sources.subtitle
            .map { SearchText($0, transliterated: true) }
            .flatMap { $0.isEmpty || $0.units == title.units ? nil : $0 }
        var keywords = usable(sources.keywords, rejecting: [sources.name] + sources.alternateTitles)
            .map { SearchText($0, transliterated: true) }
        if let subtitle { keywords += [title.joined(with: subtitle), subtitle.joined(with: title)] }
        return SearchProfile(
            title: title, alternateTitles: alternates, subtitle: subtitle, keywords: keywords)
    }

    /// 去掉 `.app` 后缀，使应用名与用户认知中的名称一致。
    static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Info.plist 的列表会重复名称，并带有 `ALTERNATE_NAME_1` 之类的占位符。
    static func usable(_ raw: [String], rejecting existing: [String]) -> [String] {
        var seen = Set(existing.map { FuzzyMatch.normalized(strippingAppExtension($0)) })
        return raw.compactMap { candidate in
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return nil }
            let key = FuzzyMatch.normalized(strippingAppExtension(name))
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return name
        }
    }

    /// 单独的 SCREAMING_SNAKE 形式词元是未翻译的占位符，正式版里也带有若干。
    private static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && !name.contains(where: { $0.isLowercase || $0.isWhitespace })
    }
}

/// 仅由 `EntryNaming.profile` 构建。
struct SearchProfile: Sendable, Hashable {
    var title: SearchText
    var alternateTitles: [SearchText]
    var subtitle: SearchText?
    /// 仅用于命中展示，不参与排序。
    var keywords: [SearchText]

    /// 条目在首次索引前持有的内容：没有任何查询能命中。
    static let unnamed = SearchProfile(
        title: SearchText(units: []), alternateTitles: [], subtitle: nil, keywords: [])
}
