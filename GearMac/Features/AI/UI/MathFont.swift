// 文件职责：封装 STIX Two Math 字体及其 OpenType MATH 表，为公式排版提供字体度量、常量与字形变体/拼接部件查询。
// 分层：UI；CoreText 字体层，不依赖主 actor。
import CoreText
import Foundation

/// macOS 自带的 STIX Two Math，在指定字号下通过其 OpenType MATH 表读取度量。
struct MathFont {
    /// MATH 表的排版常量，每个成员名对应其在 `MathConstants` 中的字节偏移。
    enum Constant: Int, CaseIterable {
        case scriptPercentScaleDown = 0
        case scriptScriptPercentScaleDown = 2
        case displayOperatorMinHeight = 6
        case axisHeight = 12
        case accentBaseHeight = 16
        case subscriptShiftDown = 24
        case subscriptTopMax = 28
        case subscriptBaselineDropMin = 32
        case superscriptShiftUp = 36
        case superscriptShiftUpCramped = 40
        case superscriptBottomMin = 44
        case superscriptBaselineDropMax = 48
        case subSuperscriptGapMin = 52
        case superscriptBottomMaxWithSubscript = 56
        case spaceAfterScript = 60
        case upperLimitGapMin = 64
        case upperLimitBaselineRiseMin = 68
        case lowerLimitGapMin = 72
        case lowerLimitBaselineDropMin = 76
        case stackTopShiftUp = 80
        case stackTopDisplayStyleShiftUp = 84
        case stackBottomShiftDown = 88
        case stackBottomDisplayStyleShiftDown = 92
        case stackGapMin = 96
        case stackDisplayStyleGapMin = 100
        case fractionNumeratorShiftUp = 120
        case fractionNumeratorDisplayStyleShiftUp = 124
        case fractionDenominatorShiftDown = 128
        case fractionDenominatorDisplayStyleShiftDown = 132
        case fractionNumeratorGapMin = 136
        case fractionNumDisplayStyleGapMin = 140
        case fractionRuleThickness = 144
        case fractionDenominatorGapMin = 148
        case fractionDenomDisplayStyleGapMin = 152
        case overbarVerticalGap = 164
        case overbarRuleThickness = 168
        case overbarExtraAscender = 172
        case underbarVerticalGap = 176
        case underbarRuleThickness = 180
        case underbarExtraDescender = 184
        case radicalVerticalGap = 188
        case radicalDisplayStyleVerticalGap = 192
        case radicalRuleThickness = 196
        case radicalExtraAscender = 200
        case radicalKernBeforeDegree = 204
        case radicalKernAfterDegree = 208
        case radicalDegreeBottomRaisePercent = 212

        /// 这三个是百分比而非以字体单位表示的长度。
        var isPercent: Bool {
            switch self {
            case .scriptPercentScaleDown, .scriptScriptPercentScaleDown, .radicalDegreeBottomRaisePercent:
                true
            default: false
            }
        }
    }

    /// 拼接部件的几何信息：字形与其连接点、推进量。
    struct Part {
        let glyph: CGGlyph
        let startConnector: CGFloat
        let endConnector: CGFloat
        let fullAdvance: CGFloat
        let isExtender: Bool
    }

    static let postScriptName = "STIXTwoMath-Regular"

    let font: CTFont
    let size: CGFloat
    private let table: MathTable
    private let scale: CGFloat

    /// 仅当系统字体或其 MATH 表缺失时为 nil，此时公式退化为显示源码。
    init?(size: CGFloat) {
        guard let table = Self.table else { return nil }
        self.table = table
        self.size = size
        font = CTFontCreateWithName(Self.postScriptName as CFString, size, nil)
        scale = size / CGFloat(table.unitsPerEm)
    }

    /// 只在第一个公式出现时解析一次，启动时不解析。
    private static let table: MathTable? = MathTable(
        CTFontCreateWithName(postScriptName as CFString, 12, nil))

