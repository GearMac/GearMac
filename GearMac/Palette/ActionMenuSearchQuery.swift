// 文件职责：封装一次菜单重建中复用的模糊查询「针」对象，对每个候选标题打分，避免重复折叠同一份输入。
// 分层：Model；纯值类型，无副作用，不得 import AppKit/SwiftUI。
import Foundation

/// 已折叠（folded）的菜单查询，在一次菜单重建中对每个行标题复用同一份。
struct ActionMenuSearchQuery {
    private let needle: FuzzyMatch.Query?

    /// 查询为空（无有效针）时为 true。
    var isEmpty: Bool { needle == nil }

    /// 由原始文本构造：去除首尾空白与换行，为空则不生成针。
    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        needle = trimmed.isEmpty ? nil : FuzzyMatch.Query(trimmed)
    }

    /// 对候选标题打分；无针时返回 0，不匹配返回 nil。
    func score(_ candidate: String) -> Int? {
        guard let needle else { return 0 }
        return FuzzyMatch.score(needle, candidate: candidate)
    }
}
