// 文件职责：提供启动器栏位与窗口头部共用的按钮控件（BarButton、HeaderMenuButton）及其悬停外观样式。
// 分层：UI（DesignSystem）；纯 SwiftUI 视图，只消费 `InterfaceMetrics` 与 `Theme`，不持有业务状态。
import SwiftUI

/// AppKit 会直接解析指定的基础符号名，因此不会继承按钮自身的变体（variant）。
private struct HeaderMenuSymbol: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let image = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name), accessibilityDescription: nil
        )?
        .withSymbolConfiguration(configuration) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: size, height: size)
        }
    }
}

/// 栏位控件的悬停外观；底部胶囊按钮与头部弹出菜单同属 `barControl` 一族圆角尺寸。
enum BarButtonChrome {
    case capsule
    case rounded

    /// 返回该外观样式对应的形状，圆角取自 `InterfaceMetrics` 的栏位控件半径。
    func shape(_ metrics: InterfaceMetrics) -> AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .rounded:
            return AnyShape(
                RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous))
        }
    }
}

/// 命令面板栏位控件，未悬停时无背景；悬停状态由自身持有，因此其调用方不会因悬停而重新渲染。
struct BarButton<Label: View>: View {
    var chrome: BarButtonChrome = .capsule
    var isSelected = false
    /// 使用 `sm` 内边距，使 16pt 字形加上内边距后成为与栏位等高的正方形。
    var isCompact = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = chrome.shape(metrics)
        return Button(action: action) {
            label
                .padding(.horizontal, isCompact ? metrics.spacing.sm : metrics.spacing.md)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    /// 选中态优先于悬停态，这是所有行共同遵循的规则。
    private var fill: Color {
        if isSelected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : Color.clear
    }
}

/// 头部控件：显示当前选项，并打开窗口内菜单。
struct HeaderMenuButton: View {
    let title: String
    let icon: PopoverMenuIcon
    /// 符号缩放前的字号；当菜单紧邻品牌图标时，则改用品牌图标的尺寸。
    let symbolSize: CGFloat
    let isOpen: Bool
    let help: String
    let action: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String, icon: PopoverMenuIcon, symbolSize: CGFloat = Theme.Typography.menuSymbolSize,
        isOpen: Bool, help: String, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.symbolSize = symbolSize
        self.isOpen = isOpen
        self.help = help
        self.action = action
    }

    /// 便捷初始化器：以 SF Symbol 名称而非 `PopoverMenuIcon` 指定图标。
    init(
        title: String, systemImage: String, symbolSize: CGFloat = Theme.Typography.menuSymbolSize,
        isOpen: Bool, help: String, action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), symbolSize: symbolSize, isOpen: isOpen,
            help: help, action: action)
    }

    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            HStack(spacing: metrics.spacing.sm) {
                switch icon {
                case .blank:
                    EmptyView()
                case .symbol(let name):
                    HeaderMenuSymbol(name: name, size: metrics.scaled(symbolSize))
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: metrics.size.barBrandIcon, height: metrics.size.barBrandIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                case .thumbnail(let id, let data):
                    MenuThumbnail(id: id, data: data)
                case .dot(let color):
                    ColorDot(color: color)
                }
                Text(title)
                    .font(metrics.typography.bar)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // 使用同一个字形旋转而非替换图标，因此展开菜单不会引起布局位移。
                Image(systemName: "chevron.down")
                    .font(metrics.typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help(help)
    }
}
