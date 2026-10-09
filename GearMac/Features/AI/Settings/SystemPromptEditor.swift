// 文件职责：系统提示词编辑器，有内容时默认模糊显示，可通过眼睛按钮切换显示/隐藏并编辑。
// 分层：UI；只绑定文本字符串，不负责持久化。
import SwiftUI

/// 有内容时默认模糊，避免在传屏时打开设置泄露提示词；为空时直接明文显示。
struct SystemPromptEditor: View {
    @Binding var text: String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(AppSettings.self) private var appSettings
    @State private var isRevealed: Bool

    /// 初始化时按当前文本是否为空决定初始显示状态。
    init(text: Binding<String>) {
        _text = text
        _isRevealed = State(initialValue: text.wrappedValue.isBlank)
    }

    /// `TextEditor` 即使在 `.disabled` 下也会保留光标、键盘与选区，因此改用该可编辑标志控制。
    private var isEditable: Bool { isEnabled && isRevealed }

    /// 渲染状态行（提示文案与显示/隐藏按钮）与编辑器本体。
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(
                    text.isBlank
                        ? appSettings.text(AIKey.promptNothingAdded)
                        : appSettings.text(AIKey.promptAddedToEveryMessage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.lg)
                Button {
                    withAnimation(.easeOut(duration: Theme.Duration.enter)) { isRevealed.toggle() }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .help(
                    isRevealed
                        ? appSettings.text(AIKey.promptHide)
                        : appSettings.text(AIKey.promptShow))
                .disabled(text.isBlank)
                .accessibilityLabel(
                    isRevealed
                        ? appSettings.text(AIKey.promptHideAccessibility)
                        : appSettings.text(AIKey.promptShowAccessibility))
            }
            prompt
                .padding(Theme.Spacing.sm)
                .frame(height: Theme.Size.editorTextHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
        }
    }

    /// 可编辑时用 TextEditor，否则以滚动文本展示并按需模糊。
    @ViewBuilder
    private var prompt: some View {
        if isEditable {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.textInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            .blur(radius: isRevealed ? 0 : Theme.Blur.redaction)
        }
    }

    /// 文本容器的行片段内边距，也是 `TextEditor` 自身文本的起始位置。
    private static let textInset: CGFloat = 5
}

/// 本文件内部使用的字符串辅助。
extension String {
    /// 去除首尾空白与换行后是否为空。
    fileprivate var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
