// 文件职责：聊天消息旁的复制按钮：复制纯文本后短暂显示对勾反馈。
// 分层：UI（SwiftUI 视图）；仅调用 Paster 复制到剪贴板，无网络与持久化。
import SwiftUI

/// 聊天消息旁的复制按钮：复制后短暂显示对勾，随后自行复位。
struct ChatCopyButton: View {

    @Environment(\.metrics) private var metrics
    let text: String
    var subject = "Message"

    /// 时间戳就代表复制事件：新的时间戳会重新触发复位，因此再次点击能继续保留对勾。
    @State private var copiedAt: Date?

    private var copied: Bool { copiedAt != nil }

    var body: some View {
        Button {
            Paster.copyPlainText(text)
            copiedAt = Date()
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(metrics.typography.keyCap)
                .foregroundStyle(tint)
                .frame(width: metrics.size.chatMessageAction, height: metrics.size.chatMessageAction)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy \(subject)")
        .task(id: copiedAt) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            copiedAt = nil
        }
    }

    private var tint: Color {
        if copied { return Theme.Colors.success }
        return Theme.Colors.textSecondary
    }
}
