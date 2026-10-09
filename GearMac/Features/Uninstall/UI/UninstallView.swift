// 文件职责：卸载列表的视图层，渲染带有摘要标题、勾选框、位置、来源证据与文件图标的行。
// 分层：UI（SwiftUI）；只负责展示与回调转发，选中/勾选状态由 UninstallSession 与 UninstallScreen 持有。
import AppKit
import SwiftUI

/// 卸载结果列表，包含摘要分节标题与惰性加载的条目行。
struct UninstallList: View {

    @Environment(\.metrics) private var metrics
    let results: [UninstallCandidate]
    let selectedID: UninstallCandidate.ID?
    let summary: String
    /// 仅在键盘导航或重置时变化，因此鼠标选中不会拽动滚动位置。
    let scroll: ScrollIntent
    let onSelect: (UninstallCandidate) -> Void
    let onToggle: (UninstallCandidate) -> Void
    let onActions: (UninstallCandidate) -> Void
    @Environment(UninstallSession.self) private var session

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: summary, isFirst: true)
                    ForEach(results) { candidate in
                        UninstallRow(
                            candidate: candidate,
                            selected: candidate.id == selectedID,
                            checked: session.selection?.isChecked(candidate.id) ?? false,
                            onToggle: { onToggle(candidate) }
                        )
                        .id(candidate.id)
                        .selectionFrame(candidate.id == selectedID)
                        .contentShape(Rectangle())
                        // 使用 simultaneous 手势，使单击选中不必等待双击判定。
                        .onTapGesture { onSelect(candidate) }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                onSelect(candidate)
                                onToggle(candidate)
                            }
                        )
                        .onRightClick { onActions(candidate) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // 选中第一行时回到顶部原点，让摘要标题也一并显示。
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        .onDisappear { IconCache.purgeFitted() }
    }
}

/// 列表中的单行：勾选框、名称、位置、证据标签、大小与文件图标。
private struct UninstallRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let candidate: UninstallCandidate
    let selected: Bool
    let checked: Bool
    let onToggle: () -> Void
    @State private var hovered = false

    /// 一行同时被选中和悬停时，选中态优先。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var glyph: String {
        if candidate.isLocked { return "lock.fill" }
        return checked ? "checkmark.square.fill" : "square"
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            // 更小的字形占用与结果行相同的槽位，使各模式下标题对齐在同一条 x 轴上。
            SymbolImage(name: glyph, size: metrics.size.checkbox)
                .foregroundStyle(candidate.isLocked ? Theme.Colors.textTertiary : .primary)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .contentShape(Rectangle())
                // 只有勾选框负责切换勾选，行的其余部分用于选中。
                .onTapGesture(perform: onToggle)
                .tooltip(candidate.localizedLockReason(settings.resolvedLanguage))
            Text(candidate.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .layoutPriority(1)
            Text(candidate.locationLabel)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let label = candidate.evidence.localizedLabel(settings.resolvedLanguage) {
                Text(label)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            Text(candidate.size?.formatted ?? "")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
            FileIconView(path: candidate.path)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
        }
        .opacity(candidate.isLocked ? 0.55 : 1)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// 文件图标视图：先取缓存，未命中时异步加载并回填。
private struct FileIconView: View {

    @Environment(\.metrics) private var metrics
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cachedFitted(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        .task(id: IconRequest(path)) {
            if let warm = IconCache.cachedFitted(forFile: path) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: path)
        }
    }
}