    /// 使 STIX 的 x 高度与 `font` 相等的字号，让公式与正文处于同一尺度。
    static func size(matchingXHeightOf font: CTFont) -> CGFloat {
        let ratio = CTFontGetXHeight(font) / xHeightPerPoint
        return ratio > 0 ? ratio : CTFontGetSize(font)
    }

    private static let xHeightPerPoint = max(
        CTFontGetXHeight(CTFontCreateWithName(postScriptName as CFString, 1, nil)), 0.01)

    /// 返回常量值：百分比常量原样，长度常量按字号换算。
    func value(_ constant: Constant) -> CGFloat {
        let raw = CGFloat(table.constants[constant] ?? 0)
        return constant.isPercent ? raw : raw * scale
    }

    var minConnectorOverlap: CGFloat { CGFloat(table.minConnectorOverlap) * scale }

    /// 取字符串首字符在本字体中的字形；无对应字形时为 nil。
    func glyph(for character: String) -> CGGlyph? {
        let units = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 else {
            return nil
        }
        return glyphs[0]
    }

    func italicCorrection(_ glyph: CGGlyph) -> CGFloat {
        CGFloat(table.italicCorrections[glyph] ?? 0) * scale
    }

    func topAccentAttachment(_ glyph: CGGlyph) -> CGFloat? {
        table.topAccentAttachments[glyph].map { CGFloat($0) * scale }
    }

    /// 字形由小到大的纵向变体，首个为字形本身。
    func verticalVariants(_ glyph: CGGlyph) -> [CGGlyph] {
        [glyph] + (table.vertical[glyph]?.variants ?? [])
    }

    /// 字形由小到大的横向变体，首个为字形本身。
    func horizontalVariants(_ glyph: CGGlyph) -> [CGGlyph] {
        [glyph] + (table.horizontal[glyph]?.variants ?? [])
    }

    /// 可堆叠到任意高度的部件，从底部起：括号的钩、中间件与可拉伸件。
    func verticalAssembly(_ glyph: CGGlyph) -> [Part] {
        (table.vertical[glyph]?.parts ?? []).map { part in
            Part(
                glyph: part.glyph, startConnector: CGFloat(part.startConnector) * scale,
                endConnector: CGFloat(part.endConnector) * scale,
                fullAdvance: CGFloat(part.fullAdvance) * scale, isExtender: part.isExtender)
        }
    }
}

/// 排版用到的 MATH 表内容，单位为字体单位。
private struct MathTable {
    /// 一个字形可用的变体与拼接部件。
    struct Construction {
        var variants: [CGGlyph] = []
        var parts: [RawPart] = []
    }

    /// MATH 表中原始的拼接部件记录，单位为字体单位。
    struct RawPart {
        let glyph: CGGlyph
        let startConnector: UInt16
        let endConnector: UInt16
        let fullAdvance: UInt16
        let isExtender: Bool
    }

    let unitsPerEm: UInt32
    let constants: [MathFont.Constant: Int16]
    let italicCorrections: [CGGlyph: Int16]
    let topAccentAttachments: [CGGlyph: Int16]
    let vertical: [CGGlyph: Construction]
    let horizontal: [CGGlyph: Construction]
    let minConnectorOverlap: UInt16

