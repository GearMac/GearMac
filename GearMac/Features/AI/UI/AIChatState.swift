// 文件职责：单条 AI 聊天的状态机：持有会话、待发送附件与工具范围，驱动流式回复的接收、节流刷新与收尾保存。
// 分层：Model/UI 状态；不 import AppKit/SwiftUI，整体运行在 @MainActor，持久化与网络副作用交给注入的 ChatHistoryStore 与 AIProvider。
import Foundation
import Observation

/// 一条聊天的可观察状态：对外暴露会话、流式进度、待发送附件与工具范围，并负责保存结果。
@MainActor
@Observable
final class AIChatState {
    private(set) var session = ChatSession()
    private(set) var isStreaming = false
    private(set) var isThinking = false
    private(set) var notice: String?
    /// 为下一条消息暂存的文件；它们会随接下来输入的内容一起发出。
    private(set) var pendingAttachments: [ChatAttachment] = []
    /// 窗口里尚未发送的文本；Quick AI 的草稿则存放在命令面板的查询中。
    var draft = ""
    /// 本聊天的工具菜单；新聊天默认启用所有已连接的服务器。
    var toolScope = ChatToolScope()

    /// 每条消费或丢弃暂存图片的路径都会推进它，使后到的解码结果能识别出自己已经过期。
    @ObservationIgnored private(set) var stagingGeneration = 0

    private let history: ChatHistoryStore
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var replyGeneration = 0
    /// 两次刷新之间缓冲的增量，使转录区按固定节奏重绘，而不是每来一个 token 就重绘。
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var pendingReasoning = ""
    /// 回复中最近一段思考的开始时间，供其折叠块显示思考时长。
    @ObservationIgnored private var reasoningStartedAt: Date?
    /// 回复完整结束时回调；此时该聊天才有可供命名的内容。
    @ObservationIgnored var onReplyFinished: (@MainActor (AIChatState) -> Void)?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastFlush = ContinuousClock().now

    private static let flushInterval: Duration = .milliseconds(40)

    /// 绑定用于持久化的历史存储。
    init(history: ChatHistoryStore) {
        self.history = history
    }

