// 文件职责：定义启动器的两种排序（带查询的相关度排序与空查询的 frecency 排序）及其决胜规则，保持纯函数以便测试。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 启动器的两种排序方式，保持纯函数以便测试用例直接对其排序。
enum LauncherOrder {
    /// 每轮排序只折叠一次，同时提供字段比较所需的两种形式。
    struct Query: Sendable {
        /// 标题、副标题、关键字与搜索词都按拉丁读法比较。
        let latin: SearchText
        /// 备选标题与别名按用户原样输入的文本比较。
        let typed: SearchText
        let term: String

        var isEmpty: Bool { typed.isEmpty }

        /// 把原始输入去掉首尾空白后，分别折叠为拉丁读法与输入原形。
        init(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            latin = SearchText(trimmed, transliterated: true)
            typed = SearchText(trimmed, transliterated: false)
            term = typed.string
        }
    }

    /// 单个条目参与排序的全部信号：别名、使用记录、类别优先级与标题等。
    struct Signals: Sendable {
        var alias: SearchText?
        var usage: LauncherUsage
        /// 完全相同时哪一类胜出；数值越高越靠前。
        var priority: Int
        var title: String
        /// 在这些查询下该条目优先，直到用户更多次打开竞争项为止。
        var boostedTerms: Set<String> = []
    }

    /// 对带查询的列表排序：过滤不匹配项后按相关度排序，并截断到 `limit`。
    static func ranked<Item>(
        _ items: [Item], query: Query, sensitivity: SearchSensitivity, limit: Int,
        profile: (Item) -> SearchProfile, signals: (Item) -> Signals
    ) -> [Item] {
        guard !query.isEmpty else { return [] }
        let scored = items.enumerated().compactMap { position, item -> (Item, Candidate)? in
            let signals = signals(item)
            guard
                let facts = Facts(
                    profile: profile(item), signals: signals, query: query, sensitivity: sensitivity)
            else { return nil }
            return (item, Candidate(facts: facts, signals: signals, position: position))
        }
        let length = query.latin.units.count
        return
            scored
            .sorted { orders($0.1, before: $1.1, length: length) }
            .prefix(limit)
            .map(\.0)
    }

    /// 空查询列表：先按 frecency 从高到低，再是有别名的条目，最后按类别与名称排序。
    static func byUsage<Item>(_ items: [Item], signals: (Item) -> Signals) -> [Item] {
        items.enumerated()
            .map { ($0.element, Candidate(facts: nil, signals: signals($0.element), position: $0.offset)) }
            .sorted {
                let order = tiebreak($0.1, $1.1)
                return order != 0 ? order < 0 : $0.1.position < $1.1.position
            }
            .map(\.0)
    }

    // MARK: - One entry's match

    /// 已计算好事实的排序候选：`facts` 为 nil 表示不做查询相关度比较。
    private struct Candidate {
        let facts: Facts?
        let signals: Signals
        let position: Int
    }

    /// 别名与查询的关系：无命中、前缀命中或完全相等。
    private enum AliasHit: Equatable {
        case none
        case prefix
        case exact
    }

    /// 历史搜索词与查询的关系；`length` 为已存储词的长度。
    private enum TermHit: Equatable {
        case none
        case exact(length: Int)
        case prefix(length: Int)
        case overbounds(length: Int)

        var strength: Int {
            switch self {
            case .none: 0
            case .overbounds: 1
            case .prefix: 2
            case .exact: 3
            }
        }

        var isExact: Bool { if case .exact = self { true } else { false } }
        var isPrefix: Bool { if case .prefix = self { true } else { false } }

        /// 达到该长度的已存词足够具体，可以重排更长的查询结果。
        var isLongOverbounds: Bool {
            if case .overbounds(let length) = self { length >= LauncherOrder.overboundsFloor } else { false }
        }
    }

    /// 条目完全不匹配时为 nil。
    private struct Facts {
        let alias: AliasHit
        let isBoosted: Bool
        let titleExact: Bool
        /// 标题与备选标题中的最优值；完全命中为 `Int.max`。
        let title: Int
        let titlePrefix: Bool
        let subtitleExact: Bool
        let subtitle: Int
        let term: TermHit

