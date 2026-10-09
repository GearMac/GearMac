// 文件职责：自定义 NSTextLayoutFragment，在文本周围绘制单行的块级装饰（代码块底纹、引用竖条、分割线、列表标记与任务复选框）。
// 分层：UI 支持层；只负责绘制，不参与文本解析或状态管理。
import AppKit

/// 绘制单行的块级装饰（代码底纹、引用竖条、分割线、列表标记），围绕其文本进行。
final class NoteBlockLayoutFragment: NSTextLayoutFragment {
    let decoration: NoteBlockDecoration

    private static let orderedLabelPadding: CGFloat = 4
    private static let bulletScale: CGFloat = 0.35
    private static let boxStroke: CGFloat = 1.25
    private static let boxRadius: CGFloat = 3
    private static let checkStroke: CGFloat = 1.5

    /// 使用文本元素、范围与装饰信息构造片段。
    init(textElement: NSTextElement, range: NSTextRange?, decoration: NoteBlockDecoration) {
        self.decoration = decoration
        super.init(textElement: textElement, range: range)
    }

    /// 不支持从归档解码。
    required init?(coder: NSCoder) {
        nil
    }

    /// 绘制被裁剪到该范围内；它从容器左侧留出一个槽位开始，使较宽的编号也能完整显示。
    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        let frame = layoutFragmentFrame
        let chrome = CGRect(
            x: -frame.minX - slot, y: 0, width: containerWidth + slot, height: frame.height)
        return bounds.union(chrome)
    }

    /// 按装饰形状绘制底纹、竖条、分割线、列表标记或复选框，然后调用父类绘制文本。
    override func draw(at point: CGPoint, in context: CGContext) {
        let left = point.x - layoutFragmentFrame.minX
        if case .code(let row, let language) = decoration.shape {
            drawBand(row: row, language: language, left: left, top: point.y, in: context)
        }
        super.draw(at: point, in: context)
        context.saveGState()
        defer { context.restoreGState() }
        switch decoration.shape {
        case .code:
            break
        case .quote(let depth):
            drawQuoteBars(depth: depth, left: left, top: point.y, in: context)
        case .rule:
            let y = (point.y + layoutFragmentFrame.height / 2).rounded(.down)
            context.setFillColor(decoration.fill.cgColor)
            let width = containerWidth.rounded()
            context.fill(CGRect(x: left.rounded(), y: y, width: width, height: Theme.Size.hairline))
        case .bullet(let level):
            drawBullet(level: level, left: left, top: point.y, in: context)
        case .ordered(let level, let label):
            drawLabel(label, level: level, left: left, top: point.y, in: context)
        case .task(let level, let checked):
            drawBox(level: level, checked: checked, left: left, top: point.y, in: context)
        }
    }

    // MARK: - Shapes

    private var slot: CGFloat { NoteCheckboxGeometry.slot(bodyPointSize: decoration.bodyPointSize) }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? super.renderingSurfaceBounds.width
    }

    /// 首个可见文本行；当列表项换行时，标记与它对齐。
    private var firstLine: CGRect {
        textLineFragments.first?.typographicBounds ?? CGRect(origin: .zero, size: layoutFragmentFrame.size)
    }

    /// 首个文本行的基线 y 坐标。
    private var firstBaseline: CGFloat {
        guard let line = textLineFragments.first else { return layoutFragmentFrame.height }
        return line.typographicBounds.minY + line.glyphOrigin.y
    }

    /// 绘制代码块底纹行，并在首行右侧绘制语言标签。
    private func drawBand(
        row: NoteBlockDecoration.Shape.CodeRow, language: String?, left: CGFloat, top: CGFloat,
        in context: CGContext
    ) {
        let minY = top.rounded()
        let rect = CGRect(
            x: left.rounded(), y: minY, width: containerWidth.rounded(),
            height: (top + layoutFragmentFrame.height).rounded() - minY)
        let roundsTop = row == .top || row == .single
        let roundsBottom = row == .bottom || row == .single
        context.saveGState()
        context.addPath(
            Self.bandPath(
                rect, topRadius: roundsTop ? Theme.Radius.menu : 0,
                bottomRadius: roundsBottom ? Theme.Radius.menu : 0))
        context.setFillColor(decoration.fill.cgColor)
        context.fillPath()
        if roundsTop, let language {
            let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize)
            let line = Self.line(language, font: font, color: decoration.ink)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let baseline = top + (layoutFragmentFrame.height + font.capHeight) / 2
            Self.draw(line, at: CGPoint(x: rect.maxX - Theme.Spacing.lg - width, y: baseline), in: context)
        }
        context.restoreGState()
    }

    /// 根据引用嵌套深度绘制多根竖条。
    private func drawQuoteBars(depth: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        context.setFillColor(decoration.fill.cgColor)
        let step = Theme.Size.markdownQuoteBar + Theme.Spacing.lg
        let minY = top.rounded()
        let height = (top + layoutFragmentFrame.height).rounded() - minY
        for level in 0..<depth {
            let bar = CGRect(
                x: (left + CGFloat(level) * step).rounded(), y: minY, width: Theme.Size.markdownQuoteBar,
                height: height)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 1, cornerHeight: 1, transform: nil))
        }
        context.fillPath()
    }

    /// 在对应列表层级绘制圆点标记。
    private func drawBullet(level: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        let diameter = decoration.bodyPointSize * Self.bulletScale
        let center = CGPoint(x: left + CGFloat(level) * slot + slot / 2, y: top + firstLine.midY)
        context.setFillColor(decoration.fill.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
    }

    /// 在对应列表层级绘制有序列表的编号标签，右对齐到槽位末端。
    private func drawLabel(_ label: String, level: Int, left: CGFloat, top: CGFloat, in context: CGContext) {
        let font = NSFont.systemFont(ofSize: decoration.bodyPointSize)
        let line = Self.line(label, font: font, color: decoration.ink)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let slotEnd = left + CGFloat(level + 1) * slot - Self.orderedLabelPadding
        Self.draw(line, at: CGPoint(x: slotEnd - width, y: top + firstBaseline), in: context)
    }

    /// 绘制任务复选框：未勾选为空心方框，已勾选为填充方框并镂空出对勾。
    private func drawBox(level: Int, checked: Bool, left: CGFloat, top: CGFloat, in context: CGContext) {
        let box = NoteCheckboxGeometry.rect(
            level: level, firstLineHeight: firstLine.height, bodyPointSize: decoration.bodyPointSize
        ).offsetBy(dx: left, dy: top + firstLine.minY)
        guard checked else {
            context.addPath(Self.roundedBox(box.insetBy(dx: Self.boxStroke / 2, dy: Self.boxStroke / 2)))
            context.setStrokeColor(decoration.fill.cgColor)
            context.setLineWidth(Self.boxStroke)
            context.strokePath()
            return
        }
        context.addPath(Self.roundedBox(box))
        context.setFillColor(decoration.fill.cgColor)
        context.fillPath()
        context.move(to: CGPoint(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.55))
        context.addLine(to: CGPoint(x: box.minX + box.width * 0.45, y: box.minY + box.height * 0.75))
        context.addLine(to: CGPoint(x: box.minX + box.width * 0.78, y: box.minY + box.height * 0.30))
        context.setBlendMode(.clear)
        context.setLineWidth(Self.checkStroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    // MARK: - Geometry and text

    /// 仅对指定端点倒圆角，使同一条底纹的上下行在接缝处无缝相接。
    private static func bandPath(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), topRadius),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), topRadius),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), bottomRadius),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY), bottomRadius)
        ]
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for (corner, next, radius) in corners {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }

    /// 返回指定矩形的圆角方框路径。
    private static func roundedBox(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: boxRadius, cornerHeight: boxRadius, transform: nil)
    }

    /// 使用指定字体与颜色构建单行 CTLine。
    private static func line(_ string: String, font: NSFont, color: NSColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// 视图坐标系是翻转的，因此绘制前先把 Core Text 的 y 轴翻回来。
    private static func draw(_ line: CTLine, at baseline: CGPoint, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = baseline
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
