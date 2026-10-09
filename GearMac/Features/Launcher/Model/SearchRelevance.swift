// 文件职责：提供通用的模糊匹配原语（`FuzzyMatch` 折叠与分层匹配、`SearchAlias`/`SearchFields` 字段模型）以及菜单项与窗口搜索的相关度单元格打分（`SearchRelevance`）。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 通用模糊匹配：把查询与候选统一折叠后按层级（完全、前缀、词首、子串、子序列）匹配并打分。
enum FuzzyMatch {
    /// 匹配层级，从最强（完全相等）到最弱（子序列）。
    enum Tier: Sendable {
        case exact
        case prefix
        case wordStart
        case substring
        case subsequence
    }

    /// 一次具体匹配：层级、位置与长度几何。
    struct Match: Sendable {
        let tier: Tier
        /// 命中在候选中开始的位置（按字符计）；两个锚定层级均为 0。
        let offset: Int
        let queryLength: Int
        let candidateLength: Int
        /// 子序列遍历的原始加分总和；所有字面层级为 0。
        let spread: Int

        /// 供只对单个字段排序、无需权衡角色的调用方使用的一种排序值。
        var score: Int { FuzzyMatch.rawScore(self) }
    }

    /// 只折叠一次的查询，避免排序时为每个候选字段重复折叠。
    struct Query: Sendable {
        fileprivate let text: String
        /// 同样只折叠一次：子序列遍历需要对每个候选随机访问。
        fileprivate let characters: [Character]
        var isEmpty: Bool { text.isEmpty }

        init(_ raw: String) {
            text = FuzzyMatch.normalized(raw)
            characters = Array(text)
        }
    }

    /// 只折叠一次的候选，供索引用同一文本与每个查询匹配。
    struct Candidate: Sendable {
        let text: String
        fileprivate let length: Int

        init(_ raw: String) {
            text = FuzzyMatch.normalized(raw)
            length = text.count
        }
    }

    /// 查询命中候选所处的层级，附带 `SearchRelevance.shape` 需要的几何信息。
    static func match(query: String, candidate: String) -> Match? {
        match(Query(query), candidate: candidate)
    }

    static func match(_ query: Query, candidate: String) -> Match? {
        match(query, candidate: Candidate(candidate))
    }

    static func match(_ query: Query, candidate: Candidate) -> Match? {
        let q = query.text
        let c = candidate.text
        let length = candidate.length
        guard !q.isEmpty else {
            return Match(
                tier: .exact, offset: 0, queryLength: 0, candidateLength: length, spread: 0)
        }

        if c == q {
            return Match(
                tier: .exact, offset: 0, queryLength: query.characters.count,
                candidateLength: length, spread: 0)
        }
        if c.hasPrefix(q) {
            return Match(
                tier: .prefix, offset: 0, queryLength: query.characters.count,
                candidateLength: length, spread: 0)
        }
        if let range = c.range(of: q) {
            let offset = c.distance(from: c.startIndex, to: range.lowerBound)
            return Match(
                tier: isWordStart(c, range.lowerBound) ? .wordStart : .substring, offset: offset,
                queryLength: query.characters.count, candidateLength: length, spread: 0)
        }
        guard let spread = subsequenceScore(query.characters, c) else { return nil }
        return Match(
            tier: .subsequence, offset: 0, queryLength: query.characters.count,
            candidateLength: length, spread: spread)
    }

    /// 只返回分数的形式，供只对单个字段排序、不按匹配强度分档的调用方使用。
    static func score(query: String, candidate: String) -> Int? {
        match(query: query, candidate: candidate).map(rawScore)
    }

    /// 使用已折叠查询的形式，供一个查询遍历大量候选的调用方使用。
    static func score(_ query: Query, candidate: String) -> Int? {
        match(query, candidate: candidate).map(rawScore)
    }

    static func score(_ query: Query, candidate: Candidate) -> Int? {
        match(query, candidate: candidate).map(rawScore)
    }

    /// FileSearch 只对一个字段排序，需要单一排序值，而非区分角色的排序值。
    fileprivate static func rawScore(_ match: Match) -> Int {
        switch match.tier {
        case .exact: 100_000
        case .prefix: 90_000 - match.candidateLength
        case .wordStart: 80_000 - match.candidateLength
        case .substring: 70_000 - match.candidateLength
        case .subsequence: match.spread
        }
    }

