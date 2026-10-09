// 文件职责：把字段的错误与提示文本转为无障碍提示（accessibility hint），供辅助技术朗读。
// 分层：UI；不改变视图的可见文本，仅附加朗读信息。
import SwiftUI

/// 将字段的错误与 `info` 传递给控件；仅绘制出来的文本不会被朗读。
struct ExtensionFieldHint: ViewModifier {
    let info: String?
    var error: String?

    /// 组装无障碍提示：把错误与提示合并为一段朗读文本。
    func body(content: Content) -> some View {
        let spoken = [error, info].compactMap { $0 }.filter { !$0.isEmpty }
        if spoken.isEmpty {
            content
        } else {
            content.accessibilityHint(Text(spoken.joined(separator: ". ")))
        }
    }
}

extension View {
    /// 为字段附加可朗读的说明与错误提示。
    func extensionFieldHint(_ info: String?, error: String? = nil) -> some View {
        modifier(ExtensionFieldHint(info: info, error: error))
    }
}
