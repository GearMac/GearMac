// 文件职责：提供带「显示/隐藏」按钮的密文输入控件 `RevealableSecureField`，在 SecureField 与 TextField 之间切换并保持光标选区。
// 分层：UI（DesignSystem，AppKit 桥接）；通过 NSTextView 字段编辑器读写选区，仅在被编辑时生效。
import AppKit
import SwiftUI

/// 旁边带显示/隐藏按钮的密文输入框；调用方设置的 field style 会作用到内部控件。
struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    var prompt: Text?

    @State private var isRevealed = false
    @State private var carriedSelection: NSRange?
    @FocusState private var focusedField: Field?

    private enum Field { case secure, plain }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isRevealed {
                TextField(title, text: $text, prompt: prompt)
                    .autocorrectionDisabled()
                    .writingToolsBehavior(.disabled)
                    .focused($focusedField, equals: .plain)
            } else {
                SecureField(title, text: $text, prompt: prompt)
                    .focused($focusedField, equals: .secure)
            }
            Button {
                setRevealed(!isRevealed)
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide" : "Show")
            .disabled(text.isEmpty)
            .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
        }
        .onChange(of: text.isEmpty) { _, isEmpty in
            if isEmpty, isRevealed { setRevealed(false) }
        }
        .onChange(of: focusedField) { _, field in
            guard field != nil, let selection = carriedSelection else { return }
            carriedSelection = nil
            restore(selection)
        }
    }

    /// 键盘输入的落点；仅当它在编辑本控件的 `text` 时才归本控件所有。
    private var fieldEditor: NSTextView? {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor,
            editor.string == text
        else { return nil }
        return editor
    }

    /// 切换显示状态，并跨控件迁移焦点与光标选区。
    private func setRevealed(_ revealed: Bool) {
        let wasFocused = focusedField != nil
        carriedSelection = wasFocused ? fieldEditor?.selectedRange() : nil
        isRevealed = revealed
        // 替换输入框会导致失焦；这里直接指定新输入框，把焦点迁移过去。
        if wasFocused { focusedField = revealed ? .plain : .secure }
    }

    /// AppKit 在获得焦点时会全选文本，若不还原，下一次按键就会整体替换内容。
    private func restore(_ selection: NSRange) {
        guard let editor = fieldEditor, NSMaxRange(selection) <= (editor.string as NSString).length
        else { return }
        editor.setSelectedRange(selection)
        editor.scrollRangeToVisible(selection)
    }
}