        init?(profile: SearchProfile, signals: Signals, query: Query, sensitivity: SearchSensitivity) {
            let latinLength = query.latin.units.count
            let typedLength = query.typed.units.count
            alias = signals.alias.map { Self.aliasHit($0, query.typed) } ?? .none
            isBoosted = signals.boostedTerms.contains(query.term)
            let titleMatch = LauncherMatch.match(query.latin, in: profile.title)
            var alternateTitles = profile.alternateTitles
            if alias == .none, let text = signals.alias { alternateTitles.append(text) }
            let alternates = alternateTitles.map { LauncherMatch.match(query.typed, in: $0) }
            let subtitleMatch = profile.subtitle.flatMap { LauncherMatch.match(query.latin, in: $0) }

            func passes(_ outcome: LauncherMatch.Outcome?, _ length: Int) -> Bool {
                outcome.map { sensitivity.accepts($0, queryLength: length) } ?? false
            }
            let isMatching =
                alias != .none || passes(titleMatch, latinLength)
                || alternates.contains { passes($0, typedLength) } || passes(subtitleMatch, latinLength)
                || profile.keywords.contains {
                    passes(LauncherMatch.match(query.latin, in: $0), latinLength)
                }
            guard isMatching else { return nil }

            titleExact = titleMatch == .exact || alternates.contains { $0 == .exact }
            title = alternates.reduce(Self.value(titleMatch)) { max($0, Self.value($1)) }
            titlePrefix =
                profile.title.units.starts(with: query.latin.units)
                || alternateTitles.contains { $0.units.starts(with: query.typed.units) }
            subtitleExact = subtitleMatch == .exact
            subtitle = Self.value(subtitleMatch)
            term = Self.termHit(signals.usage.searchTerms, query.latin.units)
        }

        /// 未命中的排序低于任何对齐结果。
        private static func value(_ outcome: LauncherMatch.Outcome?) -> Int {
            outcome?.value ?? .min
        }

        /// 前缀命中要求别名中仍有部分内容未被输入。
        private static func aliasHit(_ alias: SearchText, _ query: SearchText) -> AliasHit {
            let a = alias.units
            let q = query.units
            if a.count > q.count { return a.starts(with: q) ? .prefix : .none }
            return a == q ? .exact : .none
        }

        /// 最新的词优先：完全命中直接胜出，其次是最近的前缀命中。
        private static func termHit(_ terms: [String], _ query: [UInt16]) -> TermHit {
            var best = TermHit.none
            for term in terms.reversed() {
                let stored = Array(term.utf16)
                guard !stored.isEmpty else { continue }
                if stored.count > query.count {
                    guard stored.starts(with: query) else { continue }
                    if !best.isPrefix { best = .prefix(length: stored.count) }
                } else if stored.count == query.count {
                    if stored == query { return .exact(length: stored.count) }
                } else if query.starts(with: stored) {
                    let extra = query.count - stored.count
                    guard extra <= LauncherOrder.overboundsReach else { continue }
                    switch best {
                    case .none: best = .overbounds(length: stored.count)
                    case .overbounds(let length) where stored.count > length:
                        best = .overbounds(length: stored.count)
                    default: break
                    }
                }
            }
            return best
        }
    }

    /// 查询在已存词之外最多可多出的字符数，仍会被视为该词。
    private static let overboundsReach = 3
    /// 已存词至少达到该长度，才允许“多出字符”的判定生效。
    private static let overboundsFloor = 3

    // MARK: - The comparator

    /// 先取比较结果，相同则回退到列表中的原始位置。
    private static func orders(_ a: Candidate, before b: Candidate, length: Int) -> Bool {
        let order = compare(a, b, length: length)
        return order != 0 ? order < 0 : a.position < b.position
    }

