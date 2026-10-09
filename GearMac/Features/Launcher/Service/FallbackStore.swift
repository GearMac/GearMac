// 文件职责：维护启动器兜底项（Fallback）的启用状态与显示顺序，并持久化到 UserDefaults。
// 分层：Service；@MainActor 隔离，顺序与启用状态均以 UserDefaults 为唯一数据源。
import Foundation

/// 读取器的兜底项列表：哪些被提供，以及以什么顺序提供。
@MainActor
@Observable
final class FallbackStore {
    private let defaults = UserDefaults.standard
    private let orderKey = "fallbackOrder"
    private let disabledKey = "disabledFallbacks"

    private(set) var orderedIDs: [String]
    private(set) var disabledIDs: Set<String>

    init() {
        orderedIDs = defaults.stringArray(forKey: orderKey) ?? []
        disabledIDs = Set(defaults.stringArray(forKey: disabledKey) ?? [])
    }

    /// 按已保存的顺序对给定的兜底项列表排序。
    func ordered(_ available: [Fallback]) -> [Fallback] {
        Fallback.ordered(available, by: orderedIDs)
    }

    /// 该兜底项是否已启用。
    func isEnabled(_ fallback: Fallback) -> Bool { !disabledIDs.contains(fallback.id) }

    /// 启用或禁用某个兜底项并立即持久化。
    func setEnabled(_ enabled: Bool, for fallback: Fallback) {
        if enabled {
            disabledIDs.remove(fallback.id)
        } else {
            disabledIDs.insert(fallback.id)
        }
        defaults.set(Array(disabledIDs), forKey: disabledKey)
    }

    /// 交换两个相邻项并保存整个可见顺序，使后续行不会发生漂移。
    func exchange(_ fallback: Fallback, with other: Fallback, in order: [Fallback]) {
        guard let from = order.firstIndex(of: fallback), let to = order.firstIndex(of: other) else {
            return
        }
        var updated = order
        updated.swapAt(from, to)
        orderedIDs = updated.map(\.id)
        defaults.set(orderedIDs, forKey: orderKey)
    }
}
