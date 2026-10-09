// 文件职责：实现公式在 NSTextView 中的文本附件单元（NSTextAttachmentCell），负责尺寸、基线偏移、自适应缩放与 Core Graphics 绘制。
// 分层：UI；AppKit 文本排版层，在非主 actor 仅做只读尺寸查询。
import AppKit

/// 回复文本视图中的一个已排版公式，用文本自身的颜色按布局结果绘制。
final class MathAttachmentCell: NSTextAttachmentCell {
    private let box: MathBox
    private let color: NSColor
    /// 布局会在主 actor 之外询问尺寸，因此把尺寸数据与绘制数据分开保存。
    private nonisolated let width: CGFloat
    private nonisolated let ascent: CGFloat
    private nonisolated let descent: CGFloat

    /// 用排版结果、文本颜色与无障碍标签创建附件单元。
    init(box: MathBox, color: NSColor, label: String) {
        self.box = box
        self.color = color
        width = box.width
        ascent = box.ascent
        descent = box.descent
        super.init()
        // 不设置角色时，该附件在 VoiceOver 中会表现为未知元素。
        setAccessibilityRole(.image)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("A formula is never decoded") }

    /// 附件单元尺寸：宽 × （升部 + 降部）。
    override func cellSize() -> NSSize { NSSize(width: width, height: ascent + descent) }

    /// 基线相对单元原点的偏移，位于降部之上。
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -descent) }

    /// 比所在行更宽时（如 Quick AI 中的长公式）会等比缩小，而不是溢出。
    override func cellFrame(
        for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint, characterIndex charIndex: Int
    ) -> NSRect {
        let available = lineFrag.width - textContainer.lineFragmentPadding * 2
        let scale = width > available && available > 0 ? available / width : 1
        return NSRect(x: 0, y: -descent * scale, width: width * scale, height: (ascent + descent) * scale)
    }

    /// 在给定画框内按比例绘制公式：内容为 y 轴向上的坐标，需按控件的翻转状态变换。
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard box.width > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = cellFrame.width / box.width
        context.saveGState()
        defer { context.restoreGState() }
        if controlView?.isFlipped ?? true {
            context.translateBy(x: cellFrame.minX, y: cellFrame.maxY)
            context.scaleBy(x: scale, y: -scale)
        } else {
            context.translateBy(x: cellFrame.minX, y: cellFrame.minY)
            context.scaleBy(x: scale, y: scale)
        }
        context.translateBy(x: 0, y: box.descent)
        context.setFillColor(color.cgColor)
        box.draw(in: context)
    }

    override func wantsToTrackMouse() -> Bool { false }
}
