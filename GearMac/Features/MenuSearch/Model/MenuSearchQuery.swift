// 文件职责：对菜单搜索条目按查询条件进行匹配与排序，返回限定数量的结果。
// 分层：Model；纯计算函数，不保存状态、不 import AppKit/SwiftUI。
import Foundation

/// 菜单搜索的排序入口：按匹配质量与词项得分排序，并限制结果数量。
enum MenuSearchQuery {
    /// 单次搜索返回的最大结果条数。
    static let resultLimit = 200

    /// 按整串质量、词项得分、路径与标题依次排序，并截取前 resultLimit 条。
    static func rank(_ items: [MenuSearchItem], for query: String) -> [MenuSearchItem] {
        let whole = FuzzyMatch.Query(query)
        guard !whole.isEmpty else { return [] }
        let terms = query.split(whereSeparator: \Character.isWhitespace).map(String.init)
            .map(FuzzyMatch.Query.init)
        return items.compactMap { item -> (MenuSearchItem, Int?, Int)? in
            let quality = SearchRelevance.quality(whole, fields: item.searchFields())
            let termScore = terms.compactMap { FuzzyMatch.score($0, candidate: item.title) }
                .reduce(0, +)
            guard quality != nil || termScore > 0 else { return nil }
            return (item, quality, termScore)
        }
        .sorted { left, right in
            switch (left.1, right.1) {
            case let (leftQuality?, rightQuality?) where leftQuality != rightQuality:
                return leftQuality > rightQuality
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if left.2 != right.2 { return left.2 > right.2 }
                if left.0.displayPath != right.0.displayPath {
                    return
                        left.0.displayPath.localizedCaseInsensitiveCompare(right.0.displayPath)
                        == .orderedAscending
                }
                return
                    left.0.title.localizedCaseInsensitiveCompare(right.0.title)
                    == .orderedAscending
            }
        }
        .prefix(resultLimit)
        .map(\.0)
    }
}
