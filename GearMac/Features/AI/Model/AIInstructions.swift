// 文件职责：把系统前缀说明（AIPreamble）与用户自定义指令拼装为每一轮发送的 instructions 文本。
// 分层：Model；纯字符串拼装，不得 import AppKit/SwiftUI。
import Foundation

/// 每一轮都先带 `AIPreamble`，再带用户自己的文本；关闭后两者都不带。
enum AIInstructions {
    /// 用户文本放在最后，这样可以限定前缀说明的适用范围，而不与之冲突。
    static func compose(userPrompt: String?, isEnabled: Bool) -> String? {
        guard isEnabled else { return nil }
        let trimmed = userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AIPreamble.text : AIPreamble.text + "\n\n" + trimmed
    }
}
