// 文件职责：定义窗口布局的 3×3 锚点位置枚举，并负责其与 Anchor 轴对的互相映射。
// 分层：Model；保持纯净，仅依赖 CoreGraphics，原始值显式拼写以免重命名影响存储格式。
import CoreGraphics

/// 3×3 位置网格。原始值显式写出，这样重命名 case 不会跟着改写已存储的值。
enum WindowLayoutAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft = "top-left"
    case top
    case topRight = "top-right"
    case left
    case center
    case right
    case bottomLeft = "bottom-left"
    case bottom
    case bottomRight = "bottom-right"

    /// `place(_:in:)` 仍是代码库中唯一的锚点运算；这里只是它的拼写。
    var placement: WindowPlacementEngine.Anchor {
        WindowPlacementEngine.Anchor(horizontal: horizontal, vertical: vertical)
    }

    /// 网格按钮的无障碍标签，也是设置行显示的名称。
    /// 英文兜底：供无语言上下文（如测试）使用；界面请用 `localizedTitle(_:)`。
    var title: String { localizedTitle(.english) }

    /// 按语言取显示名称。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .topLeft: return L10n.string(WindowKey.anchorTopLeft, language: language)
        case .top: return L10n.string(WindowKey.anchorTop, language: language)
        case .topRight: return L10n.string(WindowKey.anchorTopRight, language: language)
        case .left: return L10n.string(WindowKey.anchorLeft, language: language)
        case .center: return L10n.string(WindowKey.anchorCenter, language: language)
        case .right: return L10n.string(WindowKey.anchorRight, language: language)
        case .bottomLeft: return L10n.string(WindowKey.anchorBottomLeft, language: language)
        case .bottom: return L10n.string(WindowKey.anchorBottom, language: language)
        case .bottomRight: return L10n.string(WindowKey.anchorBottomRight, language: language)
        }
    }

    private var horizontal: WindowPlacementEngine.Anchor.Axis {
        switch self {
        case .topLeft, .left, .bottomLeft: return .min
        case .top, .center, .bottom: return .center
        case .topRight, .right, .bottomRight: return .max
        }
    }

    /// `.min` 就是顶部，因为此处每个 frame 所在的 AX 空间里 +Y 向下。
    private var vertical: WindowPlacementEngine.Anchor.Axis {
        switch self {
        case .topLeft, .top, .topRight: return .min
        case .left, .center, .right: return .center
        case .bottomLeft, .bottom, .bottomRight: return .max
        }
    }

    /// 轴对映射回 case 的唯一位置，保证网格与 `describe` 一致。
    static func named(
        horizontal: WindowPlacementEngine.Anchor.Axis, vertical: WindowPlacementEngine.Anchor.Axis
    ) -> WindowLayoutAnchor {
        switch (horizontal, vertical) {
        case (.min, .min): return .topLeft
        case (.center, .min): return .top
        case (.max, .min): return .topRight
        case (.min, .center): return .left
        case (.center, .center): return .center
        case (.max, .center): return .right
        case (.min, .max): return .bottomLeft
        case (.center, .max): return .bottom
        case (.max, .max): return .bottomRight
        }
    }
}
