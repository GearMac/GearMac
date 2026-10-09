// 文件职责：定义笔记领域的基础值类型：标识、列表摘要、搜索结果、文档与编辑器输入。
// 分层：Model；纯值类型且 `Sendable`，不依赖 AppKit/SwiftUI。
import Foundation

/// 笔记的稳定标识，以字符串原始值表示。
struct NoteID: RawRepresentable, Hashable, Sendable {
    let rawValue: String
}

/// 笔记的列表摘要：标题、可选首行与修改时间。
struct NoteSummary: Identifiable, Sendable, Equatable {
    let id: NoteID
    let title: String
    /// 笔记尚未命名时用它代替 `title` 展示；用户命名后为 nil。
    let firstLine: String?
    let modifiedAt: Date

    /// 列表展示用的标题。
    var displayTitle: String { firstLine ?? title }
}

/// 一条笔记搜索结果：摘要与其得分。
struct NoteSearchResult: Identifiable, Sendable, Equatable {
    var id: NoteID { summary.id }
    let summary: NoteSummary
    let score: Int
}

/// 笔记文档：标识与其 Markdown 源文本。
struct NoteDocument: Sendable, Equatable {
    let id: NoteID
    let source: String
}

/// 送入编辑器的输入：标识、源文本与版本号（epoch）。
struct NoteEditorInput: Sendable, Equatable {
    let id: NoteID
    let source: String
    let epoch: Int
}
