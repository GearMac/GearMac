// 文件职责：带后缀的数值输入控件，以及检视器统一的字段外框样式修饰器。
// 分层：UI（SwiftUI 设置控件）；输入实时提交给上层回调，失焦或按 ↵ 时做范围钳制。
import AppKit
import SwiftUI

/// 带后缀的数字输入框：每次合法输入都会立即提交，按 ↵ 或失焦时做范围钳制。
struct WindowLayoutNumberField: View {
    let label: String
    /// 无障碍标签的主体，因为“W”单独读出来只是一个字母。
    let name: String
    let suffix: String
    let range: ClosedRange<Int>
    let value: Int
    let onCommit: (Int) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    /// 初值从 `value` 转成字符串，后续由本地文本状态与外部值双向同步。
    init(
        label: String, name: String, suffix: String, range: ClosedRange<Int>, value: Int,
        onCommit: @escaping (Int) -> Void
    ) {
        self.label = label
        self.name = name
        self.suffix = suffix
        self.range = range
        self.value = value
        self.onCommit = onCommit
        _text = State(initialValue: String(value))
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($isFocused)
                .focusEffectDisabled()
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                .onChange(of: text) { _, typed in commitIfValid(typed) }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: value) { _, new in if number(text) != new { text = String(new) } }
            Divider()
                .frame(height: Theme.Spacing.xl)
            Text(suffix)
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.layoutFieldUnit, alignment: .leading)
        }
        .layoutFieldChrome(isFocused: isFocused)
        .accessibilityLabel(name)
        .accessibilityValue("\(value) \(suffix)")
    }

    /// 实时提交，让预览跟上输入，且 ⌘↵ 不会保存到尚未生效的字段值。
    private func commitIfValid(_ typed: String) {
        guard let typed = number(typed), range.contains(typed) else { return }
        onCommit(typed)
    }

    /// 超出范围的数值钳制后回显；无法解析的输入则还原为原值。
    private func commit() {
        guard let typed = number(text) else { return revert() }
        let clamped = min(max(typed, range.lowerBound), range.upperBound)
        text = String(clamped)
        onCommit(clamped)
    }

    /// 放弃当前文本，还原为外部传入的 `value`。
    private func revert() {
        text = String(value)
    }

    /// 解析去除首尾空白后的整数，失败返回 nil。
    private func number(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }
}

extension View {
    /// 检视器统一的控件底面，让输入框、下拉菜单与添加按钮外观一致。
    func layoutFieldChrome(isFocused: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.layoutControlHeight)
            .background(shape.fill(Theme.Colors.cardFill))
            .overlay(shape.stroke(isFocused ? Color.accentColor : Theme.Colors.cardStroke))
            .contentShape(shape)
    }
}
