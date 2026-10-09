// 文件职责：房间窗口选择器屏幕，定义选择器行模型（RoomPickerRow）并实现 PaletteScreen 交互（过滤、添加/移除、保存进入）。
// 分层：UI（PaletteScreen）；遵照调色板屏协议，状态与副作用均委托给 RoomCoordinator / RoomSession。
// 改编自 Rooms (MIT)：https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation
import SwiftUI

/// 选择器的一行：一个已打开的窗口，或一个无需打开窗口即可加入房间的 App。
enum RoomPickerRow: Identifiable {
    case window(RoomLiveWindow)
    case app(RoomSession.App)

    var id: String {
        switch self {
        case .window(let window): "window:\(window.handle)"
        case .app(let app): "app:" + app.bundleID
        }
    }

    /// 该行对应的选入项（窗口句柄或 App）。
    var pick: RoomSession.Pick {
        switch self {
        case .window(let window): .window(handle: window.handle)
        case .app(let app): .app(app)
        }
    }
}

/// 选择房间成员：输入框过滤，↵ 添加或移除一项，⌘↵ 保存并进入。
struct RoomPickerScreen: PaletteScreen {
    let coordinator: RoomCoordinator
    let session: RoomSession
    let vm: PaletteState

    /// 当前筛选后的行列表。
    var rows: [RoomPickerRow] { coordinator.pickerRows(for: vm.query) }

    /// 主操作标题：根据选中项是否已在房间中，显示「加入」或「移除」。
    var primaryActionTitle: String {
        let rows = rows
        let name = "“\(session.roomName)”"
        let language = coordinator.language
        guard rows.indices.contains(vm.selection) else {
            return String(format: L10n.string(WindowKey.roomPickerAddTo, language: language), name)
        }
        return session.picked.contains(rows[vm.selection].pick)
            ? String(
                format: L10n.string(WindowKey.roomPickerRemoveFrom, language: language), name)
            : String(format: L10n.string(WindowKey.roomPickerAddTo, language: language), name)
    }

    /// ↵：切换选中项的入/出房间状态。
    func activate(at selection: Int) {
        let rows = rows
        guard rows.indices.contains(selection) else { return }
        coordinator.togglePick(rows[selection].pick)
    }

    /// ⌘↵：保存所选成员并进入房间。
    func secondary(at selection: Int) -> Bool {
        coordinator.savePicked()
        return true
    }

    /// ⇥ 原本会离开并跳到启动器，从而丢弃已选内容，因此这里拦截它。
    func tab(at selection: Int, backwards: Bool) -> Bool { true }

    func actions(at selection: Int) -> PopoverMenuContent? {
        PopoverMenuContent(
            header: session.roomName,
            items: [
                PopoverMenuItem(
                    title: primaryActionTitle, systemImage: "checkmark.circle", shortcut: "↵"
                ) {
                    activate(at: selection)
                },
                PopoverMenuItem(
                    title: L10n.string(WindowKey.roomPickerSave, language: coordinator.language),
                    systemImage: Room.sfSymbol, shortcut: "⌘↵"
                ) {
                    coordinator.savePicked()
                }
            ])
    }

    /// 屏幕主体：无结果时显示提示，否则渲染选择器列表，并在会话变化时刷新预览。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        let selectedID = rows.indices.contains(selection) ? rows[selection].id : nil
        return AnyView(
            Group {
                if rows.isEmpty {
                    EmptyResults(text: emptyText)
                } else {
                    RoomPickerList(
                        rows: rows, picked: session.picked, selectedID: selectedID,
                        scroll: scroll, onActivate: { coordinator.togglePick($0.pick) })
                }
            }
            .onChange(of: session.revision, initial: true) { coordinator.previewPicked() })
    }

    /// 空列表时的提示文案：区分桌面尚未读取、无查询与无结果三种情况。
    private var emptyText: String {
        let language = coordinator.language
        guard session.isLoaded else {
            return L10n.string(WindowKey.roomPickerReading, language: language)
        }
        return vm.query.isEmpty
            ? L10n.string(WindowKey.roomPickerEmptyNoWindows, language: language)
            : L10n.string(WindowKey.roomPickerEmptyNoMatch, language: language)
    }
}
