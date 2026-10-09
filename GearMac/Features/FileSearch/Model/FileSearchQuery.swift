// 文件职责：构造 Spotlight 查询表达式（关键词匹配、类型筛选、忽略排除、最近打开），并对候选结果做模糊评分排序与路径排除判定。
// 分层：Model；纯字符串与数据计算，不直接执行查询。
import Foundation

/// 构造 Spotlight 表达式、排序候选与排除路径的纯逻辑集合。
enum FileSearchQuery {
    static let candidateLimit = 1_000
    static let resultLimit = 200
    /// 空白屏是候选清单而非浏览器：提供足够的行以便点选，但不需要长距离滚动。
    static let recentLimit = 20

    /// 将查询按空白切分为词项。
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    /// 由关键词、类型筛选与忽略排除拼出 Spotlight 查询表达式；查询为空时返回 nil。
    static func expression(
        for query: String, excluding exclusions: [String] = [], filter: FileSearchFilter = .all
    ) -> String? {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return nil }
        let matches = terms.map { "kMDItemFSName == \"*\(escape($0))*\"cd" }
        // 在谓词中排除，避免被忽略的文件占用候选数量上限。
        let excludes = exclusions.map { "kMDItemFSName != \"\(escapeGlob($0))\"cd" }
        let types = filter.spotlightClause.map { [$0] } ?? []
        return (matches + types + excludes).joined(separator: " && ")
    }

    /// 两者都要：因为现在 macOS 很少在打开时写入 `kMDItemLastUsedDate`，而 Spotlight 只能按单个属性排序。
    enum RecentStamp: String, CaseIterable, Sendable {
        case changed = "kMDItemFSContentChangeDate"
        case used = "kMDItemLastUsedDate"

        /// 使用 Spotlight 自身的字面时间表达式，因此无需注入时钟；编辑更频繁，所以时间窗更短。
        var window: String {
            switch self {
            case .changed: return "$time.now(-259200)"
            case .used: return "$time.now(-2592000)"
            }
        }
    }

    /// 构造「最近使用」查询表达式，按给定的时间戳属性过滤。
    static func recentExpression(
        stamp: RecentStamp, excluding exclusions: [String] = [], filter: FileSearchFilter = .all
    ) -> String {
        let touched = "\(stamp.rawValue) > \(stamp.window)"
        let types = filter.spotlightClause.map { [$0] } ?? []
        let excludes = exclusions.map { "kMDItemFSName != \"\(escapeGlob($0))\"cd" }
        return ([touched] + types + excludes).joined(separator: " && ")
    }

    /// 按模糊评分对结果排序（整体查询优先，词项得分次之，最后按名称/路径字母序），并截断到结果上限。
    static func rank(
        _ results: [FileSearchResult], for query: String, ignoring ignore: FileSearchIgnoreList
    ) -> [FileSearchResult] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }
        // 各自只折叠一次：否则上千个候选会对每条结果重复折叠每个词项。
        let whole = FuzzyMatch.Query(query)
        let folded = terms.map(FuzzyMatch.Query.init)
        return results.filter { !isExcludedPath($0.id, ignoring: ignore) }.map { result in
            let full = FuzzyMatch.score(whole, candidate: result.name)
            let termScore = folded.compactMap { FuzzyMatch.score($0, candidate: result.name) }
                .reduce(0, +)
            return (result, full, termScore)
        }
        .sorted { left, right in
            switch (left.1, right.1) {
            case let (leftScore?, rightScore?) where leftScore != rightScore:
                return leftScore > rightScore
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if left.2 != right.2 { return left.2 > right.2 }
                let nameOrder = left.0.name.localizedCaseInsensitiveCompare(right.0.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return left.0.id.localizedCaseInsensitiveCompare(right.0.id) == .orderedAscending
            }
        }
        .prefix(resultLimit)
        .map(\.0)
    }

    /// 判断文件名是否包含查询的所有词项（忽略大小写与变音符号）。
    static func matches(filename: String, query: String) -> Bool {
        terms(in: query).allSatisfy { term in
            filename.range(
                of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// 隐藏路径与包（bundle）内部内容被排除，正是「搜索文件」无需额外权限的原因。
    static func isExcludedPath(_ path: String, ignoring ignore: FileSearchIgnoreList) -> Bool {
        let structural = path.split(separator: "/").contains { component in
            (component.hasPrefix(".") && component != "." && component != "..")
                || component.lowercased().hasSuffix(".app")
        }
        return structural || ignore.excludes(path: path)
    }

    /// 用户输入的词项按字面处理，因此通配符会与字符串定界符一起被转义。
    private static func escape(_ term: String) -> String {
        quoting(term, escaping: ["\\", "\"", "*", "?"])
    }

    /// 用户的模式保留 `*`，因为这是 Spotlight 唯一会求值的通配符。
    private static func escapeGlob(_ pattern: String) -> String {
        quoting(pattern, escaping: ["\\", "\""])
    }

    private static func quoting(_ text: String, escaping characters: Set<Character>) -> String {
        var escaped = ""
        for character in text {
            if characters.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
