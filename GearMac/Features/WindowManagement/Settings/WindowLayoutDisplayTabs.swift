// 文件职责：窗口布局编辑器中的显示器页签（WindowLayoutDisplayTabs）与 3×3 锚点网格（WindowLayoutPositionGrid）。
// 分层：UI（SwiftUI 设置控件）；仅操作 WindowLayoutDraft，不直接读写屏幕与存储。
import SwiftUI

/// 带编号的显示器页签：既限定画布范围，也决定新增条目的目标显示器。
struct WindowLayoutDisplayTabs: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(displays.enumerated()), id: \.element.uuid) { index, display in
                tab(display, ordinal: index + 1)
            }
        }
        .accessibilityLabel(settings.text(WindowKey.tabsDisplay))
    }

    /// 单个页签：序号加选中态描边，点击后切换草稿选中的显示器。
    private func tab(_ display: WindowLayoutDisplay, ordinal: Int) -> some View {
        let isSelected = draft.selectedDisplayUUID == display.uuid
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        return Button {
            draft.select(displayUUID: display.uuid)
        } label: {
            Text("\(ordinal)")
                .font(Theme.Typography.keyCap)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: Theme.Size.layoutDisplayTab, height: Theme.Size.layoutDisplayTab)
                .background(shape.fill(Theme.Colors.controlSurface))
                .overlay(shape.stroke(isSelected ? Color.accentColor : Theme.Colors.border))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(display.name)
        .accessibilityLabel(
            String(format: settings.text(WindowKey.tabsDisplayLabel), ordinal, display.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 3×3 锚点控件：九个格子，每个格画出窗口将占据的屏幕位置。
struct WindowLayoutPositionGrid: View {
    let selection: WindowLayoutAnchor
    /// 点击某个锚点时的回调。
    let onSelect: (WindowLayoutAnchor) -> Void

    @Environment(AppSettings.self) private var settings

    /// 按阅读顺序三行三列排列，保证网格与枚举不会不一致。
    private static let rows: [[WindowLayoutAnchor]] = [
        [.topLeft, .top, .topRight], [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight]
    ]

    var body: some View {
        Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Spacing.xs) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { cell($0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(settings.text(WindowKey.fieldPosition))
    }

    /// 单个格子：用遮罩画出该锚点的覆盖形状，选中时高亮底衬。
    private func cell(_ anchor: WindowLayoutAnchor) -> some View {
        let isSelected = anchor == selection
        let outline = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let glyph = Theme.Size.layoutPositionGlyph
        let fillInset = Theme.Spacing.xxs
        let fillSize = CGSize(
            width: glyph.width - fillInset * 2,
            height: glyph.height - fillInset * 2)
        let seat = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return Button {
            onSelect(anchor)
        } label: {
            ZStack {
                outline.stroke(lineWidth: Theme.Size.layoutPositionStroke)
                if anchor == .center {
                    RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                        .frame(
                            width: fillSize.width * anchor.coverage.width,
                            height: fillSize.height * anchor.coverage.height)
                } else {
                    outline
                        .inset(by: fillInset)
                        .mask(alignment: anchor.alignment) {
                            Rectangle()
                                .frame(
                                    width: glyph.width * anchor.coverage.width,
                                    height: glyph.height * anchor.coverage.height)
                        }
                }
            }
            .frame(width: glyph.width, height: glyph.height)
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            // 图标浮动在更宽的底衬中，因此点击格子任意位置都能命中它。
            .frame(maxWidth: .infinity, minHeight: Theme.Size.layoutPositionCell)
            .background(seat.fill(isSelected ? Theme.Colors.selection : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(anchor.localizedTitle(settings.resolvedLanguage))
        .accessibilityLabel(anchor.localizedTitle(settings.resolvedLanguage))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 借用 SwiftUI 自身的 alignment，因此不必放进 `Model/` 也不会触犯纯净性检查。
extension WindowLayoutAnchor {
    /// 方块覆盖画板的比例：单侧贴边的轴占一半，跨满的轴占全部。
    fileprivate var coverage: CGSize {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight, .center:
            return CGSize(width: 0.5, height: 0.5)
        case .top, .bottom: return CGSize(width: 1, height: 0.5)
        case .left, .right: return CGSize(width: 0.5, height: 1)
        }
    }

    /// 该锚点对应的 SwiftUI 对齐方式，用于把覆盖形状贴到正确一侧。
    fileprivate var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .top: return .top
        case .topRight: return .topTrailing
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottom: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }
}