    /// 发送一条用户消息并开始流式回复；文本与附件均为空，或正在流式输出时返回 false。
    @discardableResult
    func send(
        _ input: String, using provider: any AIProvider, model: AIModelSelection? = nil,
        webSearch: Bool = false, instructions: String? = nil,
        contextBudget: Int = ChatSession.defaultTextBudget, toolScope: String? = nil
    ) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty, !isStreaming else { return false }
        notice = nil
        session.append(
            ChatMessage(
                role: .user, text: text, images: pendingAttachments.compactMap(\.image),
                documents: pendingAttachments.compactMap(\.document), toolScope: toolScope))
        clearStaging()
        if let model { session.model = model }
        startReply(
            using: provider, webSearch: webSearch, instructions: instructions,
            contextBudget: contextBudget)
        return true
    }

    /// 此后该聊天使用这条路由；已保存的聊天立即落盘，新聊天则在首次发送时记录。
    func setModel(_ model: AIModelSelection) {
        session.model = model
        history.setModel(model, id: session.id)
    }

    /// 重新请求最后一条回复；提问与其附件按首次发送时的原样再次发出。
    @discardableResult
    func regenerate(
        using provider: any AIProvider, model: AIModelSelection? = nil, webSearch: Bool = false,
        instructions: String? = nil, contextBudget: Int = ChatSession.defaultTextBudget
    ) -> Bool {
        guard !isStreaming, session.dropTrailingReply() else { return false }
        notice = nil
        if let model { session.model = model }
        startReply(
            using: provider, webSearch: webSearch, instructions: instructions,
            contextBudget: contextBudget)
        return true
    }

    /// 组装请求、追加一条空的助手消息，并启动接收流式事件的任务。
    private func startReply(
        using provider: any AIProvider, webSearch: Bool, instructions: String?, contextBudget: Int
    ) {
        let request = AIRequest(
            instructions: instructions,
            messages: session.requestMessages(textBudget: contextBudget), webSearch: webSearch,
            conversationID: session.id)
        session.append(ChatMessage(role: .assistant, text: "", state: .streaming))
        isStreaming = true
        isThinking = false
        reasoningStartedAt = nil
        history.save(session)

        replyGeneration += 1
        let generation = replyGeneration
        replyTask = Task { [weak self, provider] in
            do {
                for try await event in provider.stream(request) {
                    guard let self, !Task.isCancelled, self.replyGeneration == generation else {
                        return
                    }
                    self.receive(event)
                }
                guard let self, !Task.isCancelled, self.replyGeneration == generation,
                    self.isStreaming
                else { return }
                self.finishLast(state: .failed, fallback: "The response ended unexpectedly.")
            } catch {
                guard let self, !Task.isCancelled, self.replyGeneration == generation,
                    self.isStreaming
                else { return }
                self.finishLast(state: .failed, fallback: error.localizedDescription)
            }
        }
    }

    /// 记录一条提示信息，供界面显示。
    func report(_ message: String) {
        notice = message
    }

    /// 直接拒绝而不是截断：输入框是解释「本轮过大」的最后机会。
    @discardableResult
    func attach(_ attachment: ChatAttachment) -> ChatAttachmentRefusal? {
        // 刻意不去重：同一个文件粘贴两次，说明你确实想要两份。
        guard pendingAttachments.count < AIAttachmentBudget.maxCount else { return .count }
        guard
            AIAttachmentBudget.admits(
                images: pendingAttachments.compactMap(\.image),
                documents: pendingAttachments.compactMap(\.document),
                addingBytes: attachment.payload.byteCount)
        else { return .size }
        pendingAttachments.append(attachment)
        return nil
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    @discardableResult
    func removeLastAttachment() -> Bool {
        guard !pendingAttachments.isEmpty else { return false }
        pendingAttachments.removeLast()
        return true
    }

    func clearAttachments() {
        clearStaging()
    }

    private func clearStaging() {
        pendingAttachments = []
        stagingGeneration += 1
    }

    /// 取消当前回复并丢弃尚未刷新的增量；仍在流式输出时把该消息标记为失败。
    func cancel() {
        replyGeneration += 1
        replyTask?.cancel()
        replyTask = nil
        guard isStreaming else {
            discardPendingText()
            return
        }
        finishLast(state: .failed, fallback: "Cancelled")
    }

    /// 丢弃当前会话，从零开始一条新聊天。
    func startNewChat() {
        cancel()
        session = ChatSession()
        notice = nil
        clearStaging()
    }

    /// 暂存图片属于挑选它们时所在的那次会话；离开该会话即丢弃。
    @discardableResult
    func open(id: UUID) -> Bool {
        if session.id == id, !session.messages.isEmpty { return true }
        guard let loaded = history.session(id: id) else { return false }
        cancel()
        session = loaded
        notice = nil
        clearStaging()
        return true
    }

    /// 删除指定会话；若正是当前会话，则先重置为一个空聊天。
    func delete(id: UUID) {
        if session.id == id {
            cancel()
            session = ChatSession()
            notice = nil
            clearStaging()
        }
        history.remove(id: id)
    }

    /// 最近一条回复的用量报告，使重新打开的聊天仍知道上一轮的开销。
    var usage: AIUsage? {
        session.messages.last { $0.role == .assistant && $0.usage != nil }?.usage
    }

    /// 当本状态正是展示 `id` 的那一个时为 true；空聊天尚未持有任何内容。
    func holds(_ id: UUID) -> Bool {
        session.id == id && !session.messages.isEmpty
    }

    /// 流式气泡还为空、尚未收到任何内容时显示的一行提示。
    var liveStatus: String? { isThinking ? "Thinking…" : nil }

    /// 最近一条包含文本的助手回复，供复制使用。
    var lastAssistantText: String? {
        session.messages.last(where: { $0.role == .assistant && !$0.text.isEmpty })?.text
    }

    /// 把流式事件分派到当前最后一条助手消息上。
    private func receive(_ event: AIStreamEvent) {
        switch event {
        case .text(let text):
            guard let last = session.messages.last, last.role == .assistant else { return }
            if isThinking { isThinking = false }
            // 按顺序缓冲：这段文本之前的思考必须先落地，不能排到它后面。
            if !pendingReasoning.isEmpty { flushPendingText() }
            queueDelta(text)
        case .thinking:
            isThinking = true
        case .reasoning(let text):
            guard let last = session.messages.last, last.role == .assistant else { return }
            isThinking = true
            if !pendingText.isEmpty { flushPendingText() }
            pendingReasoning += text
            scheduleFlush()
        case .searching(let query):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            isThinking = false
            message.searches.append(
                ChatSearch(
                    query: query, isComplete: false, textOffset: message.text.count,
                    sequence: message.nextSequence))
            session.replaceLast(with: message)
        case .searched(let query):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            if let index = message.searches.lastIndex(where: { !$0.isComplete }) {
                message.searches[index].query = message.searches[index].query ?? query
            }
            message.searches = message.searches.map { Self.completed($0) }
            session.replaceLast(with: message)
        case .toolCall(let id, let origin, let title):
            flushPendingText()
            guard var message = session.messages.last, message.role == .assistant else { return }
            isThinking = false
            message.toolUses.append(
                ChatToolUse(
                    callID: id, origin: origin, title: title, state: .running,
                    textOffset: message.text.count, sequence: message.nextSequence))
            session.replaceLast(with: message)
        case .toolResult(let id, let isError):
            guard var message = session.messages.last, message.role == .assistant else { return }
            guard let index = message.toolUses.lastIndex(where: { $0.callID == id }) else { return }
            message.toolUses[index].state = isError ? .failed : .completed
            session.replaceLast(with: message)
        case .toolCallRequested:
            break
        case .usage(let usage):
            guard var message = session.messages.last, message.role == .assistant else { return }
            message.usage = usage
            session.replaceLast(with: message)
        case .finished:
            finishLast(state: .complete, fallback: "No response")
        }
    }

    /// 先执行一次到期的前置刷新以保证首个 token 立即呈现；随后的任务将其余增量合并刷新。
    private func queueDelta(_ text: String) {
        pendingText += text
        scheduleFlush()
    }

    /// 安排一次节流刷新：距上次刷新已超过间隔则立即刷新，否则合并到下一次。
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        if ContinuousClock().now - lastFlush >= Self.flushInterval { flushPendingText() }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushPendingText()
        }
    }

    /// 把缓冲的思考与文本按顺序写入最后一条助手消息。
    private func flushPendingText() {
        guard !pendingText.isEmpty || !pendingReasoning.isEmpty else { return }
        guard var message = session.messages.last, message.role == .assistant else {
            pendingText = ""
            pendingReasoning = ""
            return
        }
        appendReasoning(pendingReasoning, to: &message)
        pendingReasoning = ""
        if !pendingText.isEmpty {
            // 搜索之后再次出现文本即说明搜索已结束，无论该路由是否明确告知。
            message.searches = message.searches.map { Self.completed($0) }
            // 回答恢复输出，即为那段思考结束的位置。
            closeReasoning(in: &message)
        }
        message.text += pendingText
        pendingText = ""
        session.replaceLast(with: message)
        lastFlush = ContinuousClock().now
    }

    /// 取消待执行的刷新并清空缓冲区。
    private func discardPendingText() {
        flushTask?.cancel()
        flushTask = nil
        pendingText = ""
        pendingReasoning = ""
    }

    /// 收尾最后一条助手消息：补齐文本、标记状态、整理进行中的记录并保存会话。
    private func finishLast(state: ChatMessage.State, fallback: String) {
        flushPendingText()
        discardPendingText()
        guard var message = session.messages.last, message.role == .assistant else { return }
        if state == .failed, !message.text.isEmpty {
            message.text += "\n\n\(fallback)"
        } else if message.text.isEmpty {
            message.text = fallback
        }
        message.state = state
        closeReasoning(in: &message)
        message.searches = message.searches.map { Self.completed($0) }
        // 回合结束时仍在运行的工具调用不会再回报结果，无论是什么结束了该回合。
        message.toolUses = message.toolUses.map { Self.settled($0) }
        session.replaceLast(with: message)
        history.save(session)
        isStreaming = false
        isThinking = false
        replyTask = nil
        if state == .complete { onReplyFinished?(self) }
    }

    /// 回答文本之后的思考属于新的一段，锚定在回答为它停顿的位置。
    /// 把一段思考追加到消息上；必要时新建一段并记录起始时间。
    private func appendReasoning(_ text: String, to message: inout ChatMessage) {
        guard !text.isEmpty else { return }
        let offset = message.text.count
        if let last = message.reasoning.last, last.textOffset == offset, last.duration == nil {
            message.reasoning[message.reasoning.count - 1].text += text
            return
        }
        // 路由的分块分隔符会开启一段思考，但它不应作为折叠块开头的文本。
        let opening = String(text.drop(while: \.isWhitespace))
        guard !opening.isEmpty else { return }
        reasoningStartedAt = Date()
        message.reasoning.append(ChatReasoning(text: opening, textOffset: offset, duration: nil))
    }

    /// 结束消息中最后一段尚未定时的思考，记录其持续时间。
    private func closeReasoning(in message: inout ChatMessage) {
        guard let last = message.reasoning.last, last.duration == nil,
            let started = reasoningStartedAt
        else { return }
        message.reasoning[message.reasoning.count - 1].duration = Date().timeIntervalSince(started)
        reasoningStartedAt = nil
    }
}

