// 文件职责：笔记切换器的交互状态（重命名草稿）与删除后的选中项计算。
// 分层：Model；纯值/纯函数、`Sendable`，不依赖 AppKit/SwiftUI。
import Foundation

/// 笔记切换器中的重命名状态：正在重命名的笔记与草稿标题。
struct NoteSwitcherRenameState: Sendable, Equatable {
    private(set) var id: NoteID?
    private(set) var draft = ""

    /// 是否处于重命名中。
    var isActive: Bool { id != nil }

    /// 开始对指定笔记重命名，并以当前标题初始化草稿。
    mutating func begin(id: NoteID, title: String) {
        self.id = id
        draft = title
    }

    /// 更新草稿标题；未处于重命名时忽略。
    mutating func updateDraft(_ updated: String) {
        guard isActive else { return }
        draft = updated
    }

    /// 取消重命名并清空草稿。
    mutating func cancel() {
        id = nil
        draft = ""
    }

    /// 提交重命名，返回笔记标识与最终标题；未在重命名时返回 nil。
    mutating func commit() -> (id: NoteID, title: String)? {
        guard let id else { return nil }
        let committed = (id, draft)
        cancel()
        return committed
    }
}

/// 笔记切换器删除后的选中项计算。
enum NoteSwitcherSelection {
    /// 删除一条笔记后应选中的下一项：优先原位置的下一项，否则取末尾，最后回退到 fallback。
    static func replacement(
        afterRemoving removed: NoteID,
        from orderedIDs: [NoteID],
        fallback: NoteID?
    ) -> NoteID? {
        guard let removedIndex = orderedIDs.firstIndex(of: removed) else { return fallback }
        let remaining = orderedIDs.filter { $0 != removed }
        if remaining.indices.contains(removedIndex) { return remaining[removedIndex] }
        return remaining.last ?? fallback
    }
}
