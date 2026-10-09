// 文件职责：管理自定义窗口尺寸的新增、编辑、删除，并联动清理热键、收藏、可见性、别名与排序引用。
// 分层：Coordinator；@MainActor @Observable，仅对 `@Environment` 可观察，对话框经注入的 core 展示。
import Foundation

/// 持有自定义尺寸的存在性、编辑与清理；只对 `@Environment` 可观察。
@MainActor
@Observable
final class CustomWindowSizeCoordinator {
    private let store: CustomWindowSizeStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// 仅用于对话框展示；该类不持有它的任何状态。
    private unowned let core: AppCore

    init(
        store: CustomWindowSizeStore, settings: AppSettings, appIndex: AppIndex,
        hotKeys: HotKeyManager, favorites: FavoritesStore, visibility: VisibilityStore,
        ranking: LauncherRankingStore, aliases: AliasStore, core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.core = core
    }

    /// 自定义尺寸属于窗口命令，因此跟随命令自身的启动器开关。
    func applyCustomWindowSizesPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setCustomWindowSizes(visible ? store.sizes : [])
    }

    /// 新增或更新；编辑期间被删除的尺寸会被重新添加，而不是消失。
    func saveCustomWindowSize(_ draft: CustomWindowSize) throws(CustomWindowSizeValidationError) {
        if store.size(id: draft.id) == nil {
            try store.add(draft)
        } else {
            try store.update(draft)
        }
    }

    /// 确认后删除该尺寸，并清理其快捷键与启动器引用。
    func deleteCustomWindowSize(id: UUID) async {
        guard let size = store.size(id: id),
            await core.confirm(
                title: String(
                    format: settings.text(WindowKey.deleteTitle), size.name),
                message: settings.text(WindowKey.sizeDeleteMessage),
                symbol: CustomWindowSize.sfSymbol, confirmTitle: settings.text(WindowKey.actionDelete)),
            store.remove(id: id) != nil
        else { return }
        // 仅在记录确实被移除后才清理关联，保证保留的记录不会丢失快捷键。
        removeReferences(ids: [size.id], entryIDs: [size.entryID])
    }

    /// 用导入的尺寸整体替换现有集合，并清理被移除项的引用；返回写入条数。
    @discardableResult
    func replaceCustomWindowSizes(_ incoming: [CustomWindowSize]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.sizes.map { ($0.id, $0.entryID) })
        let count = store.replace(with: incoming)
        let removed = Set(previous.keys).subtracting(store.sizes.map(\.id))
        removeReferences(ids: removed, entryIDs: Set(removed.compactMap { previous[$0] }))
        return count
    }

    /// 清理被移除尺寸的快捷键绑定、收藏、可见性、别名与排序记录。
    private func removeReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customWindowSize(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }
}
