// 文件职责：为扩展的 `ExtensionTint` 提供实际绘制颜色（SwiftUI `Color` 与 AppKit `NSColor`）及符号着色。
// 分层：UI；依赖 AppKit/SwiftUI，与仅依赖 Foundation 的 `Model/` 类型定义分离。
import AppKit
import SwiftUI

/// 颜色主题实际用于绘制的取值。与 `Model/` 中的类型定义分开，以保持后者仅依赖 Foundation。
extension ExtensionTint {
    /// 使用固定 sRGB 值：图块在主线程之外栅格化，动态颜色在那里的解析结果不正确。
    private var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: return (1.00, 0.27, 0.23)
        case .maroon: return (0.62, 0.24, 0.24)
        case .rose: return (1.00, 0.45, 0.53)
        case .pink: return (1.00, 0.22, 0.37)
        case .purple: return (0.75, 0.35, 0.95)
        case .indigo: return (0.37, 0.36, 0.90)
        case .blue: return (0.04, 0.52, 1.00)
        case .cyan: return (0.39, 0.82, 1.00)
        case .teal: return (0.25, 0.78, 0.88)
        case .mint: return (0.40, 0.83, 0.81)
        case .green: return (0.20, 0.84, 0.29)
        case .lime: return (0.64, 0.86, 0.24)
        case .yellow: return (1.00, 0.84, 0.04)
        case .orange: return (1.00, 0.62, 0.04)
        case .tan: return (0.84, 0.70, 0.52)
        case .brown: return (0.67, 0.53, 0.38)
        case .gray: return (0.60, 0.60, 0.62)
        case .slate: return (0.44, 0.50, 0.58)
        }
    }

    /// SwiftUI 侧的 `Color` 表示。
    var color: Color {
        let rgb = components
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// `IconCache` 实际使用的绘制颜色 —— 同样的数值，以 AppKit 的形式呈现。
    var nsColor: NSColor {
        let rgb = components
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// 用于 SF Symbol 的着色描述。
    var symbolTint: SymbolTint { SymbolTint(key: rawValue, color: nsColor) }
}
