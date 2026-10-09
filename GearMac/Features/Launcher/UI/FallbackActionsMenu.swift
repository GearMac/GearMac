// 文件职责：构建启动器兜底行（fallback row）的操作菜单内容。
// 分层：UI；仅组装菜单，具体运行与打开设置交由 FallbackCoordinator。
import Foundation

/// 单个兜底行的操作菜单。它回应的是查询而非指向某个具体对象，因此这里没有固定、排序或「在 Finder 中显示」等项：两个条目分别是运行它和修改列表。
@MainActor
enum FallbackActionsMenu {
    /// 构建兜底行菜单：运行该兜底，或打开兜底设置页。
    static func content(
        fallback: Fallback, entry: AppEntry, query: String, core: AppCore
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: entry.name,
            items: [
                PopoverMenuItem(
                    title: fallback.openVerb(core.settings.language),
                    systemImage: "list.bullet.rectangle", shortcut: "↵"
                ) { core.fallbackCoordinator.run(fallback, query: query) },
                PopoverMenuItem(
                    title: core.settings.text(LauncherKey.configureFallbacks),
                    systemImage: "slider.horizontal.3", startsSection: true
                ) {
                    core.fallbackCoordinator.showSettings()
                }
            ])
    }
}
