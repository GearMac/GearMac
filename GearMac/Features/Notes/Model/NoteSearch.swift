// 文件职责：把查询与笔记摘要/源文本匹配并打分排序，供笔记切换器检索。
// 分层：Model；纯函数、不依赖 AppKit/SwiftUI。
import Foundation

/// 笔记搜索：匹配查询与笔记并给出排序结果。
enum NoteSearch {
    /// 由空白切分出的检索词集合。
    struct Query: Sendable {
        let terms: [String]

        /// 按空白拆分出检索词。
        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map(String.init)
        }

        /// 是否没有检索词。
        var isEmpty: Bool { terms.isEmpty }
    }

    /// 匹配一条笔记：标题全部命中优先，其次标题部分命中，否则需在源文本命中；不匹配返回 nil。
    static func match(
        query: Query,
        summary: NoteSummary,
        source: String?
    ) -> NoteSearchResult? {
        guard !query.isEmpty else { return nil }

        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(query: term, candidate: summary.displayTitle) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard let source,
                source.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive]) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        return NoteSearchResult(summary: summary, score: band + titleScore)
    }

    /// 排序规则：先比得分，再比修改时间，最后按标题不区分大小写升序。
    static func precedes(_ lhs: NoteSearchResult, _ rhs: NoteSearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.summary.modifiedAt != rhs.summary.modifiedAt {
            return lhs.summary.modifiedAt > rhs.summary.modifiedAt
        }
        return lhs.summary.displayTitle.localizedCaseInsensitiveCompare(rhs.summary.displayTitle)
            == .orderedAscending
    }
}
