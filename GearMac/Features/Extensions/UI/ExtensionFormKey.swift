// 文件职责：把键盘按键映射为扩展表单的动作（激活、提交、吞掉、忽略）。
// 分层：UI 输入处理；纯函数逻辑，不持有状态。
import SwiftUI

/// 扩展表单的按键解析：将按键与修饰键映射为表单动作。
enum ExtensionFormKey {
    /// 被视为“回车”的按键集合（回车键与 Ctrl-M 控制字符）。
    static let enterKeys: Set<KeyEquivalent> = [.return, KeyEquivalent("\u{3}")]

    /// 按键解析结果的动作：activate 激活控件，submit 提交，consume 吞掉按键，ignored 忽略。
    enum Action: Equatable {
        case activate, submit, consume, ignored
    }

    /// 根据当前字段、按键、修饰键与状态（菜单是否打开、是否正在输入法组合）解析出应执行的动作。
    static func resolve(
        field: ExtensionFormField, key: KeyEquivalent, modifiers: EventModifiers,
        repeating: Bool = false, menuOpen: Bool = false, composing: Bool = false
    ) -> Action {
        guard !menuOpen, !composing, field.isFocusable else { return .ignored }
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if enterKeys.contains(key) {
            if modifiers == .command { return repeating ? .consume : .submit }
            guard modifiers.isEmpty else { return .ignored }
            if field == .textArea { return .ignored }
            if field == .text || repeating { return .consume }
            return .activate
        }
        if key == .space, modifiers.isEmpty, field == .checkbox || field == .filePicker {
            return repeating ? .consume : .activate
        }
        return .ignored
    }
}