    init?(_ font: CTFont) {
        let tag = CTFontTableTag(0x4D41_5448)
        guard let data = CTFontCopyTable(font, tag, []) as Data? else { return nil }
        let bytes = BigEndianBytes(Array(data))
        let constantsOffset = bytes.offset(at: 4)
        let glyphInfo = bytes.offset(at: 6)
        let variants = bytes.offset(at: 8)
        guard constantsOffset > 0, glyphInfo > 0, variants > 0 else { return nil }
        unitsPerEm = CTFontGetUnitsPerEm(font)
        var constants: [MathFont.Constant: Int16] = [:]
        for constant in MathFont.Constant.allCases {
            constants[constant] = bytes.int16(at: constantsOffset + constant.rawValue)
        }
        self.constants = constants
        italicCorrections = Self.values(bytes, at: glyphInfo, table: bytes.offset(at: glyphInfo))
        topAccentAttachments = Self.values(bytes, at: glyphInfo, table: bytes.offset(at: glyphInfo + 2))
        minConnectorOverlap = bytes.uint16(at: variants)
        let verticalCoverage = Self.coverage(bytes, at: variants + bytes.offset(at: variants + 2))
        let horizontalCoverage = Self.coverage(bytes, at: variants + bytes.offset(at: variants + 4))
        let verticalCount = Int(bytes.uint16(at: variants + 6))
        vertical = Self.constructions(
            bytes, variants: variants, coverage: verticalCoverage, first: variants + 10,
            count: verticalCount)
        horizontal = Self.constructions(
            bytes, variants: variants, coverage: horizontalCoverage,
            first: variants + 10 + verticalCount * 2, count: Int(bytes.uint16(at: variants + 8)))
    }

    /// 斜体修正或顶部附着表：一个 coverage，随后每个字形一条值记录。
    private static func values(
        _ bytes: BigEndianBytes, at base: Int, table offset: Int
    )
        -> [CGGlyph: Int16]
    {
        guard offset > 0 else { return [:] }
        let start = base + offset
        let glyphs = coverage(bytes, at: start + bytes.offset(at: start))
        var values: [CGGlyph: Int16] = [:]
        for (index, glyph) in glyphs.enumerated() {
            values[glyph] = bytes.int16(at: start + 4 + index * 4)
        }
        return values
    }

    private static func constructions(
        _ bytes: BigEndianBytes, variants: Int, coverage: [CGGlyph], first: Int, count: Int
    ) -> [CGGlyph: Construction] {
        var constructions: [CGGlyph: Construction] = [:]
        for (index, glyph) in coverage.prefix(count).enumerated() {
            let start = variants + bytes.offset(at: first + index * 2)
            var construction = Construction()
            let variantCount = Int(bytes.uint16(at: start + 2))
            for variant in 0..<variantCount {
                let record = bytes.uint16(at: start + 4 + variant * 4)
                if record != glyph { construction.variants.append(record) }
            }
            let assembly = bytes.offset(at: start)
            if assembly > 0 {
                let base = start + assembly
                for part in 0..<Int(bytes.uint16(at: base + 4)) {
                    let record = base + 6 + part * 10
                    construction.parts.append(
                        RawPart(
                            glyph: bytes.uint16(at: record), startConnector: bytes.uint16(at: record + 2),
                            endConnector: bytes.uint16(at: record + 4),
                            fullAdvance: bytes.uint16(at: record + 6),
                            isExtender: bytes.uint16(at: record + 8) & 1 == 1))
                }
            }
            constructions[glyph] = construction
        }
        return constructions
    }

    /// coverage 表列出的字形，按 coverage 索引顺序。
    private static func coverage(_ bytes: BigEndianBytes, at start: Int) -> [CGGlyph] {
        let count = Int(bytes.uint16(at: start + 2))
        switch bytes.uint16(at: start) {
        case 1:
            return (0..<count).map { bytes.uint16(at: start + 4 + $0 * 2) }
        case 2:
            return (0..<count).flatMap { range -> [CGGlyph] in
                let record = start + 4 + range * 6
                let first = bytes.uint16(at: record)
                let last = bytes.uint16(at: record + 2)
                return first <= last ? Array(first...last) : []
            }
        default: return []
        }
    }
}

/// 越界读取返回 0，使被截断的表退化为缺失值而不会崩溃。
private struct BigEndianBytes {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    func int16(at offset: Int) -> Int16 { Int16(bitPattern: uint16(at: offset)) }

    func offset(at position: Int) -> Int { Int(uint16(at: position)) }
}
