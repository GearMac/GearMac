// 文件职责：表示一段已排版公式的几何范围（相对基线的宽、升部、降部）与绘制指令，并提供组合与绘制原语。
// 分层：UI；使用 AppKit/CoreText，坐标系 y 轴向上。
import AppKit

/// 已排版的一段公式：相对基线的范围与待绘制的标记，y 轴向上。
struct MathBox {
    /// 一条绘制指令：一组字形或一段矩形。
    enum Mark {
        case glyphs(CTFont, [CGGlyph], [CGPoint])
        case rule(CGRect)
    }

    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    /// 末位倾斜字形超出其前进宽度的距离，上标需要避开它。
    var italicCorrection: CGFloat = 0
    private(set) var marks: [Mark] = []

    var height: CGFloat { ascent + descent }

    init(width: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0) {
        self.width = width
        self.ascent = ascent
        self.descent = descent
    }

    /// 单个字形，按墨迹边界测量，使角标贴合实际绘制而非行框。
    init(glyph: CGGlyph, font: CTFont) {
        var glyph = glyph
        var ink = CGRect.zero
        var advance = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &ink, 1)
        CTFontGetAdvancesForGlyphs(font, .default, &glyph, &advance, 1)
        width = advance.width
        ascent = max(ink.maxY, 0)
        descent = max(-ink.minY, 0)
        marks = [.glyphs(font, [glyph], [.zero])]
    }

    /// 一段经 Core Text 排版的文本；STIX 缺失的字形会回退到其它字体。
    init(text: String, font: CTFont) {
        let attributed = NSAttributedString(
            string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if !ink.isNull {
            ascent = max(ink.maxY, 0)
            descent = max(-ink.minY, 0)
        }
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            let fallback = (CTRunGetAttributes(run) as? [NSAttributedString.Key: Any])?[.font] as? NSFont
            marks.append(.glyphs(fallback.map { $0 as CTFont } ?? font, glyphs, positions))
        }
    }

    /// 由矩形生成一条实心线段的盒。
    static func rule(_ rect: CGRect) -> MathBox {
        var box = MathBox(width: rect.maxX, ascent: max(rect.maxY, 0), descent: max(-rect.minY, 0))
        box.marks = [.rule(rect)]
        return box
    }

    /// 将 `box` 的基线原点放在 `x, y` 处绘制，并扩展本盒以容纳它。
    mutating func place(_ box: MathBox, x: CGFloat, y: CGFloat = 0) {
        width = max(width, x + box.width)
        ascent = max(ascent, y + box.ascent)
        descent = max(descent, box.descent - y)
        for mark in box.marks {
            switch mark {
            case .glyphs(let font, let glyphs, let positions):
                marks.append(.glyphs(font, glyphs, positions.map { CGPoint(x: $0.x + x, y: $0.y + y) }))
            case .rule(let rect):
                marks.append(.rule(rect.offsetBy(dx: x, dy: y)))
            }
        }
    }

    /// 同一绘制整体上移 `shift`，用于把定界符居中到数学轴线上。
    func raised(by shift: CGFloat) -> MathBox {
        var raised = MathBox(width: width)
        raised.place(self, x: 0, y: shift)
        raised.ascent = ascent + shift
        raised.descent = descent - shift
        raised.italicCorrection = italicCorrection
        return raised
    }

    /// 以基线上的 y 轴向上原点、用上下文当前填充色绘制。
    func draw(in context: CGContext) {
        context.textMatrix = .identity
        for mark in marks {
            switch mark {
            case .glyphs(let font, let glyphs, let positions):
                CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
            case .rule(let rect):
                context.fill(rect)
            }
        }
    }
}
