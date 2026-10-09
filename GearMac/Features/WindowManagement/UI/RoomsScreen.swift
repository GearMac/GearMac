// 文件职责：Rooms 屏幕（切换房间），定义 PaletteScreen 的交互（↵ 进入、⇥ 切布局、⌘⌫ 删除、新建）与预览联动。
// 分层：UI（PaletteScreen）；遵照调色板屏协议，状态与副作用均委托给 RoomCoordinator / RoomSession。
// 改编自 Rooms (MIT)：https://github.com/saragordic/rooms/blob/main/LICENSE
import SwiftUI

/// 切换房间：房间按搜索排序，选中的房间会预览；⇥ 尝试切换布局。
struct RoomsScreen: PaletteScreen {
    let coordinator: RoomCoordinator
    let session: RoomSession
    let vm: PaletteState

    /// 当前筛选后的房间行列表。
    var rows: [RoomRow] { coordinator.rows(for: vm.query) }

    /// 主操作标题：根据行类型显示进入房间、选择窗口或新建房间。
    var primaryActionTitle: String {
        let language = coordinator.language
        switch row(at: vm.selection) {
        case .edit: return L10n.string(WindowKey.roomsScreenChooseWindows, language: language)
        case .create: return L10n.string(WindowKey.roomsScreenCreateRoom, language: language)
        case .room, nil: return L10n.string(WindowKey.roomsScreenEnterRoom, language: language)
        }
    }

    /// 取选中位置对应的行，越界时为 nil。
    private func row(at selection: Int) -> RoomRow? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 取选中位置对应的房间，非房间行时为 nil。
    private func room(at selection: Int) -> Room? {
        guard case .room(let room) = row(at: selection) else { return nil }
        return room
    }

    /// 仅房间行提供操作菜单。
    func hasActions(at selection: Int) -> Bool { room(at: selection) != nil }

    /// ↵：根据行类型进入房间、编辑其窗口或新建房间。
    func activate(at selection: Int) {
        switch row(at: selection) {
        case .room(let room): coordinator.enterRoom(id: room.id)
        case .edit(let room): coordinator.editWindows(of: room)
        case .create(let name): coordinator.createRoom(named: name)
        case nil: break
        }
    }

    /// 该屏幕不使用 ⌘↵ 主操作（保留为默认行为）。
    func secondary(at selection: Int) -> Bool { false }

    /// 该屏幕完全接管 ⇥：在房间上切换布局，其他行上不执行任何操作。
    func tab(at selection: Int, backwards: Bool) -> Bool {
        if let room = room(at: selection) { coordinator.cycleLayout(of: room, backwards: backwards) }
        return true
    }

    /// 处理自定义快捷键：⌘⌫ 删除房间，新建项创建房间。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete:
            guard let room = room(at: selection) else { return false }
            coordinator.deleteRoom(room)
            return true
        case .newItem:
            coordinator.createRoom(named: vm.query.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        default:
            return false
        }
    }

    /// 房间行的操作菜单：进入、下一布局、记住排布、选择窗口与删除。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let room = room(at: selection) else { return nil }
        return PopoverMenuContent(
            header: room.name,
            items: [
                PopoverMenuItem(
                    title: L10n.string(WindowKey.roomsScreenEnterRoom, language: coordinator.language),
                    systemImage: Room.sfSymbol, shortcut: "↵"
                ) {
                    coordinator.enterRoom(id: room.id)
                },
                PopoverMenuItem(
                    title: L10n.string(WindowKey.roomsScreenNextLayout, language: coordinator.language),
                    systemImage: "rectangle.3.group", shortcut: "⇥"
                ) {
                    coordinator.cycleLayout(of: room, backwards: false)
                },
                PopoverMenuItem(
                    title: L10n.string(WindowKey.roomsScreenRemember, language: coordinator.language),
                    systemImage: "rectangle.dashed.badge.record",
                    startsSection: true
                ) {
                    coordinator.rememberArrangement(of: room)
                },
                PopoverMenuItem(
                    title: L10n.string(
                        WindowKey.roomsScreenChooseWindowsEllipsis, language: coordinator.language),
                    systemImage: "macwindow.badge.plus"
                ) {
                    coordinator.editWindows(of: room)
                },
                PopoverMenuItem(
                    title: L10n.string(WindowKey.roomsScreenDeleteRoom, language: coordinator.language),
                    systemImage: "trash", startsSection: true, shortcut: "⌘⌫",
                    isDestructive: true
                ) {
                    coordinator.deleteRoom(room)
                }
            ])
    }

    /// 屏幕主体：渲染内容，并在选中房间或其修订号变化时刷新预览。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        let selected = rows.indices.contains(selection) ? rows[selection] : nil
        let previewed = selected.flatMap { row -> Room? in
            guard case .room(let room) = row else { return nil }
            return room
        }
        return AnyView(
            content(rows: rows, selectedID: selected?.id, scroll: scroll)
                // 房间值携带其布局，因此 Tab 的变更也会让预览滑动。
                .onChange(of: PreviewKey(room: previewed, revision: session.revision), initial: true) {
                    coordinator.preview(previewed)
                })
    }

    /// 屏幕内容：无房间时提示输入名称，否则渲染房间列表。
    @ViewBuilder
    private func content(rows: [RoomRow], selectedID: RoomRow.ID?, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            EmptyResults(
                text: L10n.string(WindowKey.roomsScreenEmpty, language: coordinator.language))
        } else {
            RoomsList(
                rows: rows, selectedID: selectedID, scroll: scroll,
                currentRoomID: coordinator.currentRoomID, layout: coordinator.layout(of:),
                onActivate: { row in
                    guard let index = rows.firstIndex(of: row) else { return }
                    activate(at: index)
                })
        }
    }

    /// 预览刷新的触发键：房间值与会话修订号任意变化即重绘预览。
    private struct PreviewKey: Equatable {
        let room: Room?
        let revision: Int
    }
}
