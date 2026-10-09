// 文件职责：搜索框为空时选择展示的建议条目（新装应用、常用条目与内置命令的填充逻辑）。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 搜索框为空时提供的、用户常用入口。
enum LauncherSuggestions {
    /// 建议区块最多展示的条目数。
    static let limit = 5
    /// 刚安装的应用或扩展在被首次打开前就会被推荐。
    static let recentInstallLimit = 2
    /// 刚安装的判定时间窗口。
    static let recentInstallWindow: TimeInterval = 5 * 60

    /// 建议选择所需的单个条目属性。
    struct Traits: Sendable {
        var signals: LauncherOrder.Signals
        var installedAt: Date?
        /// 已绑定快捷键的条目已有比该区块更快的进入方式。
        var hasHotKey: Bool
        /// 对尚无使用历史的用户值得推荐的内置命令；数值越高越靠前。
        var priority: Int?
    }

    /// `items` 只包含可被推荐的项：不含收藏、会议或 GearMac 自身。
    static func select<Item>(from items: [Item], now: Date, traits: (Item) -> Traits) -> [Item] {
        let all = items.map(traits)
        let signals: (Int) -> LauncherOrder.Signals = { all[$0].signals }
        let fresh = LauncherOrder.byUsage(
            all.indices.filter { isFreshInstall(all[$0], now: now) }, signals: signals
        ).prefix(recentInstallLimit)
        var taken = Set(fresh)
        let used = LauncherOrder.byUsage(
            all.indices.filter {
                !taken.contains($0) && all[$0].signals.usage.frecency > 1 && !all[$0].hasHotKey
            },
            signals: signals)
        var picked = Array(fresh) + used
        if picked.count < limit {
            taken.formUnion(used)
            let fill = all.indices
                .filter { !taken.contains($0) && all[$0].signals.alias == nil && !all[$0].hasHotKey }
                .compactMap { index in all[index].priority.map { (index: index, priority: $0) } }
                .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.index < $1.index }
            picked += fill.map(\.index)
        }
        return picked.prefix(limit).map { items[$0] }
    }

    /// 刚安装且尚未使用过的条目。
    private static func isFreshInstall(_ traits: Traits, now: Date) -> Bool {
        guard traits.signals.usage.frecency <= 1, let installed = traits.installedAt else { return false }
        return now.timeIntervalSince(installed) < recentInstallWindow
    }
}
