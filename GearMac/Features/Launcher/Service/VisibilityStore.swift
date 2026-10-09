// 文件职责：维护启动器条目与条目类别的隐藏/禁用状态，并持久化到 UserDefaults。
// 分层：Service；@MainActor 隔离，变更时递增 revision 使 AppIndex 的结果缓存失效。
import Foundation

/// 类别关闭后该类条目全部不可用，因此它既约束列表也约束快捷键。
@MainActor
@Observable
final class VisibilityStore {
    private let defaults: UserDefaults
    private let itemsKey = "hiddenLauncherItems"
    private let kindsKey = "hiddenLauncherKinds"

    private(set) var hiddenItemKeys: Set<String>
    private(set) var disabledKinds: Set<String>
    /// AppIndex 把它纳入结果缓存键，可见集合变化时使列表失效。
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenItemKeys = Set(defaults.stringArray(forKey: itemsKey) ?? [])
        disabledKinds = Set(defaults.stringArray(forKey: kindsKey) ?? [])
    }

    /// 一次性替换两个排除集合（用于导入设置备份时）。
    func replace(hiddenItems: [String], disabledKinds newKinds: [String]) {
        hiddenItemKeys = Set(hiddenItems)
        disabledKinds = Set(newKinds)
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
        defaults.set(Array(disabledKinds), forKey: kindsKey)
    }

    /// 该条目用于可见性记录的偏好键。
    func key(for entry: AppEntry) -> String { entry.preferenceKey }

    /// 条目是否出现在启动器中：其类别与条目自身都必须处于开启状态。
    func isVisible(_ entry: AppEntry) -> Bool {
        isCategoryEnabled(entry) && isItemVisible(entry)
    }

    /// 由某功能面板负责的条目只受该功能开关控制，不受类别开关约束。
    private func isCategoryEnabled(_ entry: AppEntry) -> Bool {
        entry.settingsOwner != nil || isKindEnabled(entry.kind)
    }

    func isItemVisible(_ entry: AppEntry) -> Bool { isItemVisible(key: key(for: entry)) }

    func isItemVisible(key: String) -> Bool { !hiddenItemKeys.contains(key) }

    func setItemVisible(_ visible: Bool, for entry: AppEntry) {
        setItemVisible(visible, forKey: key(for: entry))
    }

    /// 设置条目是否可见，变化时持久化并递增 revision。
    func setItemVisible(_ visible: Bool, forKey key: String) {
        guard isItemVisible(key: key) != visible else { return }
        if visible { hiddenItemKeys.remove(key) } else { hiddenItemKeys.insert(key) }
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    /// 移除给定键的隐藏记录，用于清理已不存在的条目。
    func removeItemKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previous = hiddenItemKeys
        hiddenItemKeys.subtract(keys)
        guard hiddenItemKeys != previous else { return }
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    /// 该类别是否未被禁用。
    func isKindEnabled(_ kind: AppEntry.Kind) -> Bool {
        !disabledKinds.contains(kind.rawValue)
    }

    /// 启用或禁用一个类别并持久化。
    func setKindEnabled(_ enabled: Bool, for kind: AppEntry.Kind) {
        guard isKindEnabled(kind) != enabled else { return }
        if enabled { disabledKinds.remove(kind.rawValue) } else { disabledKinds.insert(kind.rawValue) }
        revision &+= 1
        defaults.set(Array(disabledKinds), forKey: kindsKey)
    }

    /// 自带开关的功能不由此存储控制。
    func allowsHotKey(_ action: HotKeyAction) -> Bool {
        switch action {
        case .app: isKindEnabled(.application)
        case .settingsPane: isKindEnabled(.systemSettings)
        case .systemAction: isKindEnabled(.systemAction)
        case .command(let id): id.owner == nil ? isKindEnabled(.command) : true
        case .togglePalette, .dictation, .quickAction, .customCommand, .windowCommand, .customWindowSize,
            .windowLayout, .windowRoom, .quicklink, .appleShortcut, .snippet, .extensionCommand:
            true
        }
    }
}
