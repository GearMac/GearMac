// 文件职责：把 settings.json 中描述的快捷键文本，经 `HotKeyManager` 及其冲突规则应用到实际绑定。
// 分层：Service；apply 与 commit 分两步，避免迁移中的组合键与旧绑定相互冲突。
import Foundation

/// 按 settings.json 的写法表示的快捷键，经 `HotKeyManager` 及其冲突规则应用。
@MainActor
final class HotKeySettingsFile {
    /// settings.json 中某条期望的快捷键配置。
    struct Wanted {
        let action: HotKeyAction
        let text: String?
        let label: String
    }

    /// 一次待提交的绑定变更，保留原值以便冲突时回滚。
    private struct Change {
        let action: HotKeyAction
        let binding: HotKeyBinding
        let previous: HotKeyBinding?
        let label: String
        let text: String
        let key: SettingsFileKey
    }

    let hotKeys: HotKeyManager
    private var pending: [Change] = []

    /// 使用给定的 HotKeyManager 完成初始化。
    init(hotKeys: HotKeyManager) {
        self.hotKeys = hotKeys
    }

    /// 每次读取时重新构建，因为键盘布局与 Hyper 和弦都可能在运行时变化。
    var spelling: HotKeySpelling {
        HotKeySpelling(
            characters: ASCIIKeyboardLayout.baseCharacters(for: 0..<128),
            hyperModifiers: KeyShortcut.displayedHyperChord().map(KeyShortcut.carbonModifiers(from:)))
    }

    /// 返回某动作对应的 settings.json 文本，未绑定则为 nil。
    func text(for action: HotKeyAction, _ spelling: HotKeySpelling) -> String? {
        hotKeys.binding(for: action).map(spelling.text(for:))
    }

    /// 构造某个 settings 键对应的读写绑定。
    func binding(for key: SettingsFileKey, action: HotKeyAction, name: String) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [self] in text(for: action, spelling).settingsJSON },
            write: { [self] json in
                guard let text = String?(settingsJSON: json) else { return [.invalidValue(key)] }
                return apply([Wanted(action: action, text: text, label: name)], key: key)
            })
    }

    /// 现在先清除有变化的绑定，把设置交给 `commit`，避免迁移中的组合键发生碰撞。
    func apply(_ wanted: [Wanted], key: SettingsFileKey) -> [SettingsFileIssue] {
        let spelling = self.spelling
        var issues: [SettingsFileIssue] = []
        for item in wanted {
            let current = hotKeys.binding(for: item.action)
            guard let text = item.text else {
                if current != nil { hotKeys.setBinding(nil, for: item.action) }
                continue
            }
            guard let binding = spelling.binding(from: text) else {
                issues.append(
                    .invalidEntry(key, "\(item.label): “\(text)” isn't a shortcut GearMac can bind"))
                continue
            }
            guard binding != current else { continue }
            if current != nil { hotKeys.setBinding(nil, for: item.action) }
            pending.append(
                Change(
                    action: item.action, binding: binding, previous: current, label: item.label,
                    text: text, key: key))
        }
        return issues
    }

    /// 执行 `apply` 排队的变更；若某组合键已被其他动作占用则上报问题，并恢复原绑定。
    func commit() -> [SettingsFileIssue] {
        let changes = pending
        pending.removeAll()
        var issues: [SettingsFileIssue] = []
        for change in changes {
            guard let owner = hotKeys.conflictOwner(of: change.binding, excluding: change.action) else {
                hotKeys.setBinding(change.binding, for: change.action)
                continue
            }
            issues.append(
                .invalidEntry(change.key, "\(change.label): “\(change.text)” already runs \(owner)"))
            if let previous = change.previous,
                hotKeys.conflictOwner(of: previous, excluding: change.action) == nil
            {
                hotKeys.setBinding(previous, for: change.action)
            }
        }
        return issues
    }
}
