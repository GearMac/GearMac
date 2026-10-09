// 文件职责：定义启动器的颜色卡片视图（色样 + 主记法 + 说明），以及颜色卡片的「复制为…」操作菜单。
// 分层：UI；颜色格式与展示文案来自 ColorValue/ColorFormat，不在本文件内计算。
import SwiftUI

/// 启动器的颜色卡片：复用计算器卡片的组件拼成，从而读起来像同一个答案。
struct ColorCard: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    let selected: Bool

    /// 宽度足以被读作色样，又窄到不会被误认为卡片背景。
    private static let swatchWidth: CGFloat = 108

    /// 展示与复制使用同一种记法，因此按 ↵ 不会复制出卡片未显示的颜色。
    private var primary: ColorFormat { ColorFormat.primary(for: color) }

    /// 左侧主记法与徽标，右侧色样；上下留白使其与计算器卡片一致。
    var body: some View {
        HStack(spacing: 0) {
            LeadCardColumn(
                text: AttributedString(primary.string(for: color)), badge: primary.title)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
            // 拉伸填满数值列而非固定尺寸：没有任何记法拥有固定高度。
            ColorSwatch(color: color, cornerRadius: metrics.radius.card)
                .frame(width: Self.swatchWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, metrics.spacing.md)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxxl)
        .leadCard(selected: selected)
    }
}

/// 颜色卡片的操作菜单：动词已在标题中给出，因此每行只需展示其记法。
@MainActor
enum ColorActionsMenu {
    /// 为给定颜色构建「复制为…」菜单，每行对应一种颜色记法，主记法带 ↵ 快捷键。
    static func content(color: ColorValue, core: AppCore) -> PopoverMenuContent {
        let primary = ColorFormat.primary(for: color)
        return PopoverMenuContent(
            header: core.settings.text(LauncherKey.copyColorAs),
            items: ColorFormat.offered(for: color).map { format in
                PopoverMenuItem(
                    title: format.title, icon: .blank,
                    shortcut: format == primary ? "↵" : nil, detail: format.string(for: color)
                ) {
                    core.clipboardCoordinator.copyColor(color, as: format)
                }
            })
    }
}
