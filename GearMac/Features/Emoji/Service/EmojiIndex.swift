// 文件职责：表情目录的内存索引，负责解析数据、按分区分组、模糊搜索排序与查询结果记忆化。
// 分层：Service；索引状态在主 actor 上维护，解析与文本折叠在 detached 任务中完成。
import Foundation

/// 已解析的目录：加载时预计算分区，搜索结果按单次查询深度记忆化。
@MainActor
@Observable
final class EmojiIndex {
    private(set) var entries: [EmojiEntry] = []
    private(set) var categorySections: [(category: EmojiCategory, entries: [EmojiEntry])] = []

    /// `order` 是目录索引，也是同分时保持目录顺序的决胜负依据。
    private struct ScoredEntry {
        let entry: EmojiEntry
        let score: Int
        let order: Int
    }

    /// 加载时预先折叠好的词条文本，使每次按键只需折叠查询。
    private struct FoldedEntry: Sendable {
        let name: FuzzyMatch.Candidate
        let keywords: FuzzyMatch.Candidate
        let keywordList: [FuzzyMatch.Candidate]

        init(_ entry: EmojiEntry) {
            name = FuzzyMatch.Candidate(entry.name)
            keywords = FuzzyMatch.Candidate(entry.keywords)
            keywordList = entry.keywords.split(separator: ",").map { FuzzyMatch.Candidate(String($0)) }
        }
    }

