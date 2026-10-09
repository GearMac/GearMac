// 文件职责：定义一次 AI 会话（ChatSession）及其转录消息，负责上下文预算裁剪、消息追加与列表摘要。
// 分层：Model；纯值类型，不依赖 AppKit/SwiftUI，不做任何 I/O。
import Foundation

/// 一次聊天会话：持有模型选择、转录消息与时间戳，并提供上下文预算内的请求构建。
struct ChatSession: Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    private(set) var updatedAt: Date
    private(set) var messages: [ChatMessage]
    /// 该会话使用的路由，重新打开时会回到同一个模型。
    var model: AIModelSelection?

    init(
        id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil,
        messages: [ChatMessage] = [], model: AIModelSelection? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messages = messages
        self.model = model
    }

    /// 会话标题：取第一条用户消息的摘要，没有则返回 "New Chat"。
    var title: String {
        guard let text = messages.first(where: { $0.role == .user })?.text else {
            return "New Chat"
        }
        return Self.summary(text, limit: 72)
    }

    /// 会话预览：最后一条非空消息的摘要。
    var preview: String {
        guard let text = messages.last(where: { !$0.text.isEmpty })?.text else { return "" }
        return Self.summary(text, limit: 120)
    }

    /// 用于会话列表的轻量摘要视图。
    var summary: ChatConversation {
        ChatConversation(
            id: id, title: title, preview: preview, createdAt: createdAt,
            updatedAt: updatedAt, messageCount: messages.count)
    }

    /// `textBudget` 属于路由而非会话：端上模型的上下文窗口远小于云端模型。
    func requestMessages(textBudget: Int = Self.defaultTextBudget) -> [AIMessage] {
        Self.boundedContext(
            historyMessages.map { message in
                AIMessage(
                    role: message.role == .user ? .user : .assistant,
                    text: message.text, images: message.images, documents: message.documents)
            }, textBudget: textBudget)
    }

    /// 默认文本预算（以 UTF-8 字节计）。
    static let defaultTextBudget = 100_000

    /// 一次请求可作为历史携带的轮次：失败或未完成的回复不会外发。
    var historyMessages: [ChatMessage] {
        messages.filter { $0.role == .user || $0.state == .complete }
    }

    /// 按预算自身的单位计数；超出 `textBudget` 后最旧的轮次不再外发。
    var historyBytes: Int {
        historyMessages.reduce(0) { $0 + $1.text.utf8.count }
    }

    /// `requestMessages` 实际会发送的轮次数，仅计数而不构建或内联这些消息。
    func sentMessageCount(textBudget: Int = Self.defaultTextBudget) -> Int {
        let history = historyMessages
        guard let newest = history.lastIndex(where: { $0.role == .user }) else {
            return history.count
        }
        var remaining = textBudget
        let tail = history[(newest + 1)...]
        remaining -= tail.reduce(0) { $0 + $1.text.utf8.count }
        var head: [ChatMessage.Role] = []
        for message in history[..<newest].reversed() {
            remaining -= message.text.utf8.count
            guard remaining >= 0 else { break }
            head.append(message.role)
        }
        // 与 `boundedContext` 保持一致：切片不会以一句提问已落出的回复开头。
        while head.last == .assistant { head.removeLast() }
        return head.count + 1 + tail.count
    }

    /// 较早的轮次以文本形式保留在 `textBudget` 之内，使请求体积不随会话增长。
    static func boundedContext(
        _ messages: [AIMessage], textBudget: Int = Self.defaultTextBudget
    ) -> [AIMessage] {
        guard let newest = messages.lastIndex(where: { $0.role == .user }) else { return messages }
        var remaining = textBudget
        var tail: [AIMessage] = []
        for message in messages[(newest + 1)...] {
            remaining -= message.text.utf8.count
            tail.append(AIMessage(role: message.role, text: message.text))
        }
        var head: [AIMessage] = []
        for message in messages[..<newest].reversed() {
            remaining -= message.text.utf8.count
            guard remaining >= 0 else { break }
            head.append(AIMessage(role: message.role, text: message.text))
        }
        // 切片以触发它的用户轮次开头；孤立的回复只会显得杂乱。
        while head.last?.role == .assistant { head.removeLast() }
        let prompt = messages[newest]
        let kept = AIAttachmentBudget.bounded(prompt.images, prompt.documents)
        // 在此处内联而非写入 `ChatMessage.text`：转录的标题取自第一条用户文本。
        let bounded = AIMessage(
            role: prompt.role,
            text: AIAttachmentPolicy.prompt(text: prompt.text, documents: kept.documents),
            images: kept.images,
            documents: kept.documents.filter { $0.mimeType == AIAttachmentPolicy.pdfMIMEType })
        return head.reversed() + [bounded] + tail
    }

    /// 追加一条消息并推进更新时间。
    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = max(updatedAt, message.sentAt)
    }

    /// 用新消息替换最后一条，并把更新时间推进到 now。
    mutating func replaceLast(with message: ChatMessage, now: Date = Date()) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1] = message
        updatedAt = max(updatedAt, now)
    }

    /// 重新生成的前半步：只移除末尾的回复，它所回答的提问保留。
    @discardableResult
    mutating func dropTrailingReply() -> Bool {
        guard messages.last?.role == .assistant, messages.count > 1 else { return false }
        messages.removeLast()
        return true
    }

    /// 「复制会话」写入剪贴板的内容：每轮以说话者标注，附件按名称列出。
    func markdownTranscript(title: String) -> String {
        var parts = ["# \(title)"]
        for message in messages
        where !message.text.isEmpty || !message.documents.isEmpty || !message.images.isEmpty {
            var turn = message.role == .user ? "**You**" : "**AI**"
            let names = message.documents.map(\.name) + message.images.map { _ in "Image" }
            if !names.isEmpty { turn += " _(attached: \(names.joined(separator: ", ")))_" }
            // 选项围栏在界面上绘制为按钮；粘贴到转录文本里只剩标记。
            let text = message.role == .assistant ? ChatChoices.split(message.text).text : message.text
            parts.append(turn + "\n\n" + text)
        }
        return parts.joined(separator: "\n\n")
    }

    /// 合并空白并把文本截断到 limit 个字符。
    private static func summary(_ text: String, limit: Int) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
    }
}

/// 会话列表中的一条记录：标题、预览与元数据，并叠加可选的自定义/生成标题。
struct ChatConversation: Identifiable, Equatable, Sendable {
    let id: UUID
    /// 由第一个问题派生；重命名单独存放，绝不覆盖它。
    let title: String
    let preview: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    var customTitle: String?
    var isPinned = false
    /// 由该会话的 harness 或模型命名的标题；重命名仍优先于它。
    var generatedTitle: String?

    /// 展示用标题：自定义标题优先，其次模型生成的标题，最后回退到派生标题。
    var displayTitle: String { customTitle ?? generatedTitle ?? title }
}
