// 文件职责：内置其他窗口管理器的默认快捷键预设（Rectangle/Magnet、Spectacle），并计算应用预设带来的变更。
// 分层：Model；保持纯净，依赖 Carbon.HIToolbox 取物理键码，不 import AppKit/SwiftUI。
import Carbon.HIToolbox
import Foundation

/// 其他窗口管理器的出厂快捷键。见 docs/features/window-management.md。
enum WindowShortcutPreset: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case spectacle

    var id: String { rawValue }

    /// 英文兜底名称；供无语言上下文的调用方（如测试）使用。
    var title: String { localizedTitle(.english) }

    /// 预设名称；品牌名在两种语言下相同。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .rectangle: L10n.string(WindowKey.presetRectangle, language: language)
        case .spectacle: L10n.string(WindowKey.presetSpectacle, language: language)
        }
    }

    /// 每个 app 注册时使用的物理键码，这样非 QWERTY 布局也能匹配。
    var bindings: [WindowCommand.ID: HotKeyBinding] {
        switch self {
        case .rectangle:
            [
                .leftHalf: Self.combo(kVK_LeftArrow, controlKey | optionKey),
                .rightHalf: Self.combo(kVK_RightArrow, controlKey | optionKey),
                .topHalf: Self.combo(kVK_UpArrow, controlKey | optionKey),
                .bottomHalf: Self.combo(kVK_DownArrow, controlKey | optionKey),
                .topLeftQuarter: Self.combo(kVK_ANSI_U, controlKey | optionKey),
                .topRightQuarter: Self.combo(kVK_ANSI_I, controlKey | optionKey),
                .bottomLeftQuarter: Self.combo(kVK_ANSI_J, controlKey | optionKey),
                .bottomRightQuarter: Self.combo(kVK_ANSI_K, controlKey | optionKey),
                .firstThird: Self.combo(kVK_ANSI_D, controlKey | optionKey),
                .centerThird: Self.combo(kVK_ANSI_F, controlKey | optionKey),
                .lastThird: Self.combo(kVK_ANSI_G, controlKey | optionKey),
                .firstTwoThirds: Self.combo(kVK_ANSI_E, controlKey | optionKey),
                .centerTwoThirds: Self.combo(kVK_ANSI_R, controlKey | optionKey),
                .lastTwoThirds: Self.combo(kVK_ANSI_T, controlKey | optionKey),
                .maximize: Self.combo(kVK_Return, controlKey | optionKey),
                .maximizeHeight: Self.combo(kVK_UpArrow, controlKey | optionKey | shiftKey),
                .center: Self.combo(kVK_ANSI_C, controlKey | optionKey),
                .makeLarger: Self.combo(kVK_ANSI_Equal, controlKey | optionKey),
                .makeSmaller: Self.combo(kVK_ANSI_Minus, controlKey | optionKey),
                .restore: Self.combo(kVK_Delete, controlKey | optionKey),
                .nextDisplay: Self.combo(kVK_RightArrow, controlKey | optionKey | cmdKey),
                .previousDisplay: Self.combo(kVK_LeftArrow, controlKey | optionKey | cmdKey)
            ]
        case .spectacle:
            [
                .leftHalf: Self.combo(kVK_LeftArrow, optionKey | cmdKey),
                .rightHalf: Self.combo(kVK_RightArrow, optionKey | cmdKey),
                .topHalf: Self.combo(kVK_UpArrow, optionKey | cmdKey),
                .bottomHalf: Self.combo(kVK_DownArrow, optionKey | cmdKey),
                .topLeftQuarter: Self.combo(kVK_LeftArrow, controlKey | cmdKey),
                .topRightQuarter: Self.combo(kVK_RightArrow, controlKey | cmdKey),
                .bottomLeftQuarter: Self.combo(kVK_LeftArrow, controlKey | shiftKey | cmdKey),
                .bottomRightQuarter: Self.combo(kVK_RightArrow, controlKey | shiftKey | cmdKey),
                .maximize: Self.combo(kVK_ANSI_F, optionKey | cmdKey),
                .center: Self.combo(kVK_ANSI_C, optionKey | cmdKey),
                .makeLarger: Self.combo(kVK_RightArrow, controlKey | optionKey | shiftKey),
                .makeSmaller: Self.combo(kVK_LeftArrow, controlKey | optionKey | shiftKey),
                .restore: Self.combo(kVK_ANSI_Z, optionKey | cmdKey),
                .nextDisplay: Self.combo(kVK_RightArrow, controlKey | optionKey | cmdKey),
                .previousDisplay: Self.combo(kVK_LeftArrow, controlKey | optionKey | cmdKey)
            ]
        }
    }

    /// 预设之外的命令不计入，因为应用预设从不会触碰它们。
    static func matching(_ current: [WindowCommand.ID: HotKeyBinding]) -> WindowShortcutPreset? {
        allCases.first { preset in preset.bindings.allSatisfy { current[$0.key] == $0.value } }
    }

    private static func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
    }
}

/// 应用预设会改变什么，在写入任何内容之前先算出来。
struct WindowShortcutPresetPlan: Equatable, Sendable {
    /// 与命令当前持有的快捷键不同的预设条目。
    let assignments: [WindowCommand.ID: HotKeyBinding]
    /// 预设未分配、但占用了预设要给其他命令的按键的那些命令。
    let displaced: [WindowCommand.ID]
    /// 所有会失去用户自设快捷键的命令，按目录顺序排列。
    let overwritten: [WindowCommand.ID]

    init(preset: WindowShortcutPreset, current: [WindowCommand.ID: HotKeyBinding]) {
        let assignments = preset.bindings.filter { current[$0.key] != $0.value }
        let claimed = Set(assignments.values)
        let displaced = WindowCommand.ID.allCases.filter { id in
            guard assignments[id] == nil, let binding = current[id] else { return false }
            return claimed.contains(binding)
        }
        self.assignments = assignments
        self.displaced = displaced
        overwritten = WindowCommand.ID.allCases.filter { id in
            (assignments[id] != nil && current[id] != nil) || displaced.contains(id)
        }
    }
}
