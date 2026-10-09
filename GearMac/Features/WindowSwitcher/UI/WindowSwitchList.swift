// 文件职责：窗口切换器的列表视图，渲染可切换窗口行并展示应用图标、标题与最小化状态。
// 分层：UI（SwiftUI 视图）；仅负责展示与点击回调，业务状态由 WindowSwitchSession 提供。
import SwiftUI

/// 窗口切换器的条目列表：可滚动、跟随选中项，并将点击回调交给上层。
struct WindowSwitchList: View {

    @Environment(\.metrics) private var metrics
    let entries: [WindowSwitchEntry]
    let selectedID: WindowSwitchEntry.ID?
    let scroll: ScrollIntent
    let onActivate: (WindowSwitchEntry) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == entries.first?.id
    }

    /// 列表主体：渲染所有条目，应用选中样式与滚动跟随。
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        WindowSwitchRow(entry: entry, selected: entry.id == selectedID)
                            .selectionFrame(entry.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(entry) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// 窗口切换器中的单行视图：应用图标、窗口标题与所属应用名。
private struct WindowSwitchRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let entry: WindowSwitchEntry
    let selected: Bool
    @State private var hovered = false

    /// 行背景色：选中 > 悬停 > 透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// 行尾部说明：应用名，最小化时括注状态。
    private var trailing: String {
        entry.isMinimized
            ? "\(entry.appName) · \(settings.text(WindowSwitcherKey.minimized))" : entry.appName
    }

    /// 行主体：图标 + 标题 + 尾部文字，并在最小化时降低透明度。
    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let iconURL = entry.iconURL {
                    EntryIconView(source: .file(stamp: entry.iconStamp), fileURL: iconURL)
                } else {
                    EntryIconView(source: .symbol("macwindow"))
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            .opacity(entry.isMinimized ? 0.5 : 1)
            Text(entry.displayTitle)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(entry.isMinimized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: metrics.spacing.md)
            Text(trailing)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.displayTitle)
        .accessibilityValue(trailing)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
