// 文件职责：定义解析后的颜色可以重写成的各种记法，并负责各记法下颜色文本的数字拼写。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，只做纯字符串格式化。
import Foundation

/// 解析后的颜色可以重写成的各种记法。参见 docs/features/clipboard.md#colours。
enum ColorFormat: CaseIterable, Hashable, Sendable {
    case hex
    case hexWithAlpha
    case rgba
    case hsl
    case hslWithAlpha
    case oklch

    /// 菜单行的标题；渲染出的值作为它的尾随文本。
    /// 英文标题保留给尚未迁移的调用点（启动器的颜色卡片），界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .hex: return "Hex"
        case .hexWithAlpha: return "Hex with Alpha"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .hslWithAlpha: return "HSL with Alpha"
        case .oklch: return "Oklch"
        }
    }

    /// 按界面语言给出的记法名。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .hex: .colorFormatHex
            case .hexWithAlpha: .colorFormatHexWithAlpha
            case .rgba: .colorFormatRGBA
            case .hsl: .colorFormatHSL
            case .hslWithAlpha: .colorFormatHSLWithAlpha
            case .oklch: .colorFormatOklch
            }
        return L10n.string(key, language: language)
    }

    /// 该颜色在此记法下读作什么（即渲染出的字符串）。
    func string(for color: ColorValue) -> String {
        switch self {
        case .hex: return ColorDigits.hex(color, includingAlpha: false)
        case .hexWithAlpha: return ColorDigits.hex(color, includingAlpha: true)
        case .rgba:
            return "rgba(\(ColorDigits.channel(color.red)), \(ColorDigits.channel(color.green)), "
                + "\(ColorDigits.channel(color.blue)), \(ColorDigits.decimal(color.alpha)))"
        case .hsl, .hslWithAlpha:
            let hsl = color.hsl
            let alpha = carriesAlpha ? ", \(ColorDigits.decimal(color.alpha))" : ""
            return "hsl(\(ColorDigits.angle(hsl.hue)), \(ColorDigits.percent(hsl.saturation)), "
                + "\(ColorDigits.percent(hsl.lightness))\(alpha))"
        case .oklch:
            let oklch = color.oklch
            // Oklab 各轴的范围约为 ±0.4，若只保留一位小数则多数颜色都会显示为 0。
            return "oklch(\(ColorDigits.percent(oklch.l)) \(ColorDigits.decimal(oklch.c)) "
                + "\(ColorDigits.angle(oklch.h))\(ColorDigits.slashAlpha(color)))"
        }
    }

    /// 仅在确实存在 alpha 时才给出带 alpha 的选项，因此永远不会提供一个不透明的重复项。
    static func offered(for color: ColorValue) -> [ColorFormat] {
        allCases.filter { color.hasAlpha || !$0.carriesAlpha }
    }

    /// 卡片上展示、↵ 复制的记法：能完整表达该颜色的最短形式。
    static func primary(for color: ColorValue) -> ColorFormat {
        color.hasAlpha ? .hexWithAlpha : .hex
    }

    private var carriesAlpha: Bool {
        switch self {
        // CSS4 写法只在存在 alpha 时写出 alpha，因此它们永远不会与主格式重复。
        case .hexWithAlpha, .hslWithAlpha: return true
        default: return false
        }
    }
}

/// 各记法用到的数字拼写——设为 private，因为颜色文本的书写正是本文件的职责。
private enum ColorDigits {
    /// 大写形式，即十六进制颜色约定俗成的书写方式。
    static func hex(_ color: ColorValue, includingAlpha: Bool) -> String {
        let channels = [color.red, color.green, color.blue] + (includingAlpha ? [color.alpha] : [])
        return "#" + channels.map { String(format: "%02X", channel($0)) }.joined()
    }

    /// 单个 0…255 通道，按所有 8 位记法的惯例取整。
    static func channel(_ value: Double) -> Int { integer(value * 255) }

    /// 去掉尾随零，使整数值写作 `1` 而不是 `1.000`。
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded()
            ? String(integer(rounded)) : String(format: "%g", rounded)
    }

    /// 保留一位小数，恰为整数时省略：整数百分比在反解时最多带来 5/255 的误差。
    static func percent(_ value: Double) -> String { number(value * 100) + "%" }

    /// 角度带单位，与 CSS Color 4 书写每个色相的方式一致。
    static func angle(_ value: Double) -> String { number(value) + "deg" }

    /// `oklch()` 的 alpha 写在斜杠之后，颜色不透明时则什么都不写。
    static func slashAlpha(_ color: ColorValue) -> String {
        color.hasAlpha ? " / " + decimal(color.alpha) : ""
    }

    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(integer(tenths)) : String(format: "%.1f", tenths)
    }

    /// 统一的收口点：`Int(_:)` 遇到非有限 Double 会崩，而每种记法最终都要经历这一次转换。
    private static func integer(_ value: Double) -> Int {
        value.isFinite ? Int(value.rounded()) : 0
    }
}
