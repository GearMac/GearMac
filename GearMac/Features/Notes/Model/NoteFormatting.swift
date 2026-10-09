// 文件职责：描述选区当前已具备的格式状态，供工具栏按钮高亮与切换判定使用。
// 分层：Model；纯值类型、`Sendable`，不依赖 AppKit/SwiftUI。
import Foundation

/// 选区当前已具备的格式；每个标志为真表示对应的切换会将其移除。
struct NoteFormatting: Sendable, Equatable {
    /// 所有可作标题的行都是同一级标题时为 1–6；都是普通段落时为 0。
    var headingLevel: Int?
    var inlineStyles: Set<NoteEditAction.InlineStyle>
    var isLink: Bool
    var isCodeBlock: Bool
    var isQuote: Bool
    var list: NoteEditAction.ListStyle?

    static let plain = NoteFormatting(
        headingLevel: nil, inlineStyles: [], isLink: false, isCodeBlock: false, isQuote: false, list: nil)
}