    /// 负值表示 `a` 在前；第一条能区分两者的规则即决定顺序。
    private static func compare(_ a: Candidate, _ b: Candidate, length: Int) -> Int {
        guard let x = a.facts, let y = b.facts else { return tiebreak(a, b) }
        if x.alias != y.alias, x.alias == .exact || y.alias == .exact {
            return x.alias == .exact ? -1 : 1
        }
        if x.isBoosted != y.isBoosted {
            let (boosted, other) = x.isBoosted ? (a, b) : (b, a)
            let used = other.signals.usage.frecency
            if !(used > 1 && used > boosted.signals.usage.frecency) { return x.isBoosted ? -1 : 1 }
        }
        if length > 3, x.titleExact || y.titleExact {
            guard x.titleExact, y.titleExact else { return x.titleExact ? -1 : 1 }
            return first(termStrength(x.term, y.term), frecency(a, b)) ?? tiebreak(a, b)
        }
        if x.term.isExact || y.term.isExact {
            guard x.term.isExact, y.term.isExact else { return x.term.isExact ? -1 : 1 }
            return first(frecency(a, b)) ?? tiebreak(a, b)
        }
        if x.subtitleExact || y.subtitleExact {
            guard x.subtitleExact, y.subtitleExact else { return x.subtitleExact ? -1 : 1 }
            return first(frecency(a, b), descending(x.title, y.title)) ?? tiebreak(a, b)
        }
        if (x.alias == .prefix) != (y.alias == .prefix) { return x.alias == .prefix ? -1 : 1 }
        if x.term.isPrefix != y.term.isPrefix { return x.term.isPrefix ? -1 : 1 }
        if x.term != .none, y.term != .none {
            if x.term.isPrefix, y.term.isPrefix, let order = first(frecency(a, b)) { return order }
            if case .overbounds(let left) = x.term, case .overbounds(let right) = y.term, left != right,
                left >= overboundsFloor || right >= overboundsFloor
            {
                return descending(left, right)
            }
            if x.term.isLongOverbounds != y.term.isLongOverbounds { return x.term.isLongOverbounds ? -1 : 1 }
        }
        if x.term.isLongOverbounds, y.term == .none { return -1 }
        if y.term.isLongOverbounds, x.term == .none { return 1 }
        let order = first(
            descending(max(x.title, x.subtitle), max(y.title, y.subtitle)), frecency(a, b),
            descending(x.title, y.title), descending(x.titlePrefix, y.titlePrefix),
            descending(a.signals.priority, b.signals.priority))
        return order ?? collate(a, b)
    }

    /// 查询无法区分两个条目时用于决胜的规则。
    private static func tiebreak(_ a: Candidate, _ b: Candidate) -> Int {
        let aliased = descending(a.signals.alias != nil, b.signals.alias != nil)
        return first(frecency(a, b), aliased, descending(a.signals.priority, b.signals.priority))
            ?? collate(a, b)
    }

    private static func termStrength(_ x: TermHit, _ y: TermHit) -> Int {
        if x.strength != y.strength { return descending(x.strength, y.strength) }
        if case .overbounds(let left) = x, case .overbounds(let right) = y { return descending(left, right) }
        return 0
    }

    private static func frecency(_ a: Candidate, _ b: Candidate) -> Int {
        descending(a.signals.usage.frecency, b.signals.usage.frecency)
    }

    /// 按数字与大小写无关比较：`Item 2` 排在 `Item 10` 之前。
    private static func collate(_ a: Candidate, _ b: Candidate) -> Int {
        switch a.signals.title.localizedStandardCompare(b.signals.title) {
        case .orderedAscending: -1
        case .orderedDescending: 1
        case .orderedSame: 0
        }
    }

    private static func descending<Value: Comparable>(_ left: Value, _ right: Value) -> Int {
        left == right ? 0 : (left > right ? -1 : 1)
    }

    private static func descending(_ left: Bool, _ right: Bool) -> Int {
        left == right ? 0 : (left ? -1 : 1)
    }

    private static func first(_ orders: Int...) -> Int? {
        orders.first { $0 != 0 }
    }
}
