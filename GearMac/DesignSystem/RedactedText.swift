// 文件职责：提供「点击才显示」的脱敏文本视图 `RedactedText`，默认展示替身文本，点击后在原值与替身间切换。
// 分层：UI（DesignSystem）；替身由 `RedactedPlaceholder` 生成，真实值仅在本地状态中切换显示。
import SwiftUI

/// 仅在用户主动请求时才显示：设置面板容易被截图，而这里展示的往往是人的姓名。
struct RedactedText: View {
    let value: String
    var revealHelp = "Click to reveal"
    var hideHelp = "Click to hide"

    @State private var isRevealed = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: Theme.Duration.enter)) { isRevealed.toggle() }
        } label: {
            Text(isRevealed ? value : RedactedPlaceholder.forValue(value))
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                .blur(radius: isRevealed ? 0 : Theme.Blur.redaction)
                .textSelection(.disabled)
        }
        .buttonStyle(.plain)
        .help(isRevealed ? hideHelp : revealHelp)
        // 对看不到模糊效果的用户而言，把替身读出来不仅无用，还会误导。
        .accessibilityLabel(isRevealed ? value : "Hidden: \(revealHelp.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}
