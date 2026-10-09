// 文件职责：定义 `Grid` 组件的布局属性（列数、瓦片宽高比、填充方式与内容内缩），并从渲染节点解析这些属性。
// 分层：Model；仅做值对象计算与节点字段解析，不 import AppKit/SwiftUI。
import Foundation

/// `Grid` 的布局属性：瓦片形状以及条目内容在其中的摆放方式。
struct ExtensionGridLayout: Equatable, Sendable {
    /// 瓦片边框与其内容之间的内缩。Raycast 随瓦片一起缩放它，这里同样如此。
    enum Inset: String, Sendable {
        case zero
        case small = "sm"
        case medium = "md"
        case large = "lg"

        /// 内缩相对于瓦片边长的比例。
        var fraction: Double {
            switch self {
            case .zero: return 0
            case .small: return 0.08
            case .medium: return 0.16
            case .large: return 0.24
            }
        }
    }

    /// 瓦片自身的圆角半径，归属于此类型而非 `Theme`：启动器界面没有这个尺寸的元素。
    static let tileRadius: Double = 12

    /// Raycast 会将其限制在 1…8。
    var columns: Int
    /// 瓦片宽度 ÷ 高度。
    var aspectRatio: Double
    /// `Grid.Fit.Fill` 将内容裁剪到瓦片；`.Contain` 则将其完整放入。
    var fills: Bool
    var inset: Inset

    /// 用显式参数构造，并对列数与宽高比做有效范围限制。
    init(columns: Int = 5, aspectRatio: Double = 1, fills: Bool = false, inset: Inset = .zero) {
        self.columns = min(max(columns, 1), 8)
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
        self.fills = fills
        self.inset = inset
    }

    /// 从渲染节点的属性中解析出布局配置。
    init(_ root: RenderNode) {
        self.init(
            columns: ExtensionGridLayout.columns(root),
            aspectRatio: ExtensionGridLayout.ratio(root.string("aspectRatio")) ?? 1,
            fills: root.string("fit") == "fill",
            inset: root.string("inset").flatMap(Inset.init(rawValue:)) ?? .zero)
    }

    /// 给定网格可用宽度时求瓦片宽度，使一次测量可供给每个单元格。
    func tileWidth(inWidth width: Double, spacing: Double) -> Double {
        max(1, (width - spacing * Double(columns - 1)) / Double(columns))
    }

    /// 解析列数：优先用 `columns`，否则回退到旧式的 `itemSize`。
    private static func columns(_ root: RenderNode) -> Int {
        if let columns = root.double("columns").map({ Int($0) }), columns > 0 { return columns }
        // Raycast 的默认值是 5；`itemSize` 是表达同一含义的旧式属性。
        switch root.string("itemSize") {
        case "small": return 8
        case "large": return 3
        default: return 5
        }
    }

    /// `aspectRatio` 以 `"1"` 或 `"16/9"` 这类字符串传入。
    private static func ratio(_ text: String?) -> Double? {
        guard let text else { return nil }
        let parts = text.split(separator: "/").compactMap { Double($0) }
        switch parts.count {
        case 1: return parts[0] > 0 ? parts[0] : nil
        case 2: return parts[0] > 0 && parts[1] > 0 ? parts[0] / parts[1] : nil
        default: return nil
        }
    }
}
