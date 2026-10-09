// 文件职责：定义解析后的颜色值类型，并解析 CSS 风格的十六进制与 rgb()/hsl()/oklch() 文本。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，只做纯字符串与数值处理。
import Foundation

/// 解析后的颜色，以 sRGB 分量存储，所有格式都由此派生。
struct ColorValue: Equatable, Sendable {
    /// 每个分量取值 0…1 且已截断；不携带 alpha 的记法 alpha 为 1。
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// NaN 能穿过 `min`/`max` 且 `Int(NaN)` 会崩，因此非有限的分量一律置零。
    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// 各种记法都按 8 位表示，因此四舍五入后等同不透明的 alpha 即视为不透明。
    var hasAlpha: Bool { (alpha * 255).rounded() < 255 }
}

extension ColorValue {
    /// 以 HSL 传入、以 sRGB 存储：只有一套分量，意味着所有格式都派生自同一来源。
    init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let saturation = min(max(saturation, 0), 1)
        let lightness = min(max(lightness, 0), 1)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double) =
            switch sector {
            case ..<1: (chroma, second, 0)
            case ..<2: (second, chroma, 0)
            case ..<3: (0, chroma, second)
            case ..<4: (0, second, chroma)
            case ..<5: (second, 0, chroma)
            default: (chroma, 0, second)
            }
        self.init(red: red + base, green: green + base, blue: blue + base, alpha: alpha)
    }

    /// 色相、饱和度与亮度，是 HSL 初始化器的逆运算。
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let chroma = maximum - minimum
        let lightness = (maximum + minimum) / 2
        // 舍入会在亮度为 1 时留下约 1e-16 的 chroma，而下面的除数此时为 0。
        let span = 1 - abs(2 * lightness - 1)
        guard chroma > 0, span > 0 else { return (0, 0, lightness) }
        let hue: Double =
            switch maximum {
            case red: 60 * ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            case green: 60 * ((blue - red) / chroma + 2)
            default: 60 * ((red - green) / chroma + 4)
            }
        return (
            hue < 0 ? hue + 360 : hue, min(chroma / span, 1), lightness
        )
    }

    /// 颜色是单个裸 token，超过最长 `hsla()` 形式的文本都不可能是颜色。
    private static let detectionLimit = 64

    /// 值得先做 trim 的原始文本长度上限；超过它则无论如何都不可能是颜色。
    private static let scanLimit = 2048

    /// 解析一个完整的、已 trim 的 token；不是颜色时返回 nil。
    static func parse(_ text: String) -> ColorValue? {
        // 每个可见行都会在每次渲染时执行，因此在分配内存之前先按形态排除。
        guard text.utf8.count <= scanLimit, couldBeColor(text.utf8) else { return nil }
        // 与分类器一致，先 trim 再判长度上限；否则换行符会导致本可读的行被排除。
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= detectionLimit else { return nil }
        if token.hasPrefix("#") { return parseHex(token.dropFirst()) }
        return parseFunctional(token)
    }

    /// 正文与链接仅凭结尾字节即可排除：颜色的结尾是十六进制字符或 `)`。
    private static func couldBeColor(_ bytes: String.UTF8View) -> Bool {
        guard let first = bytes.first(where: { !isSpace($0) }),
            let last = bytes.reversed().first(where: { !isSpace($0) })
        else { return false }
        if first == UInt8(ascii: "#") { return isHex(last) }
        return isLetter(first) && last == UInt8(ascii: ")")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || ((byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "f"))
    }

    /// `#rgb`、`#rgba`、`#rrggbb`、`#rrggbbaa`——CSS 定义的四种长度。
    private static func parseHex(_ digits: Substring) -> ColorValue? {
        // 限定 ASCII，因为 `isHexDigit` 也接受全角形式，而颜色不会那样书写。
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let channels: [Double]
        switch digits.count {
        case 3, 4:
            // 简写会把每个数字重复一次，因此 `#0f0` 表示 `#00ff00` 而非 `#0f0f00`。
            channels = digits.compactMap { $0.hexDigitValue.map { Double($0 * 17) / 255 } }
        case 6, 8:
            channels = stride(from: 0, to: digits.count, by: 2).compactMap { offset in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                let end = digits.index(start, offsetBy: 2)
                return UInt8(digits[start..<end], radix: 16).map { Double($0) / 255 }
            }
        default:
            return nil
        }
        guard channels.count == digits.count / (digits.count <= 4 ? 1 : 2) else { return nil }
        return ColorValue(
            red: channels[0], green: channels[1], blue: channels[2],
            alpha: channels.count == 4 ? channels[3] : 1)
    }

    /// `rgb()` / `rgba()` / `hsl()` / `hsla()` / `oklch()`，支持逗号形式与 CSS4 空格形式。
    private static func parseFunctional(_ token: String) -> ColorValue? {
        guard let open = token.firstIndex(of: "("), token.hasSuffix(")") else { return nil }
        let function = token[token.startIndex..<open].lowercased()
        let body = token[token.index(after: open)..<token.index(before: token.endIndex)]
        // `rgba` 是 `rgb` 的别名而非独立函数，因此 alpha 始终可选。
        guard let parts = arguments(of: body), parts.count == 3 || parts.count == 4,
            let alpha = parts.count == 4 ? component(parts[3], scale: 1) : 1
        else { return nil }
        switch function {
        case "rgb", "rgba":
            guard let red = component(parts[0], scale: 255),
                let green = component(parts[1], scale: 255),
                let blue = component(parts[2], scale: 255)
            else { return nil }
            return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
        case "hsl", "hsla":
            // CSS 中两者都用百分比；裸写 `100` 会被读作 1.0 而返回白色。
            guard let hue = angle(parts[0]), let saturation = percentage(parts[1]),
                let lightness = percentage(parts[2])
            else { return nil }
            return ColorValue(
                hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
        case "oklch":
            // 百分比 chroma 是 0.4 的比例值，0.4 是 CSS 为该轴给定的上界。
            guard let lightness = component(parts[0], scale: 1),
                let chroma = component(parts[1], scale: 1),
                let hue = angle(parts[2])
            else { return nil }
            return ColorValue(
                lightness: lightness, chroma: parts[1].hasSuffix("%") ? chroma * 0.4 : chroma,
                hue: hue, alpha: alpha)
        default:
            return nil
        }
    }

    /// 单个通道按 `scale` 归一；带尾随 `%` 时始终按整体的比例理解。
    private static func component(_ text: String, scale: Double) -> Double? {
        // `Double` 会读入 `nan`、`inf` 以及 CSS 从不书写的 Swift 字面量（如 `0x10` 表示 16）。
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || ".-%".contains($0)) }) else {
            return nil
        }
        let value =
            text.hasSuffix("%")
            ? Double(text.dropLast()).map { $0 / 100 } : Double(text).map { $0 / scale }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    /// CSS 中只以百分比书写的通道。
    private static func percentage(_ text: String) -> Double? {
        text.hasSuffix("%") ? component(text, scale: 1) : nil
    }

    /// 逗号分隔或以空格加斜杠分隔，二者不混用——因此逗号决定了按哪种方式解析。
    private static func arguments(of body: Substring) -> [String]? {
        let parts: [String]
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            parts = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            // 按斜杠两侧分别计数：若拉平，`rgb(0 255 / 0.5)` 会把 alpha 当成蓝色通道。
            let sides = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" })
                .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            switch sides.count {
            // alpha 书写在斜杠之后，故未用斜杠分隔的第四个参数属于格式错误。
            case 1 where sides[0].count == 3: parts = sides[0]
            case 2 where sides[0].count == 3 && sides[1].count == 1: parts = sides[0] + sides[1]
            default: return nil
            }
        }
        return parts.allSatisfy { !$0.isEmpty } ? parts : nil
    }

    /// 以度为单位、归一化到 0…<360 的色相，使 `-30deg` 与 `330` 等价。
    private static func angle(_ text: String) -> Double? {
        let digits = text.lowercased().hasSuffix("deg") ? String(text.dropLast(3)) : text
        guard let degrees = Double(digits), degrees.isFinite else { return nil }
        return degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
    }
}
