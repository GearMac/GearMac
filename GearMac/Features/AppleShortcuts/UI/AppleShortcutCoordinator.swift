// 文件职责：维护 Apple Shortcuts 流程，把发现的快捷指令汇入启动器切片，并提供唯一的运行入口。
// 分层：Coordinator；@MainActor 串行化状态变更，由 Settings/UI 调用以编排副作用。
import AppKit

/// 掌控 Apple Shortcuts 流程：把发现的快捷指令汇入启动器切片，并提供唯一的运行入口。
@MainActor
@Observable
final class AppleShortcutCoordinator {
    /// 每一行都绘制 Shortcuts app 的图标，因此缓存一份 bitmap 即可服务整个列表。
    static let applicationURL =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
        ?? URL(fileURLWithPath: "/System/Applications/Shortcuts.app")

    /// 以行形式保存发现的快捷指令库，仅在列表本身变化时重建。
    private(set) var entries: [AppEntry] = []

    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// 首次读取成功前为 nil，因此启动后的第一次读取一定会执行清理。
    @ObservationIgnored private var shortcuts: [AppleShortcut]?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        settings: AppSettings, appIndex: AppIndex, hotKeys: HotKeyManager,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        aliases: AliasStore, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 返回指定快捷指令当前已知的名称；库尚未加载时返回 nil。
    func name(of id: UUID) -> String? {
        shortcuts?.first { $0.id == id }?.name
    }

    // MARK: - Feature presence

    /// 关闭功能会遗忘快捷指令库但不清理任何引用：只有成功读取才能判定哪些已消失。
    func applyPresence() {
        guard settings.appleShortcutsEnabled else {
            shortcuts = nil
            entries = []
            appIndex.setAppleShortcuts([])
            return
        }
        refresh()
    }

    /// 每次打开启动器都重新读取；工具响应只需数毫秒，因此重叠的刷新直接丢弃。
    func refresh() {
        guard settings.appleShortcutsEnabled, refreshTask == nil else { return }
        refreshTask = Task {
            let found = try? await AppleShortcutRunner.list()
            refreshTask = nil
            // 读取失败时保留上一次成功的库，连同其所有别名与绑定。
            guard let found, settings.appleShortcutsEnabled, found != shortcuts else { return }
            shortcuts = found
            entries = found.map { AppEntry($0, applicationURL: Self.applicationURL) }
            appIndex.setAppleShortcuts(entries)
            removeReferences(toShortcutsMissingFrom: found)
        }
    }

    /// 清理已删除快捷指令所占用的引用，包括在 GearMac 未运行期间被删除的那些。
    private func removeReferences(toShortcutsMissingFrom live: [AppleShortcut]) {
        let keys =
            Array(aliases.aliases.keys) + favorites.keys + visibility.hiddenItemKeys
            + ranking.visits.keys
        let bound = Set(hotKeys.boundAppleShortcutIDs)
        let stale = AppleShortcut.staleIDs(referencedBy: keys, bound: bound, live: live)
        guard !stale.isEmpty else { return }
        for id in stale.intersection(bound) {
            let action = HotKeyAction.appleShortcut(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        let entryIDs = Set(stale.map(AppleShortcut.entryID(for:)))
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    // MARK: - Running

    /// 启动器行与全局快捷键共用的唯一入口，确保功能开关不会被绕过。
    func run(id: UUID) {
        guard settings.appleShortcutsEnabled else { return }
        // 先归还焦点：快捷指令通常作用于用户此前的窗口。
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette() }
        let name = name(of: id) ?? settings.text(AppleShortcutsKey.defaultName)
        Task {
            do throws(AppleShortcutRunner.Failure) {
                try await AppleShortcutRunner.run(id: id)
            } catch {
                await core.showNotice(
                    title: String(
                        format: settings.text(AppleShortcutsKey.errorRun), name),
                    message: error.localizedDescription,
                    symbol: AppleShortcut.sfSymbol, tone: .danger)
            }
        }
    }

    /// 打开系统 Shortcuts app。
    func openShortcutsApp() {
        AppLauncher.launch(Self.applicationURL)
    }
}
