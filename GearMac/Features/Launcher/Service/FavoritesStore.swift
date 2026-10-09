// 文件职责：维护收藏应用的顺序键列表（以 preferenceKey 为键），并在搜索为空时将收藏置顶。
// 分层：Service；@MainActor 隔离，变更时递增 revision 使 AppIndex 的结果缓存失效。
import Foundation

/// 收藏应用的有序键列表，在搜索为空时固定在顶部显示。
@MainActor
@Observable
final class FavoritesStore {
    private let defaults = UserDefaults.standard
    private let key = "favoriteApps"

    private(set) var keys: [String]
    /// AppIndex 把它纳入结果缓存键，置顶内容变化时使列表失效。
    private(set) var revision = 0

    init() {
        keys = defaults.stringArray(forKey: key) ?? []
    }

    /// 该应用用于收藏与排名的偏好键。
    func key(for app: AppEntry) -> String { app.preferenceKey }

    /// 该应用是否已被收藏。
    func isFavorite(_ app: AppEntry) -> Bool { keys.contains(key(for: app)) }

    /// 一次性替换整个收藏列表（用于导入设置备份时）。
    func replace(keys newKeys: [String]) {
        keys = newKeys
        commit()
    }

    /// 移除给定键对应的收藏项。
    func remove(keys removedKeys: Set<String>) {
        guard !removedKeys.isEmpty else { return }
        let updated = keys.filter { !removedKeys.contains($0) }
        guard updated != keys else { return }
        keys = updated
        commit()
    }

    /// 在收藏与取消收藏之间切换该应用。
    func toggle(_ app: AppEntry) {
        let k = key(for: app)
        if let index = keys.firstIndex(of: k) {
            keys.remove(at: index)
        } else {
            keys.append(k)
        }
        commit()
    }

    /// 传入的两个键来自可见顺序，因此被隐藏的条目仍保留其位置。
    func exchange(_ first: String, with second: String) {
        guard let a = keys.firstIndex(of: first), let b = keys.firstIndex(of: second), a != b else {
            return
        }
        keys.swapAt(a, b)
        commit()
    }

    /// 递增 revision 并把收藏列表写回 UserDefaults。
    private func commit() {
        revision &+= 1
        defaults.set(keys, forKey: key)
    }

    /// 把 `apps` 拆成收藏（按存储顺序）与其余项（保持原有顺序）。
    func ordered(_ apps: [AppEntry]) -> (favorites: [AppEntry], rest: [AppEntry]) {
        guard !keys.isEmpty else { return ([], apps) }
        let byKey = Dictionary(
            apps.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let favorites = keys.compactMap { byKey[$0] }
        let favoriteKeys = Set(keys)
        let rest = apps.filter { !favoriteKeys.contains(key(for: $0)) }
        return (favorites, rest)
    }
}
