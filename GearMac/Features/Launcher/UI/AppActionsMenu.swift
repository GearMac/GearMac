// 文件职责：为启动器中的条目（应用、命令、扩展、日程等）构建右键菜单与「Actions」胶囊共用的弹出菜单内容。
// 分层：UI；仅组装 PopoverMenuContent，具体动作交由 AppCore 的 Coordinator 执行。
import SwiftUI

/// 启动器应用条目的操作菜单：由右键或「Actions」胶囊触发。
@MainActor
enum AppActionsMenu {
    /// 由持有可见顺序的界面解析；每一行都执行其快捷键对应的动作。
    @MainActor
    struct FavoriteActions {
        let isFavorite: Bool
        let canMoveUp: Bool
        let canMoveDown: Bool
        let toggle: () -> Void
        let move: (Int) -> Void
    }

    /// 组装完整菜单内容：前置动作，加上收藏与排序、隐藏、运行态（重启/退出/强制退出）、卸载、扩展等条目。
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, running: Bool,
        favorites: FavoriteActions, onResetRanking: @escaping () -> Void,
        onHideFromSearch: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items = leadingItems(app: app, searchQuery: searchQuery, core: core)
        func text(_ key: LauncherKey) -> String { core.settings.text(key) }
        // 由查询驱动的行只随其查询存在，因此没有偏好设置能将其持久保留。
        let isPersistent = !CommandCatalog.isQueryDriven(app)
        if isPersistent {
            items.append(
                PopoverMenuItem(
                    title: text(
                        favorites.isFavorite ? .favoriteRemove : .favoriteAdd),
                    systemImage: favorites.isFavorite ? "star.slash" : "star", startsSection: true,
                    shortcut: "⇧⌘F", action: favorites.toggle))
        }
        if favorites.canMoveUp {
            items.append(
                PopoverMenuItem(
                    title: text(.favoriteMoveUp), systemImage: "arrow.up", shortcut: "⌥⌘↑"
                ) {
                    favorites.move(-1)
                })
        }
        if favorites.canMoveDown {
            items.append(
                PopoverMenuItem(
                    title: text(.favoriteMoveDown), systemImage: "arrow.down", shortcut: "⌥⌘↓"
                ) {
                    favorites.move(1)
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: text(.resetRanking), systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if isPersistent, app.canHideFromSearch {
            items.append(
                PopoverMenuItem(
                    title: text(.hideFromSearch), systemImage: "eye.slash", shortcut: "⇧⌘H",
                    action: onHideFromSearch))
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: text(.restartApplication), systemImage: "arrow.clockwise",
                    startsSection: true,
                    shortcut: "⌘R"
                ) {
                    core.launcherCoordinator.restart(app)
                })
            items.append(
                PopoverMenuItem(
                    title: text(.quitApplication), systemImage: "power", shortcut: "⌃⇧Q"
                ) {
                    core.launcherCoordinator.quit(app)
                })
            items.append(
                PopoverMenuItem(
                    title: text(.forceQuitApplication), systemImage: "xmark.circle",
                    shortcut: "⌃⌥⇧Q"
                ) {
                    core.launcherCoordinator.quit(app, force: true)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: text(.uninstallApplication), systemImage: "trash", startsSection: true,
                    isDestructive: true
                ) {
                    core.uninstallCoordinator.beginUninstall(app)
                })
        }
        if app.kind == .extensionCommand {
            if core.extensions.isBackgroundSchedulable(for: app) {
                let enabled = core.extensions.isBackgroundEnabled(for: app)
                items.append(
                    PopoverMenuItem(
                        title: text(
                            enabled ? .backgroundRefreshDisable : .backgroundRefreshEnable),
                        systemImage: enabled ? "pause.circle" : "play.circle", startsSection: true
                    ) {
                        core.extensions.toggleBackgroundRefresh(for: app)
                    })
                if enabled {
                    items.append(
                        PopoverMenuItem(title: text(.refreshNow), systemImage: "arrow.clockwise") {
                            core.extensions.refreshNow(app)
                        })
                }
            }
            items.append(
                PopoverMenuItem(
                    title: text(.configureExtension), systemImage: "slider.horizontal.3",
                    startsSection: true
                ) {
                    core.extensionCoordinator.showExtensionSettings(for: app)
                })
            items.append(
                PopoverMenuItem(
                    title: text(.uninstallExtension), systemImage: "trash", isDestructive: true
                ) {
                    core.extensionCoordinator.confirmUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    /// 构建菜单顶部的前置条目：日程行沿用该日程卡片的动作，其余为打开与「在 Finder 中显示」。
    private static func leadingItems(
        app: AppEntry, searchQuery: String, core: AppCore
    ) -> [PopoverMenuItem] {
        if app.kind == .meeting, let meeting = core.calendarCoordinator.meeting(entryID: app.id) {
            return MeetingActionsMenu.content(meeting: meeting, core: core).items
        }
        let primarySymbol =
            switch app.kind {
            case .application, .command, .extensionCommand: "list.dash.header.rectangle"
            default: "list.bullet.rectangle"
            }
        var items = [
            PopoverMenuItem(
                title: core.settings.text(app.kind.openVerbKey), systemImage: primarySymbol,
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(LauncherKey.showInFinder), systemImage: "folder",
                    shortcut: "⌘↵"
                ) {
                    core.launcherCoordinator.showInFinder(app)
                })
        }
        return items
    }
}
