// 文件职责：定义笔记编辑器可发起的 Markdown 编辑手势枚举。
// 分层：Model；纯枚举、`Sendable`，不依赖 AppKit/SwiftUI。
import Foundation

/// 文本视图交给 `NoteMarkdownEditing` 规划的一种 Markdown 感知编辑手势。
enum NoteEditAction: Sendable, Equatable {
    /// 行内样式：粗体、斜体、删除线、行内代码。
    enum InlineStyle: Sendable, CaseIterable { case bold, italic, strikethrough, code }
    /// 列表样式：无序、有序、任务。
    enum ListStyle: Sendable { case bullet, ordered, task }

    case newline
    case deleteBackward
    case indent
    case outdent
    case toggleInline(InlineStyle)
    case toggleLink
    /// level 为 0 时把该行还原为普通段落。
    case setHeading(level: Int)
    case toggleList(ListStyle)
    /// 给涉及的行加围栏；若选区已在围栏块内则移除其围栏。
    case toggleCodeBlock
    case toggleQuote
    case toggleTask(lineIndex: Int)
    /// `[] ` 输入规则。
    case typedSpace
    case pasteURL(String)
}
