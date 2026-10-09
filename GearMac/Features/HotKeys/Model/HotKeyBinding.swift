// 文件职责：定义快捷键的绑定形式（组合键、双击修饰键、单击/双击指定修饰键、Globe 键等），以及键帽展示与冲突判定。
// 分层：Model；纯值类型，键帽渲染标注 @MainActor。
import Foundation

/// 动作所绑定的形式。参见 docs/features/hotkeys.md。
enum HotKeyBinding: Hashable, Sendable, Codable {
    case combo(KeyShortcut)
    case doubleTap(DoubleTapModifier)
    case modifier(ModifierKey)
    case doubleModifier(ModifierKey)
    case globe
    case doubleGlobe

    /// 每个键帽对应一个字符串，使所有展示位置都经由同一条路径渲染绑定。
    @MainActor var keycaps: [String] {
        switch self {
        case .combo(let shortcut): shortcut.keycaps
        case .doubleTap(let modifier): modifier.keycaps
        case .modifier(let key): key.keycaps
        case .doubleModifier(let key): key.modifier?.keycaps ?? ["🌐︎", "🌐︎"]
        case .globe: ["🌐︎"]
        case .doubleGlobe: ["🌐︎", "🌐︎"]
        }
    }

    /// 录制器展示时冠在键帽前的修饰键前缀（如 "L" / "R"），无则 nil。
    var recorderPrefix: String? {
        switch self {
        case .modifier(let key): key.side.map { String($0.prefix(1)) }
        default: nil
        }
    }

    /// 录制器展示用的键帽（去掉侧别前缀）。
    @MainActor var recorderKeycaps: [String] {
        recorderPrefix == nil ? keycaps : Array(keycaps.dropFirst())
    }

    /// 该绑定对应的组合键（仅组合键形式有值）。
    var shortcut: KeyShortcut? {
        if case .combo(let shortcut) = self { return shortcut }
        return nil
    }

    /// 该绑定是否需要修饰键轻点监视器（非组合键形式需要）。
    var usesModifierTapMonitor: Bool {
        switch self {
        case .combo: false
        case .doubleTap, .modifier, .doubleModifier, .globe, .doubleGlobe: true
        }
    }

    /// 长按时所使用的修饰键（仅单击修饰键与 Globe 形式有值）。
    var holdKey: ModifierKey? {
        switch self {
        case .modifier(let key): key
        case .globe: .globe
        default: nil
        }
    }

    /// 该绑定涉及的修饰键集合，用于冲突判定。
    private var modifierKeys: Set<ModifierKey> {
        switch self {
        case .modifier(let key), .doubleModifier(let key): [key]
        case .globe, .doubleGlobe: [.globe]
        case .doubleTap(let modifier): Set(ModifierKey.allCases.filter { $0.modifier == modifier })
        case .combo: []
        }
    }

    /// 判断两个绑定是否冲突；`holdsModifier` 表示长按修饰键模式下的比较。
    func conflicts(with other: Self, holdsModifier: Bool = false) -> Bool {
        if self == other { return true }
        guard !modifierKeys.isDisjoint(with: other.modifierKeys) else { return false }
        if holdsModifier { return true }
        switch (self, other) {
        case (.doubleTap, .doubleModifier), (.doubleModifier, .doubleTap): return true
        case (.globe, .modifier), (.modifier, .globe): return true
        case (.doubleGlobe, .doubleModifier), (.doubleModifier, .doubleGlobe): return true
        default: return false
        }
    }
}
