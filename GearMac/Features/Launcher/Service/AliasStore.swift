// 文件职责：维护用户为每个启动器条目设置的别名（alias）表，并持久化到 UserDefaults。
// 分层：Service；@MainActor 隔离，别名变更时递增 revision，使 AppIndex 的排名缓存失效。
import Foundation

/// 用户为每个条目设置的别名，键与收藏、排名一致，均使用 `preferenceKey`。
@MainActor
@Observable
final class AliasStore {
    private let defaults: UserDefaults
    private let defaultsKey = "launcherAliases"

    private(set) var aliases: [String: String]
    /// AppIndex 把它纳入结果缓存键，别名一变更就会使已有排名失效。
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// 读取该条目已保存的别名，未设置时返回 nil。
    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    /// 原样保存用户输入（此处做 trim 会吃掉词与词之间的空格），但纯空白仍视为未设置。
    func setAlias(_ alias: String, for entryKey: String) {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : alias
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    /// 移除指定键对应的别名，用于清理已不存在的条目。
    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    /// 一次性替换整张别名表（用于导入设置备份时）。
    func replace(_ new: [String: String]) {
        // 导入遵循与手动输入相同的规则：纯空白视为未设置，否则会变成永远清不掉的值。
        aliases = new.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }
}