    /// 记忆化缓存的键：查询词、目录版本、常用库身份与版本、数量上限。
    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
        let frequentID: ObjectIdentifier
        let frequentRevision: Int
        let limit: Int
    }

    private var byGlyph: [String: EmojiEntry] = [:]
    /// 与 `entries` 一一对应。
    private var foldedEntries: [FoldedEntry] = []
    @ObservationIgnored private var searchMemo = Memo<SearchKey, [EmojiEntry]>()
    /// 每次加载递增，使上面的键能标明它打分的是哪一版目录。
    private var revision = 0

    var isLoaded: Bool { !entries.isEmpty }

    /// `languages` 决定将 bundle 中哪些关键词包汇入目录的英文关键词。
    func load(_ raw: String = EmojiData.raw, languages: [String] = [], bundle: Bundle = .main) async {
        let (parsed, folded) = await Task.detached(priority: .utility) {
            let parsed = EmojiCatalog.parse(raw, localized: Self.keywordPacks(for: languages, in: bundle))
            return (parsed, parsed.map(FoldedEntry.init))
        }.value
        entries = parsed
        foldedEntries = folded
        var grouped: [EmojiCategory: [EmojiEntry]] = [:]
        for entry in parsed { grouped[entry.category, default: []].append(entry) }
        categorySections = EmojiCategory.allCases.compactMap { category in
            grouped[category].map { (category, $0) }
        }
        byGlyph = Dictionary(parsed.map { ($0.glyph, $0) }, uniquingKeysWith: { first, _ in first })
        revision &+= 1
    }

    /// 使用普通文件而非 `.lproj`：那会把 AppKit 自身的文本也切成非英文。
    private nonisolated static func keywordPacks(for languages: [String], in bundle: Bundle) -> [String] {
        let urls = bundle.urls(forResourcesWithExtension: "txt", subdirectory: "EmojiKeywords") ?? []
        let byLanguage = Dictionary(
            urls.map { ($0.deletingPathExtension().lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first })
        return EmojiCatalog.keywordLanguages(available: byLanguage.keys.sorted(), preferred: languages)
            .compactMap { byLanguage[$0].flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
    }

    /// 按字形查询词条。
    func entry(for glyph: String) -> EmojiEntry? { byGlyph[glyph] }

    /// 在名称与关键词上做排序后的模糊匹配；空查询不返回任何结果。
    func search(_ query: String, frequent: FrequentEmojiStore, limit: Int = 320) -> [EmojiEntry] {
        let trimmed = FuzzyMatch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped =
            trimmed.count > 2 && trimmed.first == ":" && trimmed.last == ":"
            ? String(trimmed.dropFirst().dropLast()) : trimmed
        let words = unwrapped.split(whereSeparator: \.isWhitespace).map(String.init)
        let q = words.joined(separator: " ")
        guard !q.isEmpty, limit > 0 else { return [] }
        let key = SearchKey(
            query: q, revision: revision, frequentID: ObjectIdentifier(frequent),
            frequentRevision: frequent.revision, limit: limit)
        return searchMemo.value(for: key) {
            let query = FuzzyMatch.Query(q)
            let terms = words.count > 1 ? words : []
            let frequentGlyphs = frequent.top(Self.frecencyLimit)
            let frecency = Dictionary(
                frequentGlyphs.enumerated().map {
                    ($0.element, Self.frecencyLimit - $0.offset)
                }, uniquingKeysWith: max)
            var scored: [ScoredEntry] = []
            for (order, entry) in entries.enumerated() {
                guard let textScore = Self.textScore(query, terms: terms, folded: foldedEntries[order])
                else { continue }
                let score = textScore + (frecency[entry.glyph] ?? 0)
                scored.append(ScoredEntry(entry: entry, score: score, order: order))
            }
            return
                scored
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
                .prefix(limit)
                .map(\.entry)
        }
    }

    /// 略低于半档，使质量相同的名称匹配总能胜出。
    private static let keywordPenalty = 500
    private static let frecencyLimit = 100
    /// 完整的前置名称单词：高于精确关键词，低于精确名称。
    private static let leadingWordScore = 95_000
    /// 分散的查询词排在任何字面短语之后，纯名称命中优先于混合命中。
    private static let nameWordsScore = 60_000
    private static let mixedWordsScore = 50_000

    /// 计算单个词条的文本得分；所有词都无法定位到名称或关键词时返回 nil。
    private static func textScore(
        _ query: FuzzyMatch.Query, terms: [String], folded: FoldedEntry
    ) -> Int? {
        var nameOnly = true
        for term in terms where !containsWordStart(term, in: folded.name.text) {
            guard !term.contains(","), containsWordStart(term, in: folded.keywords.text) else { return nil }
            nameOnly = false
        }

        let nameMatch = FuzzyMatch.match(query, candidate: folded.name)
        if nameMatch?.tier == .exact { return nameMatch?.score }
        var best = nameMatch?.score
        if let nameMatch, nameMatch.tier == .prefix,
            let next = folded.name.text.dropFirst(nameMatch.queryLength).first,
            !next.isLetter && !next.isNumber
        {
            best = leadingWordScore - nameMatch.candidateLength
        }
        if !terms.isEmpty {
            let ordered = nameMatch?.tier == .subsequence ? nameMatch?.score ?? 0 : 0
            best = max(best ?? Int.min, (nameOnly ? nameWordsScore : mixedWordsScore) + ordered)
        }
        guard !folded.keywordList.isEmpty, FuzzyMatch.score(query, candidate: folded.keywords) != nil
        else { return best }
        for keyword in folded.keywordList {
            guard let match = FuzzyMatch.match(query, candidate: keyword) else { continue }
            best = max(best ?? Int.min, min(match.score, leadingWordScore) - keywordPenalty)
            if match.tier == .exact { break }
        }
        return best
    }

    /// 判断 `term` 是否出现在候选文本的词首（开头或非字母数字字符之后）。
    private static func containsWordStart(_ term: String, in candidate: String) -> Bool {
        var start = candidate.startIndex
        while let range = candidate.range(of: term, range: start..<candidate.endIndex) {
            if range.lowerBound == candidate.startIndex { return true }
            let previous = candidate[candidate.index(before: range.lowerBound)]
            if !previous.isLetter && !previous.isNumber { return true }
            start = candidate.index(after: range.lowerBound)
        }
        return false
    }
}
