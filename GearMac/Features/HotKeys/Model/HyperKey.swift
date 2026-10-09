// 文件职责：定义可映射为 Hyper 组合键的物理按键（Caps Lock、右侧修饰键）及其键码、事件来源与快捷按下行为。
// 分层：Model；纯枚举，依赖 Carbon 与 CoreGraphics 常量。
import Carbon.HIToolbox
import CoreGraphics

/// 被重新映射为 Hyper 组合键的物理按键。参见 docs/features/hotkeys.md#the-hyper-key。
enum HyperKeyPhysicalKey: String, CaseIterable, Identifiable, Sendable {
    case none
    case capsLock
    case rightControl, rightShift, rightOption, rightCommand

    var id: String { rawValue }

    /// Hyper 快捷键折叠显示的单一符号。
    static let hyperGlyph = "✦"

    /// 选择器中展示的名称。
    var title: String {
        switch self {
        case .none: return "None"
        case .capsLock: return "Caps Lock (⇪)"
        case .rightControl: return "Right Control (⌃)"
        case .rightShift: return "Right Shift (⇧)"
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        }
    }

    /// 该物理按键的虚拟键码，仅 `.none` 为 `nil`。
    var keyCode: Int? {
        switch self {
        case .none: return nil
        case .capsLock: return kVK_CapsLock
        case .rightControl: return kVK_RightControl
        case .rightShift: return kVK_RightShift
        case .rightOption: return kVK_RightOption
        case .rightCommand: return kVK_RightCommand
        }
    }

    /// 轻点监听所用的键码；Caps Lock 作为 Hyper 时会被 HID 重映射为 F18。
    var tapKeyCode: Int? {
        self == .capsLock ? kVK_F18 : keyCode
    }

    /// 按下事件是以 keyDown/keyUp（Caps Lock 经 F18）到达，还是以 `flagsChanged` 到达。
    var tapUsesKeyEvents: Bool { self == .capsLock }

    /// 未被重映射时会自行生效的按键——这些才有「快捷按下」那一行设置。
    var hasOriginalFunction: Bool { self == .capsLock }

    /// 该键贡献的通用标志位，使轻点逻辑能在不属于集合时将其移除。
    var ownFlag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .capsLock: return .maskAlphaShift
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        }
    }

    /// 「快捷按下」时用于触发该键原始功能的标签。
    var quickPressOriginalTitle: String? {
        self == .capsLock ? "Trigger Caps Lock (⇪)" : nil
    }
}

/// 单独轻点 Hyper 键时的行为（仅对有原始功能的键提供）。
enum HyperKeyQuickPress: String, CaseIterable, Sendable {
    case none
    case originalKey
    case escape
}
