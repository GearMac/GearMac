// 文件职责：窗口管理设置中的房间库，列出房间并提供新建、进入、挑选窗口、删除、快捷键与启动器可见性开关。
// 分层：UI（SwiftUI 设置区块）；通过 RoomStore 读取、RoomCoordinator 执行副作用，不直接接触窗口。
import SwiftUI

/// 房间库，位于窗口管理设置面板内；房间按窗口管理设置的间距和授权排列窗口。
struct RoomsSection: View {
    @Environment(RoomStore.self) private var store
    @Environment(RoomCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.windowRoomsShowInLauncher) {
                SettingsRowTitle(.windowManagementRooms, settings.text(WindowKey.roomsShowInLauncher))
            }

            if store.rooms.isEmpty {
                Text(settings.text(WindowKey.roomsEmpty))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.rooms) { room in
                    RoomSettingsRow(room: room)
                }
            }

            Button {
                coordinator.createRoom()
            } label: {
                SettingsRowTitle(.windowManagementRooms, settings.text(WindowKey.roomsNew))
            }
        } header: {
            SettingsSectionHeader(.windowManagementRooms)
        }
    }
}

/// 单个房间的快捷键、启动器勾选框与操作按钮，样式与布局行保持一致。
private struct RoomSettingsRow: View {
    let room: Room

    @Environment(RoomCoordinator.self) private var coordinator
    @Environment(VisibilityStore.self) private var visibility
    @Environment(AppSettings.self) private var settings

    /// 副标题：房间内容摘要加它所用布局的标题。
    private var subtitle: String {
        "\(room.localizedSummary(settings.resolvedLanguage)) · "
            + coordinator.layout(of: room).localizedTitle(settings.resolvedLanguage)
    }

    var body: some View {
        SettingsRow(title: room.name, subtitle: subtitle) {
            SymbolImage(name: Room.sfSymbol, size: 13)
        } trailing: {
            ShortcutRecorder(action: .windowRoom(id: room.id))

            Button {
                coordinator.enterRoom(id: room.id)
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.roomsEnterHelp))
            .accessibilityLabel(String(format: settings.text(WindowKey.actionEnter), room.name))

            Button {
                coordinator.editWindows(of: room)
            } label: {
                Image(systemName: "macwindow.badge.plus")
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.roomsChooseHelp))
            .accessibilityLabel(
                String(format: settings.text(WindowKey.actionChooseWindows), room.name))

            Button {
                coordinator.deleteRoom(room)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help(settings.text(WindowKey.actionDelete))
            .accessibilityLabel(String(format: settings.text(WindowKey.actionDelete), room.name))

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(format: settings.text(WindowKey.actionShowInLauncher), room.name))
        }
    }

    /// 把房间包装为 AppEntry 后读写 VisibilityStore，与应用索引发布的键保持一致。
    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(room)) },
            set: { visibility.setItemVisible($0, for: AppEntry(room)) })
    }
}
