// 文件职责：提供外观（深色/浅色）判断与 sRGB 墨水色构造的小型扩展。
// 分层：Service；仅依赖 AppKit，不持有状态。
import AppKit

extension NSAppearance {
    /// 用 `bestMatch` 而非名称比较，使鲜艳色与无障碍变体也能正确解析。
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// 在 sRGB 中构造，即 `Color.white` 解析到的空间，使深色分支得到相同像素。
    static func srgbInk(_ white: CGFloat, alpha: Double) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }
}
