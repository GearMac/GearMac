// 文件职责：驱动 Codex 订阅的一轮生成：建线程、流式接收 app-server 通知并映射为事件，以及中断处理。
// 分层：Service；主 actor 上运行，把 app-server 的线程/轮次概念映射为应用的流式事件。
import Foundation

/// Codex 轮次运行器：把一次 `AIRequest` 映射为一个 app-server 线程与轮次，并驱动其生命周期。
@MainActor
final class CodexTurnRunner {
    private static let safetyInstructions = """
        You are providing text generation inside GearMac. Never execute commands, read local files, \
        inspect the environment, or modify files.
        """
    private static let webSearchInstructions = """
        You may use web search when the answer depends on current or external information. For a \
        follow-up, use the sources already in this conversation and search again when more detail \
        or verification is needed. Find the source yourself rather than asking the user for a link \
        you can search for. Cite a source as a markdown link whose text is the publication's name, \
        never "Read more" or a URL.
        """
    private static let noWebSearchInstructions = "Do not use web search."

    var connect: (@MainActor ([AIToolServer]) async throws -> [ChatGPTSubscription.Model])?
    var onTurnEnded: (@MainActor () -> Void)?

    /// 一次会话在本地保留的上下文：线程 ID、模型、指令与已发送的消息。
    private struct Conversation {
        let id: UUID
        let threadID: String
        let model: String
        let instructions: String
        let webSearch: Bool
        var messages: [AIMessage]
    }

    /// 单个流的活动状态；引用标识保证过时的清理不会误伤它的后继。
    private final class Turn {
        let continuation: AIProviderStream.Continuation
        /// 此轮可调用的服务器与会回答问题的人；未装载任何工具的轮次会拒绝一切请求。
        let servers: [AIToolServer]
        let session: AIToolServerSession?
        var threadID: String?
        var turnID: String?
        let conversationID: UUID?
        var conversation: Conversation?
        var reply = ""
        /// 上一个增量所属的摘要分段，用于让下一段另起一段。
        var summaryPart: String?
        /// 一次征询所涉及的工具：命名它的 item 总是在征询之前出现。
        var startedTools: [String: String] = [:]
        var spentCalls = 0

        init(
            continuation: AIProviderStream.Continuation, servers: [AIToolServer],
            session: AIToolServerSession?, conversationID: UUID?
        ) {
            self.continuation = continuation
            self.servers = servers
            self.session = session
            self.conversationID = conversationID
        }

        var roundCap: Int? { session == nil ? 1 : session?.rounds }
    }

    /// 单个流的引用标识，在其轮次存在之前就已发出。
    private final class TurnToken: Sendable {}

    private let client: CodexAppServerClient
    private var turns: [ObjectIdentifier: Turn] = [:]
    private var conversations: [UUID: Conversation] = [:]
    /// 其 Stop 早于轮次 ID 到达的线程；第一个命名它的 ID 会消耗掉这个 Stop。
    private var pendingInterruptThreadIDs: Set<String> = []

    /// 绑定客户端并接管其征询与重启回调。
    init(client: CodexAppServerClient) {
        self.client = client
        client.onElicitation = { [weak self] elicitation in
            await self?.consent(to: elicitation) ?? false
        }
        client.onRelaunch = { [weak self] in self?.endStrandedTurns() }
    }

    /// 是否存在正在运行的轮次。
    var isActive: Bool { !turns.isEmpty }

