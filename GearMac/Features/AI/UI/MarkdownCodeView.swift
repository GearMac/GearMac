// 文件职责：渲染 Markdown 代码块，展示语言标签、复制按钮与等宽正文。
// 分层：UI；不自行滚动，交由会话记录的滚动容器统一处理。
import SwiftUI

/// 行内容软换行：再套一个滚动视图会与会话记录自身的边缘渐隐效果冲突。
struct MarkdownCodeView: View {
    @Environment(\.metrics) private var metrics
    let language: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.md) {
                if let language {
                    Text(language)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                ChatCopyButton(text: text, subject: "Code")
            }
            Text(text)
                .font(metrics.typography.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke))
    }
}
