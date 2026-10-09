// 文件职责：定义笔记编辑器的字体排版常量（正文、标题、行内代码、代码块与隐藏标记字体）。
// 分层：UI 支持层；`@MainActor` 限定，只提供字体静态值，不持有状态。
import AppKit

/// 编辑器使用的 `NSFont` 集合：比系统文本样式大一号，因为笔记是用于阅读的。
@MainActor
enum NoteMarkdownTypography {
    static let body = NSFont.systemFont(ofSize: size(.title3))
    static let heading1 = NSFont.systemFont(ofSize: size(.largeTitle), weight: .bold)
    static let heading2 = NSFont.systemFont(ofSize: size(.title1), weight: .bold)
    static let heading3 = NSFont.systemFont(ofSize: size(.title2), weight: .semibold)
    static let inlineCode = NSFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
    static let codeBlock = NSFont.monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular)
    /// 足够小，使被隐藏的标记不留下可见空隙，同时仍是一个真实字形串。
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    /// 4 至 6 级标题共用第三级标题的样式。
    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: heading1
        case 2: heading2
        default: heading3
        }
    }

    /// 返回在原字体基础上叠加指定符号特征（如粗体、斜体）的字体。
    static func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let current = font.fontDescriptor.symbolicTraits
        let descriptor = font.fontDescriptor.withSymbolicTraits(current.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    /// 取指定系统文本样式的字号。
    private static func size(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).pointSize
    }

    /// 返回与给定字号匹配的行内代码等宽字体。
    static func inlineCode(matching font: NSFont) -> NSFont {
        font.pointSize == body.pointSize
            ? inlineCode : NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
    }
}
