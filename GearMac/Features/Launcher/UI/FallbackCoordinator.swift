// 文件职责：管理启动器的兜底（fallback）区块：为某次查询提供哪些兜底，以及运行兜底时分派到何处。
// 分层：Coordinator；持有兜底存储与设置，具体的运行目标通过 AppCore 转发给各功能 Coordinator。
import Foundation

/// 负责启动器的兜底区块：为某次查询提供哪些兜底，以及运行兜底时的去向。
@MainActor
final class FallbackCoordinator {
    private let store: FallbackStore
    private let quicklinks: QuicklinkStore
    private let settings: AppSettings
    private let visibility: VisibilityStore
    /// 兜底把查询交给的五个目标；这里没有任何属于本类型自身的状态。
    private unowned let core: AppCore

    /// 注入兜底存储、快捷链接、设置与可见性服务，并保留对 AppCore 的弱引用。
    init(
        store: FallbackStore, quicklinks: QuicklinkStore, settings: AppSettings,
        visibility: VisibilityStore, core: AppCore
    ) {
        self.store = store
        self.quicklinks = quicklinks
        self.settings = settings
        self.visibility = visibility
        self.core = core
    }

    /// 这台 Mac 当前可提供的全部兜底，按用户排序展示——设置页列出的正是这一份。
    var available: [Fallback] { store.ordered(candidates) }

    /// 启动器中的兜底行。空查询不构成任何输入，因此不会产生该区块。
    func entries(for query: String) -> [(fallback: Fallback, entry: AppEntry)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return available.filter(store.isEnabled).compactMap { fallback in
            entry(for: fallback).map { (fallback, $0) }
        }
    }

    /// 当快捷链接自排序保存后被删除时返回 nil。
    func entry(for fallback: Fallback) -> AppEntry? {
        switch fallback {
        case .builtin(let builtin): return CommandCatalog.makeEntry(builtin.command)
        case .quicklink(let id): return quicklinks.quicklink(id: id).map(AppEntry.init)
        }
    }

    /// 唯一的汇聚点；每个目标都把该查询当作它本就需要的输入。
    func run(_ fallback: Fallback, query: String) {
        switch fallback {
        case .builtin(.quickAI): core.quickAICoordinator.ask(query)
        case .builtin(.searchFiles): core.fileSearchCoordinator.show(query: query)
        case .builtin(.runShellCommand): core.customCommandCoordinator.runShellCommand(query)
        case .builtin(.define): core.dictionaryCoordinator.show(term: query)
        case .quicklink(let id): core.quicklinkCoordinator.openQuicklink(id: id, filling: query)
        }
    }

    /// 区块齿轮与行自身的动作；面板会随设置页打开而关闭。
    func showSettings() {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        core.settingsCoordinator.showSettings(tab: .fallbacks)
    }

    /// 功能已关闭的兜底在任何地方都不提供，设置页也不例外。
    private var candidates: [Fallback] {
        var result = Fallback.Builtin.allCases.filter(isAvailable).map(Fallback.builtin)
        guard settings.quicklinksEnabled else { return result }
        result += quicklinks.quicklinks
            .filter { $0.isEnabled && QuicklinkDestination.containsPlaceholder($0.link) }
            .sorted(by: Quicklink.precedes)
            .map { .quicklink($0.id) }
        return result
    }

    /// 判断某个内置兜底是否可用：取决于其对应功能的开关状态。
    private func isAvailable(_ builtin: Fallback.Builtin) -> Bool {
        switch builtin {
        case .quickAI: return settings.aiEnabled
        case .searchFiles: return settings.fileSearchEnabled
        // Its own capability: this shell is not the custom-command library's switch to hold.
        case .runShellCommand: return true
        // Settings › Commands is Define's only switch, so hiding the command there hides this too.
        case .define: return visibility.isVisible(CommandCatalog.makeEntry(.define))
        }
    }
}