/// 流式收尾时用于规范化搜索与工具调用记录的辅助方法。
extension AIChatState {
    /// 把一次搜索标记为已完成。
    fileprivate static func completed(_ search: ChatSearch) -> ChatSearch {
        var search = search
        search.isComplete = true
        return search
    }

    /// 回合结束时仍在运行的工具调用一律标记为失败。
    fileprivate static func settled(_ use: ChatToolUse) -> ChatToolUse {
        guard use.state == .running else { return use }
        var use = use
        use.state = .failed
        return use
    }
}

/// 输入框拒绝再接收文件的原因；具体限额由 `AIAttachmentBudget` 定义。
enum ChatAttachmentRefusal: Equatable, Sendable {
    case count
    case size
    case textTooLong
    case undecodable
    case unreadable
    case unsupported(String)
    case imagesUnsupported
    case documentsUnsupported

    /// 对应的用户可见说明。
    var message: String {
        switch self {
        case .count:
            return "\(AIAttachmentBudget.maxCount) attachments is all one message can carry."
        case .size: return "That file is too big for this message — send these first."
        case .textTooLong:
            let limit = AIAttachmentBudget.maxInlinedTextBytes / 1_024
            return "That text file is too big to attach — \(limit) KB is the limit."
        case .undecodable: return "That file isn't text GearMac can read."
        case .unreadable: return "That file could not be read."
        case .unsupported(let ext):
            return "GearMac can attach images, PDFs and text files, not .\(ext) files."
        case .imagesUnsupported: return "This model can't read images. Switch model to attach one."
        case .documentsUnsupported:
            return "This model can't read PDFs. Switch model, or paste the text instead."
        }
    }
}

/// 一个暂存文件，带有 chip 所显示的名称与预览；两者都不会发往网络。
struct ChatAttachment: Identifiable, Equatable, Sendable {
    /// 同一个暂存列表容纳全部类别，因此生命周期规则对它们一视同仁。
    enum Payload: Equatable, Sendable {
        case image(AIImage)
        case document(AIDocument)

        var byteCount: Int {
            switch self {
            case .image(let image): return image.data.count
            case .document(let document): return document.data.count
            }
        }
    }

    let id = UUID()
    let payload: Payload
    let name: String
    /// 约 40px 的 PNG，大小约 1KB：解码六个的代价低于一次按键引发的重绘。
    let preview: Data?

    var image: AIImage? {
        guard case .image(let image) = payload else { return nil }
        return image
    }

    var document: AIDocument? {
        guard case .document(let document) = payload else { return nil }
        return document
    }

    var kind: AIAttachmentPolicy.Kind {
        switch payload {
        case .image: return .image
        case .document(let document):
            return document.mimeType == AIAttachmentPolicy.pdfMIMEType ? .pdf : .text
        }
    }
}
