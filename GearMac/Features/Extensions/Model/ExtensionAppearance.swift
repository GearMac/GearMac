// 文件职责：定义扩展图标的呈现外观（SF Symbol 名称 + 底色），供 Settings 侧边栏等 UI 展示。
// 分层：Model；保持纯净，仅承载可编解码的纯数据，不 import AppKit/SwiftUI。
import Foundation

/// 扩展图标的原生风格替代物：在一个有底色的色块上放置一个精选符号。
struct ExtensionAppearance: Codable, Equatable, Hashable, Sendable {
    var symbol: String
    var tint: ExtensionTint

    /// 未提供图标时使用的默认外观：拼图符号 + 紫色底。
    static let fallback = ExtensionAppearance(symbol: "puzzlepiece.extension", tint: .purple)
}

/// Settings 侧边栏自有的色板族，使覆盖色显得协调而非突兀。
enum ExtensionTint: String, CaseIterable, Identifiable, Codable, Sendable {
    // 声明顺序即色板排列顺序：先绕色轮一圈，再是大地的中性色。
    case red, maroon, rose, pink, purple, indigo, blue, cyan, teal, mint
    case green, lime, yellow, orange, tan, brown, gray, slate

    var id: String { rawValue }

    /// 作为色板提示（tooltip）展示——单看 "tan" 含义不够明确。
    var title: String {
        switch self {
        case .tan: return "Light Brown"
        case .maroon: return "Maroon"
        case .slate: return "Slate"
        default: return rawValue.capitalized
        }
    }
}
