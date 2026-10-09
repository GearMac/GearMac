// 文件职责：实现 sRGB 与 Oklab/Oklch 色彩空间之间的转换，为颜色复制提供感知均匀的记法。
// 分层：Model；保持纯净，不得 import AppKit/SwiftUI，仅做纯数值计算。
import Foundation

/// Oklab 及其极坐标形式，是颜色复制时所用的那种感知记法背后的色彩空间。
extension ColorValue {
    /// Oklab 定义在光值上，而不是十六进制三元组所携带的 gamma 编码值上。
    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// 把 sRGB 三通道线性化为光值。
    private var linearComponents: (r: Double, g: Double, b: Double) {
        (Self.linear(red), Self.linear(green), Self.linear(blue))
    }

    /// Oklab：与 Lab 思路相同，经过拟合使等步长看起来也等距。`l` 取值范围 0…1。
    private var oklab: (l: Double, a: Double, b: Double) {
        let (r, g, b) = linearComponents
        let long = Self.cubeRoot(0.4122215 * r + 0.5363325 * g + 0.0514460 * b)
        let medium = Self.cubeRoot(0.2119035 * r + 0.6806995 * g + 0.1073970 * b)
        let short = Self.cubeRoot(0.0883025 * r + 0.2817188 * g + 0.6299787 * b)
        return (
            0.2104543 * long + 0.7936178 * medium - 0.0040720 * short,
            1.9779985 * long - 2.4285922 * medium + 0.4505937 * short,
            0.0259040 * long + 0.7827718 * medium - 0.8086758 * short
        )
    }

    /// Oklch 极坐标形式：亮度 `l`、色度 `c` 与色相角度 `h`（度）。
    var oklch: (l: Double, c: Double, h: Double) {
        let oklab = oklab
        return (
            oklab.l, (oklab.a * oklab.a + oklab.b * oklab.b).squareRoot(),
            Self.hueDegrees(oklab.a, oklab.b)
        )
    }

    /// `pow` 在底数为负且指数为分数时无定义，而通道值可能为负。
    private static func cubeRoot(_ value: Double) -> Double {
        value < 0 ? -pow(-value, 1.0 / 3) : pow(value, 1.0 / 3)
    }

    /// 中性色返回 0：仅由两个舍入误差做 `atan2` 也会算出一个方向。
    private static func hueDegrees(_ a: Double, _ b: Double) -> Double {
        guard abs(a) > 1e-6 || abs(b) > 1e-6 else { return 0 }
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// `oklch` 的逆运算：取色器以该空间的色块表示颜色，而不是用十六进制。
    init(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let long = Self.cubed(lightness + 0.3963377774 * a + 0.2158037573 * b)
        let medium = Self.cubed(lightness - 0.1055613458 * a - 0.0638541728 * b)
        let short = Self.cubed(lightness - 0.0894841775 * a - 1.2914855480 * b)
        self.init(
            red: Self.gamma(4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short),
            green: Self.gamma(-1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short),
            blue: Self.gamma(-0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short),
            alpha: alpha)
    }

    private static func cubed(_ value: Double) -> Double { value * value * value }

    /// `linear` 的逆运算；分界点以下的通道可能为负，而 `pow` 会返回 NaN。
    private static func gamma(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}
