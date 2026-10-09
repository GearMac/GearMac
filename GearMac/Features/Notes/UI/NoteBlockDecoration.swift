// 文件职责：定义笔记编辑器按行绘制的块级装饰（代码块、引用、分割线、列表符号、任务复选框）的数据模型与其属性键。
// 分层：UI 支持层；纯值语义描述，不持有 AppKit 视图，需可跨线程传递到排版阶段。
import AppKit

extension NSAttributedString.Key {
    /// 覆盖整行的装饰属性，使 TextKit 提供的段落能在索引 0 处读到它。
    static let noteBlockDecoration = NSAttributedString.Key("gearmac.note.blockDecoration")
}

/// `NoteBlockLayoutFragment` 为单行绘制的装饰内容；不可变，因此可安全传入排版流程。
final class NoteBlockDecoration: NSObject, Sendable {
    /// 一行的装饰形状类型。
    enum Shape: Sendable, Equatable, Hashable {
        /// 代码块中的行位置：首行、中间行、末行或单行。
        enum CodeRow: Sendable, Hashable { case top, middle, bottom, single }
        case code(CodeRow, language: String?)
        case quote(depth: Int)
        case rule
        case bullet(level: Int)
        /// 源文本自身的编号标签，例如 `3.` 或 `3)`。
        case ordered(level: Int, label: String)
        case task(level: Int, checked: Bool)
    }

    /// 当前装饰的形状。
    let shape: Shape
    /// 色带、竖条、分割线、圆点或方框的填充色。
    let fill: NSColor
    /// 编号文字或语言标签的颜色；任务项则改为从方框中镂空出对勾。
    let ink: NSColor
    let bodyPointSize: CGFloat

    /// 使用形状、填充色、文字色与正文字号构造装饰。
    init(shape: Shape, fill: NSColor, ink: NSColor, bodyPointSize: CGFloat) {
        self.shape = shape
        self.fill = fill
        self.ink = ink
        self.bodyPointSize = bodyPointSize
    }

    /// 按值比较，使一行重新样式化为相同外观时不会被判定为发生变化。
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NoteBlockDecoration else { return false }
        return shape == other.shape && fill == other.fill && ink == other.ink
            && bodyPointSize == other.bodyPointSize
    }

    /// 与 `isEqual` 保持一致的哈希值，参与哈希表比较。
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(shape)
        hasher.combine(fill)
        hasher.combine(ink)
        hasher.combine(bodyPointSize)
        return hasher.finalize()
    }
}
