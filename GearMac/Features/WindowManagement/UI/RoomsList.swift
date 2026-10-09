// 文件职责：Rooms 界面的房间列表视图，渲染房间/编辑/新建行并展示当前房间标记与布局提示。
// 分层：UI（SwiftUI 视图）；仅负责展示与点击回调，业务状态由 RoomCoordinator 提供。
import SwiftUI

/// Rooms 界面的房间列表：可滚动、跟随选中项，并将点击回调交给上层。
struct RoomsList: View {
    @Environment(\.metrics) private var metrics
    let rows: [RoomRow]
    let selectedID: RoomRow.ID?
    let scroll: ScrollIntent
    let currentRoomID: UUID?
    let layout: (Room) -> RoomLayoutKind
    let onActivate: (RoomRow) -> Void

    private var firstRowSelected: Bool { selectedID != nil && selectedID == rows.first?.id }

    /// 列表主体：渲染所有行，应用选中样式与滚动跟随。
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RoomRowView(
                            row: row, selected: row.id == selectedID,
                            isCurrent: row.room?.id == currentRoomID,
                            layout: row.room.map(layout)
                        )
                        .selectionFrame(row.id == selectedID)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(row) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// Rooms 列表中的单行视图：应用图标、标题、副标题与布局提示（仅选中行显示快捷键）。
private struct RoomRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let row: RoomRow
    let selected: Bool
    let isCurrent: Bool
    /// 对新建或编辑房间（而非进入房间）的行，该值为 nil。
    let layout: RoomLayoutKind?
    @State private var hovered = false

    /// 行背景色：选中 > 悬停 > 透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// 行主标题：房间名，或编辑/新建房间的操作标题。
    private var title: String {
        switch row {
        case .room(let room): room.name
        case .edit(let room):
            String(
                format: settings.text(WindowKey.roomsListChooseWindowsFor), room.name)
        case .create(let name):
            String(format: settings.text(WindowKey.roomsListCreateRoomNamed), name)
        }
    }

    /// 行副标题：房间为「当前标记 + 概要 + 去重后的应用名」组合，编辑/新建行为固定提示。
    private var subtitle: String {
        switch row {
        case .room(let room):
            let apps = room.windows.map(\.appName).reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }
            return (
                [isCurrent ? settings.text(WindowKey.roomsListCurrent) : nil,
                    room.localizedSummary(settings.resolvedLanguage)]
                    + [apps.joined(separator: ", ")]
            )
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .edit, .create:
            return settings.text(WindowKey.roomsListEditSubtitle)
        }
    }

    /// 行图标：根据行类型选择房间、编辑或新建的 SF Symbol。
    private var symbol: String {
        switch row {
        case .room: Room.sfSymbol
        case .edit: "macwindow.badge.plus"
        case .create: CommandID.createRoom.sfSymbol
        }
    }

    /// 行主体：图标 + 标题/副标题 + 布局提示，并设置无障碍信息。
    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            EntryIconView(source: .symbol(symbol))
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            if let layout {
                HStack(spacing: metrics.spacing.sm) {
                    Text(layout.localizedTitle(settings.resolvedLanguage))
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                    // Tab 会切换所选房间的布局，因此只有该行提示这个快捷键。
                    if selected { KeyCapChip(text: "⇥", style: .outline) }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            layout.map {
                String(
                    format: settings.text(WindowKey.roomsListAccessibilityLayout), subtitle,
                    $0.localizedTitle(settings.resolvedLanguage))
            } ?? subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension RoomRow {
    /// 仅当该行为房间行时返回其 Room，否则返回 nil。
    fileprivate var room: Room? {
        guard case .room(let room) = self else { return nil }
        return room
    }
}