    /// 以流的形式发起一轮：内部启动任务驱动，流终止时取消任务并收尾。
    nonisolated func stream(
        _ request: AIRequest, model: String, effort: String?,
        toolServers: AIToolServerSession? = nil
    ) -> AIProviderStream {
        AIProviderStream { continuation in
            let token = TurnToken()
            let task = Task { [weak self] in
                await self?.startTurn(
                    request, model: model, effort: effort, toolServers: toolServers,
                    continuation: continuation, token: token)
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in self?.endTurn(token) }
            }
        }
    }

    /// 按流标识结束一轮（中断对应的 Codex 轮次）。
    private func endTurn(_ token: TurnToken) {
        guard let turn = turns[ObjectIdentifier(token)] else { return }
        interrupt(turn, key: ObjectIdentifier(token))
    }

    /// 清空会话缓存并中断全部存活轮次。
    func reset() {
        conversations.removeAll()
        for (key, turn) in turns { interrupt(turn, key: key) }
    }

    /// 丢弃指定会话的本地上下文，并解除与之关联的轮次。
    func discardConversation(id: UUID) {
        conversations[id] = nil
        for turn in turns.values where turn.conversationID == id { turn.conversation = nil }
    }

    /// 处理 app-server 通知：按 threadId 定位轮次，并把各类事件翻译为流事件。
    func handle(method: String, params: [String: JSONValue]) {
        guard let thread = params["threadId"]?.stringValue else { return }
        if pendingInterruptThreadIDs.contains(thread) {
            handleArmed(method: method, params: params, threadID: thread)
            return
        }
        guard let entry = turns.first(where: { $0.value.threadID == thread }) else { return }
        let key = entry.key
        let turn = entry.value
        let continuation = turn.continuation
        switch method {
        case "item/agentMessage/delta":
            guard let delta = params["delta"]?.stringValue, !delta.isEmpty else { return }
            if turn.conversation != nil { turn.reply += delta }
            continuation.yield(.text(delta))
        // 使用摘要而非原始 reasoning：原始流默认关闭，且会重复摘要内容。
        case "item/reasoning/summaryTextDelta":
            guard let delta = params["delta"]?.stringValue, !delta.isEmpty else { return }
            let part = "\(params["itemId"]?.stringValue ?? ""):\(params["summaryIndex"]?.intValue ?? 0)"
            if let previous = turn.summaryPart, previous != part { continuation.yield(.reasoning("\n\n")) }
            turn.summaryPart = part
            continuation.yield(.reasoning(delta))
        case "item/started":
            guard let item = params["item"]?.objectValue else { return }
            switch item["type"]?.stringValue {
            case "webSearch": continuation.yield(.searching(item["query"]?.stringValue))
            case "reasoning": continuation.yield(.thinking)
            case "mcpToolCall": startToolCall(item, in: turn, key: key)
            default: break
            }
        case "item/completed":
            guard let item = params["item"]?.objectValue else { return }
            switch item["type"]?.stringValue {
            case "webSearch": continuation.yield(.searched(item["query"]?.stringValue))
            case "mcpToolCall":
                guard let id = item["id"]?.stringValue else { return }
                continuation.yield(
                    .toolResult(id: id, isError: item["status"]?.stringValue != "completed"))
            default: break
            }
        case "turn/started":
            // 提前捕获，使即使 turn/start 的响应永远不到，Stop 也能中断这一轮。
            if let id = params["turn"]?.objectValue?["id"]?.stringValue { turn.turnID = id }
        case "turn/completed":
            guard let completed = params["turn"]?.objectValue else { return }
            switch completed["status"]?.stringValue {
            case "completed":
                if var conversation = turn.conversation {
                    conversation.messages.append(AIMessage(role: .assistant, text: turn.reply))
                    conversations[conversation.id] = conversation
                }
                continuation.yield(.finished)
                continuation.finish()
            case "failed":
                continuation.finish(
                    throwing: AIProviderError.responseFailed(
                        completed["error"]?.objectValue?["message"]?.stringValue
                            ?? "Codex could not finish the response."))
            default:
                continuation.finish(
                    throwing: AIProviderError.responseFailed("The response was interrupted."))
            }
            clear(key)
        case "error":
            guard params["willRetry"]?.boolValue != true else { return }
            continuation.finish(
                throwing: AIProviderError.responseFailed(
                    params["error"]?.objectValue?["message"]?.stringValue
                        ?? "Codex returned an error."))
            clear(key)
        default:
            break
        }
    }

    /// 一次调用的显示行与轮次上限：Codex 不给出轮次，因此改数调用次数，这更严格。
    private func startToolCall(_ item: [String: JSONValue], in turn: Turn, key: ObjectIdentifier) {
        guard let id = item["id"]?.stringValue else { return }
        let name = item["server"]?.stringValue ?? ""
        let handle = CodexMCPLaunch.handle(ofServer: name)
        if let handle, let tool = item["tool"]?.stringValue { turn.startedTools[handle] = tool }
        let origin = handle.map { AIToolServerRow.title(of: $0, in: turn.servers) }
        turn.continuation.yield(
            .toolCall(
                id: id, origin: origin ?? AIToolServerRow.label(name),
                title: AIToolServerRow.label(item["tool"]?.stringValue ?? "")))
        turn.spentCalls += 1
        guard let roundCap = turn.roundCap, turn.spentCalls > roundCap else { return }
        // 先结束再接中断，否则中断自身的清理会报出另一个原因。
        turn.continuation.finish(
            throwing: AIProviderError.responseFailed(
                "Stopped after \(roundCap) rounds of tool calls."))
        interrupt(turn, key: key)
    }

    /// 按线程路由，使每个聊天的调用都在该聊天自己的同意策略下征询。
    private func consent(to elicitation: CodexElicitation) async -> Bool {
        guard let turn = turns.values.first(where: { $0.threadID == elicitation.threadID }),
            !turn.servers.isEmpty, let session = turn.session,
            let handle = CodexMCPLaunch.handle(ofServer: elicitation.serverName)
        else { return false }
        let tool = elicitation.namedTool ?? turn.startedTools[handle] ?? elicitation.toolName
        return await session.consent(AIToolServerCall(handle: handle, tool: tool))
    }

    /// 服务器清单在启动时固定，因此装载了另一份清单的轮次会结束现有线程。
    private func endStrandedTurns() {
        conversations.removeAll()
        pendingInterruptThreadIDs.removeAll()
        for (key, turn) in turns where turn.threadID != nil {
            turn.continuation.finish(
                throwing: AIProviderError.responseFailed(
                    "Codex restarted to change the tools another chat can use."))
            clear(key)
        }
    }

    /// Stop 已丢下的线程，只为了等那个 Stop 缺失的轮次 ID 而保留监听。
    private func handleArmed(
        method: String, params: [String: JSONValue], threadID: String
    ) {
        switch method {
        case "turn/started":
            guard let id = params["turn"]?.objectValue?["id"]?.stringValue else { return }
            interruptOnce(threadID: threadID, turnID: id)
        case "turn/completed", "error":
            pendingInterruptThreadIDs.remove(threadID)
        default:
            break
        }
    }

    /// 执行一轮开始：解析工具与模型、建立/复用线程、发起 turn/start，并处理取消与错误。
    private func startTurn(
        _ request: AIRequest,
        model: String,
        effort: String?,
        toolServers: AIToolServerSession?,
        continuation: AIProviderStream.Continuation,
        token: TurnToken
    ) async {
        guard
            let promptIndex = request.messages.lastIndex(where: {
                $0.role == .user
                    && (!$0.images.isEmpty
                        || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            })
        else {
            continuation.finish(
                throwing: AIProviderError.unavailable("There is no user message to send."))
            return
        }
        let key = ObjectIdentifier(token)
        var tookOwnership = false
        do {
            let servers = await toolServers?.servers() ?? []
            // 清单是启动期的事实，因此 `connect` 可能重启一个装载了其他清单的服务器。
            let models = try await connect?(servers) ?? []
            // 模型发现会吞掉错误，所以发生在 connect 内的 Stop 会在这里浮出。
            try Task.checkCancellation()
            guard !model.isEmpty else {
                throw AIProviderError.unavailable(
                    "No Codex model is available for this account.")
            }
            if let id = request.conversationID,
                turns.values.contains(where: { $0.conversationID == id })
            {
                throw AIProviderError.unavailable("A reply is already running for this chat.")
            }
            let turn = Turn(
                continuation: continuation, servers: servers, session: toolServers,
                conversationID: request.conversationID)
            turns[key] = turn
            tookOwnership = true

            guard models.isEmpty || models.contains(where: { $0.id == model }) else {
                throw AIProviderError.unavailable(
                    "\(model) is no longer available. Choose another model in Settings.")
            }

            try await prepareThread(
                for: request, promptIndex: promptIndex, model: model, turn: turn, key: key)
            guard turns[key] === turn, !Task.isCancelled, let threadID = turn.threadID else { return }
            // 非结构化子进程可存活于 Stop 之外，因此它返回的轮次 ID 仍可被中断。
            var turnParameters: [String: Any] = [
                "threadId": threadID,
                "model": model,
                "approvalPolicy": servers.isEmpty ? "never" : "untrusted",
                "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                "input": turnInput(for: request.messages[promptIndex])
            ]
            if let effort { turnParameters["effort"] = effort }
            let turnTask = Task { [client] in
                try await client.request(
                    method: "turn/start", params: turnParameters)
            }
            let turnID = try await turnTask.value["turn"]?.objectValue?["id"]?.stringValue
            guard turns[key] === turn, !Task.isCancelled else {
                if turns[key] === turn { interrupt(turn, key: key) }
                if let turnID { interruptOnce(threadID: threadID, turnID: turnID) }
                return
            }
            if let turnID { turn.turnID = turnID }
        } catch is CancellationError {
            if tookOwnership {
                endTurn(token)
            } else if turns.isEmpty {
                // 获取所有权之前的 Stop 同样跳过了 `endTurn`，因此空闲定时器需在此重新武装。
                onTurnEnded?()
            }
        } catch {
            continuation.finish(throwing: ChatGPTSubscriptionManager.userFacing(error))
            if let turn = turns[key] {
                interrupt(turn, key: key)
            } else if !tookOwnership, turns.isEmpty {
                onTurnEnded?()
            }
        }
    }

    /// 准备一个 app-server 线程：条件相同时复用，否则新建并注入历史记录。
    private func prepareThread(
        for request: AIRequest, promptIndex: Int, model: String, turn: Turn, key: ObjectIdentifier
    ) async throws {
        let instructions = developerInstructions(for: request, hasTools: !turn.servers.isEmpty)
        let history = request.messages[..<promptIndex].filter { $0.role != .system }.map {
            AIMessage(role: $0.role, text: $0.text)
        }
        let previous = request.conversationID.flatMap { conversations.removeValue(forKey: $0) }
        if let previous, previous.model == model, previous.instructions == instructions,
            previous.webSearch == request.webSearch, previous.messages == history
        {
            turn.threadID = previous.threadID
            turn.conversation = previous
        } else {
            let threadResponse = try await client.request(
                method: "thread/start",
                params: [
                    "model": model,
                    "cwd": client.workspace.path,
                    "approvalPolicy": turn.servers.isEmpty ? "never" : "untrusted",
                    "sandbox": "read-only",
                    "ephemeral": true,
                    "config": ["web_search": request.webSearch ? "live" : "disabled"],
                    "developerInstructions": instructions
                ])
            guard let threadID = threadResponse["thread"]?.objectValue?["id"]?.stringValue else {
                throw CodexAppServerClient.ClientError.requestFailed(
                    "Codex returned no generation thread.")
            }
            guard turns[key] === turn, !Task.isCancelled else { return }
            turn.threadID = threadID

            let items = historyItems(from: request.messages[..<promptIndex])
            if !items.isEmpty {
                _ = try await client.request(
                    method: "thread/inject_items",
                    params: ["threadId": threadID, "items": items])
            }
            if let id = request.conversationID {
                turn.conversation = Conversation(
                    id: id, threadID: threadID, model: model, instructions: instructions,
                    webSearch: request.webSearch, messages: history)
            }
        }
        guard turns[key] === turn, !Task.isCancelled else { return }
        if request.messages.contains(where: { !$0.images.isEmpty || !$0.documents.isEmpty }) {
            turn.conversation = nil
        }
        turn.conversation?.messages.append(
            AIMessage(role: .user, text: request.messages[promptIndex].text))
    }

    /// 组装开发者指令：安全边界、可用工具、搜索策略，以及请求自带的指令。
    private func developerInstructions(for request: AIRequest, hasTools: Bool) -> String {
        let requestInstructions =
            ([request.instructions]
            + request.messages.compactMap {
                $0.role == .system ? $0.text : nil
            }).compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        var allowedTools: [String] = []
        if hasTools { allowedTools.append("the MCP tools supplied with this request") }
        if request.webSearch { allowedTools.append("web search") }
        let tools =
            allowedTools.isEmpty
            ? "Never invoke tools or access external resources. Use only the request content supplied by GearMac."
            : "The only tools you may use are \(allowedTools.joined(separator: " and "))."
        let search = request.webSearch ? Self.webSearchInstructions : Self.noWebSearchInstructions
        return ([Self.safetyInstructions, tools, search] + requestInstructions).joined(separator: "\n\n")
    }

    /// 将一条消息转为 Codex 的 turn 输入数组（文本与图片）。
    private func turnInput(for message: AIMessage) -> [[String: Any]] {
        var input: [[String: Any]] = []
        if !message.text.isEmpty { input.append(["type": "text", "text": message.text]) }
        input += message.images.map { ["type": "image", "url": $0.dataURL] }
        return input
    }

    /// 将历史消息转为可注入线程的 item 数组，跳过系统消息与空内容。
    private func historyItems(from messages: ArraySlice<AIMessage>) -> [[String: Any]] {
        messages.compactMap { message in
            guard message.role != .system,
                !message.images.isEmpty
                    || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let role = message.role == .user ? "user" : "assistant"
            let contentType = message.role == .user ? "input_text" : "output_text"
            var content: [[String: Any]] = []
            if !message.text.isEmpty { content.append(["type": contentType, "text": message.text]) }
            content += message.images.map { ["type": "input_image", "image_url": $0.dataURL] }
            return ["type": "message", "role": role, "content": content]
        }
    }

    /// 中断一轮：已知轮次 ID 则直接中断，否则先武装线程等待其 ID。
    private func interrupt(_ turn: Turn, key: ObjectIdentifier) {
        clear(key)
        guard let threadID = turn.threadID else { return }
        guard let turnID = turn.turnID else {
            // Stop 早于 ID 到达：先武装线程，而不是丢掉服务端仍在运行的这一轮。
            pendingInterruptThreadIDs.insert(threadID)
            return
        }
        interrupt(threadID: threadID, turnID: turnID)
    }

    /// 两种命名方式都可能先到达；解除武装可避免一次 Stop 触发两次中断。
    private func interruptOnce(threadID: String, turnID: String) {
        guard pendingInterruptThreadIDs.remove(threadID) != nil else { return }
        interrupt(threadID: threadID, turnID: turnID)
    }

    /// 向服务端发送中断请求。
    private func interrupt(threadID: String, turnID: String) {
        Task { [weak self] in
            _ = try? await self?.client.request(
                method: "turn/interrupt", params: ["threadId": threadID, "turnId": turnID])
        }
    }

    /// 收尾会结束一个被服务端抛弃的流；最后一个存活轮次结束时重新武装空闲关停。
    private func clear(_ key: ObjectIdentifier) {
        guard let turn = turns.removeValue(forKey: key) else { return }
        turn.continuation.finish(
            throwing: AIProviderError.responseFailed("The Codex connection was interrupted."))
        if let threadID = turn.threadID { client.cancelElicitations(threadID: threadID) }
        if turns.isEmpty { onTurnEnded?() }
    }
}
