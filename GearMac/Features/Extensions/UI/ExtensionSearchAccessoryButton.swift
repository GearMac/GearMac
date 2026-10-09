// 文件职责：把扩展的搜索栏下拉（searchBarAccessory）绘制为头部控件按钮。
// 分层：UI；只负责展示当前选项与图标，点击行为由外部 action 回调决定。
import SwiftUI

/// 扩展的搜索栏下拉，以头部控件的形式绘制。未复用 `HeaderMenuButton`：
/// 它展示的选项携带扩展自己的图标，而 `PopoverMenuIcon` 无法表达。
struct ExtensionSearchAccessoryButton: View {
    @Environment(\.metrics) private var metrics
    /// 为图标与勾选标记旁的长选项预留空间，同时避免表单字段 360pt 的过度铺展。
    static let listWidth: CGFloat = 240

    let accessory: ExtensionSearchAccessory
    /// 当前持有的选项；仅在首次提交写入之前为 nil。
    let value: String?
    let assetsPath: String?
    let isOpen: Bool
    let action: () -> Void

    /// 从视图环境读取，使界面外观切换时已解析的图标能够重绘。
    @Environment(\.isDarkAppearance) private var isDark

    /// 按钮主体：图标、选项标题与展开箭头。
    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            HStack(spacing: metrics.spacing.sm) {
                if let icon {
                    ExtensionIconView(
                        resolved: icon, size: metrics.size.menuIcon, usesMenuSymbolStyle: true)
                }
                Text(accessory.title(for: value) ?? "")
                    .font(metrics.typography.bar)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // 面板始终在头部下方展开，因此箭头不会翻转朝上。
                ExtensionDisclosureChevron(open: isOpen)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help("\(accessory.tooltip ?? accessory.placeholder ?? "Filter")  ⌘P")
    }

    /// 按当前选项解析出的图标。
    private var icon: ExtensionImage.Resolved? {
        ExtensionImage.resolve(
            accessory.item(for: value)?.iconValue, assetsPath: assetsPath, isDark: isDark)
    }
}
