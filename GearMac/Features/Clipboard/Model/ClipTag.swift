// 文件职责：定义用户创建的剪贴板标签（名称即主键，颜色以 hex 记法存储）与内置色板。
// 分层：Model；纯值类型，仅 Foundation。
import Foundation

/// 用户创建的标签：名称即主键，颜色以 `#RRGGBB` 记法存储且可被 `ColorValue` 解析。
struct ClipTag: Identifiable, Hashable, Sendable {
    let name: String
    let colorHex: String

    var id: String { name }
}

/// 新建标签可选的内置色板；取中等明度，使白色文字在任意色上均可读。
enum ClipTagPalette {
    static let hexes: [String] = [
        "#E5484D", "#F76B15", "#FFB224", "#46A758",
        "#00B2A9", "#0091FF", "#6E56CF", "#D6409F"
    ]
}
