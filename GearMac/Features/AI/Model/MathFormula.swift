// 文件职责：表示回复中写下的一个数学公式，保存其源码、解析后的语法树与是否为行间公式。
// 分层：Model；值类型与纯解析，不依赖 UI 渲染。
import Foundation

/// 回复中写下的一个公式，连同其源码保存，便于复制或回退时原样还原。
struct MathFormula: Hashable, Sendable {
    /// 原始书写形式，包含定界符。
    let source: String
    /// 解析后的语法树。
    let root: MathNode
    /// 是否为行间公式。
    let display: Bool

    /// 解析 tex 构建公式；解析失败返回 nil。
    init?(tex: String, source: String, display: Bool) {
        guard let root = MathNode.parse(tex) else { return nil }
        self.source = source
        self.root = root
        self.display = display
    }

    /// 依附于行内公式在 `MarkdownBlock.inline` 结果中所占的那一个字符。
    enum Attribute: AttributedStringKey {
        typealias Value = MathFormula
        static let name = "GearMacMathFormula"
    }

    /// 行内公式在绘制文本中占用的字符，也是查找所搜索的字符。
    static let placeholder: Character = "\u{FFFC}"
}
