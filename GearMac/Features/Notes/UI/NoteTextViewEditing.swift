// 文件职责：定义 `NoteTextView` 向其所属编辑器请求的接口，包括渲染状态与生命周期回调。
// 分层：UI 协议层；`@MainActor` 限定，实现方须在主线程响应。
import Foundation

/// `NoteTextView` 对持有它的编辑器提出的要求：渲染状态与生命周期调用。
@MainActor
protocol NoteTextViewEditing: AnyObject {
    var rendersMarkdown: Bool { get }
    /// 文本视图当前源文本的解析结果。
    var markdown: NoteMarkdown { get }
    /// 焦点状态变化时回调。
    func focusChanged()
    /// 外观（如主题或字号）变化时回调。
    func appearanceChanged()
    /// 拖拽选择结束时回调。
    func dragSelectionEnded()
}