    /// 所有搜索共用的唯一折叠实现：匹配、学习排序键与去重都调用它。
    static func normalized(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value >= 0xAD }) else {
            return value.lowercased()
        }
        // 先做组合，使韩文或越南文输入法产生的分解输入能像正常输入一样折叠。
        let composed = value.precomposedStringWithCanonicalMapping
        let scalars = composed.unicodeScalars.filter { $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(scalars)).folding(options: folding, locale: nil)
    }

    /// 与区域设置无关：土耳其语折叠会把 "I" 映射为 "ı"，使所有已存键失配。
    static let folding: String.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive
    ]

    /// 判断该下标是否为词首（字符串开头，或前一字符不是字母也不是数字）。
    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    /// 原地遍历并携带前一个字符：此前 `Array(c)` 会在每次按键时产生一次分配。
    private static func subsequenceScore(_ q: [Character], _ c: String) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        var ci = 0
        var previous: Character?
        for ch in c {
            if qi < q.count, ch == q[qi] {
                var bonus = 1
                if ci == prev + 1 {
                    run += 1
                    bonus += run * 3
                } else {
                    run = 0
                }
                if ci == 0 {
                    bonus += 12
                } else if let previous, !previous.isLetter, !previous.isNumber {
                    bonus += 8
                }
                score += bonus
                prev = ci
                qi += 1
                if qi == q.count { break }
            }
            previous = ch
            ci += 1
        }
        guard qi == q.count else { return nil }
        return score
    }

    /// 从索引 0 开始连续命中会得到的分数，用于把 `spread` 归一化为比例。
    static func referenceSpread(_ queryLength: Int) -> Int {
        guard queryLength > 0 else { return 1 }
        return 13 + (queryLength - 1) + 3 * queryLength * (queryLength - 1) / 2
    }
}

/// 条目可被命中的一个字符串；排序只读取 `role`，不读其他内容。
struct SearchAlias: Sendable, Hashable {
    enum Role: Sendable {
        /// 条目的提供者而非条目本身：如菜单的路径、窗口所属应用。
        case owner
        /// 条目展示所用的名称。
        case name
    }

    let text: String
    let role: Role

    init(_ text: String, _ role: Role) {
        self.text = text
        self.role = role
    }

    /// 以“名称”角色创建别名。
    static func name(_ text: String) -> Self { Self(text, .name) }
    /// 以“提供者”角色创建别名。
    static func owner(_ text: String) -> Self { Self(text, .owner) }
}

/// 绝不要把它们压扁成一个字符串——命中的是哪个别名决定了单元格选择的一半。
struct SearchFields: Sendable, Hashable, ExpressibleByArrayLiteral {
    var aliases: [SearchAlias]

    init(_ aliases: [SearchAlias] = []) { self.aliases = aliases }
    init(arrayLiteral elements: SearchAlias...) { aliases = elements }

    mutating func append(_ alias: SearchAlias) { aliases.append(alias) }
}

/// 查询与菜单项或窗口的契合程度：取最强字段的单元格，并按 shape 排序。
enum SearchRelevance {
    /// 单元格内部 `shape` 的取值跨度；它只在单元格内部排序，绝不跨越单元格。
    static let shapeSpan = 99

    /// 由角色与匹配层级决定的分档值；nil 表示该组合不参与候选。
    static func cell(_ role: SearchAlias.Role, _ tier: FuzzyMatch.Tier) -> Int? {
        switch (role, tier) {
        case (.name, .exact): 6_500
        case (.name, .prefix): 3_000
        case (.owner, .exact): 2_500
        case (.name, .wordStart): 2_400
        case (.owner, .prefix): 2_000
        case (.name, .substring): 1_800
        case (.owner, .wordStart): 1_500
        case (.owner, .substring): 1_100
        case (.name, .subsequence): 1_000
        // 同一提供者的所有条目共享其文本，因此子序列命中的结果会泛滥。
        case (.owner, .subsequence): nil
        }
    }

    /// 在单个单元格内排序候选：查询覆盖了名称的多大比例，以及命中位置有多靠前。
    static func shape(_ match: FuzzyMatch.Match) -> Int {
        guard match.candidateLength > 0 else { return 0 }
        let coverage = min(1, Double(match.queryLength) / Double(match.candidateLength))
        // 采用绝对位置而非比例：命中发生在第 5 个字符处，在任何名称中的深度相同。
        let positional =
            match.tier == .subsequence
            ? min(1, Double(match.spread) / Double(FuzzyMatch.referenceSpread(match.queryLength)))
            : 1 / (1 + Double(match.offset) / 4)
        return Int((Double(shapeSpan) * (0.6 * coverage + 0.4 * positional)).rounded())
    }

    /// 由最强匹配别名得到的基础相关度；无任何匹配时为 nil。
    static func quality(query: String, fields: SearchFields) -> Int? {
        quality(FuzzyMatch.Query(query), fields: fields)
    }

    /// 使用已折叠查询的形式：索引只折叠一次查询，而非每个条目折叠一次。
    static func quality(_ query: FuzzyMatch.Query, fields: SearchFields) -> Int? {
        // 空查询对所有条目同样相关，因此没有别名可以占用单元格。
        guard !query.isEmpty else { return 0 }
        var best: Int?
        for alias in fields.aliases {
            guard let match = FuzzyMatch.match(query, candidate: alias.text),
                let cell = cell(alias.role, match.tier)
            else { continue }
            best = max(best ?? Int.min, cell + shape(match))
        }
        return best
    }
}
