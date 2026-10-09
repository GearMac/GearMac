// 文件职责：生成会话标题——向模型提供首轮问答的摘录，并清洗模型返回的标题文本。
// 分层：Model；纯函数与常量，不依赖 UI，不产生副作用。
import Foundation

/// 由模型或 harness 为会话给出的名称，需已有第一个回答可供命名。
enum ChatTitle {
    /// 标题最大长度。
    static let maxLength = 60
    /// 足以命名的首轮对话摘录长度，避免把整篇粘贴的文档塞进去。
    static let excerptLength = 800

    /// 请求模型命名时使用的指令。
    static let instructions = """
        Name this conversation in three to six words. Reply with the title only: no quotes, no \
        trailing punctuation, no preamble.
        """

    /// 描述由第一个问题（以及已有时的回答）组成：发送即命名时只有问题。
    static func description(of session: ChatSession) -> String? {
        guard let question = session.messages.first(where: { $0.role == .user }),
            !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let asked = "User: \(question.text.prefix(excerptLength))"
        guard
            let answer = session.messages.first(where: {
                $0.role == .assistant && $0.state == .complete && !$0.text.isEmpty
            })
        else { return asked }
        return asked + "\nAssistant: \(ChatChoices.split(answer.text).text.prefix(excerptLength))"
    }

    /// 模型返回的标题常带引号、标题符号或句末标点，需要清洗。
    static func sanitize(_ raw: String) -> String? {
        let firstLine =
            raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var title = firstLine
        if let label = title.firstMatch(of: #/^(?i:title)\s*:\s*/#) {
            title.removeSubrange(label.range)
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "#*_\"'“”‘’` "))
        while let last = title.last, ".:;,!".contains(last) { title.removeLast() }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return title.count > maxLength ? String(title.prefix(maxLength - 1)) + "…" : title
    }
}
