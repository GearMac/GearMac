// 文件职责：把按键（`KeyPress` / `KeyEquivalent`）解析为带列表控件可理解的动作，如展开、移动、提交、追加字符。
// 分层：UI；纯解析逻辑，无副作用，不直接触碰视图与外部状态。
import SwiftUI

/// 按键对带列表控件的含义；集中在一处，避免规则互相遮蔽。
enum ExtensionListKey: Equatable {
    case openList
    case moveUp
    case moveDown
    case commit
    case dismiss
    case append(String)
    case deleteBackward
    /// 未展开的单项选择控件上的 ←/→，无需展开即可逐项切换取值。
    case stepValue(Int)
    case ignored

    init(press: KeyPress, listOpen: Bool) {
        self = ExtensionListKey.resolve(
            key: press.key, characters: press.characters, modifiers: press.modifiers,
            listOpen: listOpen)
    }

    /// 单独抽出以便测试驱动器调用：`KeyPress` 无法在 SwiftUI 之外构造。
    static func resolve(
        key: KeyEquivalent, characters: String, modifiers: EventModifiers, listOpen: Bool
    ) -> ExtensionListKey {
        // 组合键属于绑定它的那一方（⌘K、某操作的快捷键），永远不属于此列表。
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }

        switch key {
        case .upArrow: return listOpen ? .moveUp : .ignored
        case .downArrow: return listOpen ? .moveDown : .openList
        case .return, KeyEquivalent("\u{3}"): return listOpen ? .commit : .openList
        case .escape: return listOpen ? .dismiss : .ignored
        case .leftArrow: return listOpen ? .ignored : .stepValue(-1)
        case .rightArrow: return listOpen ? .ignored : .stepValue(1)
        case .space: return listOpen ? .append(" ") : .openList
        case .tab: return .ignored
        default: break
        }

        // 实测：⌫ 以 U+007F 到达，而非 SwiftUI 的 `.delete` 所命名的 U+0008。
        if isDeletion(key: key, characters: characters) {
            return listOpen ? .deleteBackward : .ignored
        }

        guard listOpen, !characters.isEmpty, characters.allSatisfy(isTypable) else {
            return .ignored
        }
        return .append(characters)
    }

    /// 只接受搜索框会显示的字符：控制键自身的字符不得变成文本。
    private static func isTypable(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return true }
        return !CharacterSet.controlCharacters.contains(scalar)
            && !CharacterSet.illegalCharacters.contains(scalar)
    }

    /// 每个删除键的两种写法：具名等价项，以及它们携带的 Unicode 标量。
    private static func isDeletion(key: KeyEquivalent, characters: String) -> Bool {
        if key == .delete || key == .deleteForward { return true }
        let deletions: Set<Unicode.Scalar> = ["\u{8}", "\u{7F}"]
        if deletions.contains(key.character.unicodeScalars.first ?? " ") { return true }
        guard characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first
        else { return false }
        return deletions.contains(scalar)
    }
}
