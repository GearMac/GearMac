// 文件职责：定义窗口切换器的查询排序（模糊匹配 + 相关度评分与结果数量上限）。
// 分层：Model；纯查询逻辑，不依赖 UI 或系统 API。
import Foundation

/// 窗口切换查询的排序与截断。
enum WindowSwitchQuery {
    /// 结果数量上限。
    static let resultLimit = 200

    /// 同分时按传入位置排序，使同等匹配质量的结果保持最近使用顺序。
    static func rank(_ entries: [WindowSwitchEntry], for query: String) -> [WindowSwitchEntry] {
        let folded = FuzzyMatch.Query(query)
        guard !folded.isEmpty else { return Array(entries.prefix(resultLimit)) }
        return entries.enumerated()
            .compactMap { position, entry -> (WindowSwitchEntry, Int, Int)? in
                guard let quality = SearchRelevance.quality(folded, fields: entry.searchFields())
                else { return nil }
                return (entry, quality, position)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .prefix(resultLimit)
            .map(\.0)
    }
}
