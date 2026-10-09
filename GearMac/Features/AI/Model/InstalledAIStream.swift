// 文件职责：解码各个已安装 CLI 的 JSON 流输出，转换为统一的 AIStreamEvent 帧（文本、思考、工具调用、用量与错误）。
// 分层：Model；纯解析，不启动进程也不持有会话状态。
import Foundation

/// 解码一帧得到的标准化流事件与状态。
struct InstalledAIStreamFrame: Equatable, Sendable {
    var events: [AIStreamEvent] = []
    var sessionID: String?
    var error: String?
    var completed = false
    /// CLI 挂起的工具调用；由 runner 应答后本轮继续。
    var controlRequest: ClaudeControlProtocol.Request?
    var unsupportedRequestID: String?
    /// 轮次上限结束了本轮。只有 runner 知道该用哪个数字来说明。
    var stoppedAtRoundCap = false
}

/// 按 CLI 种类分派 JSON 流解码。
enum InstalledAIStreamDecoder {
    /// 解析一行 JSON，按 kind 选择对应的解码分支。
    static func decode(
        _ data: Data, kind: InstalledAIKind, servers: [AIToolServer] = []
    ) -> InstalledAIStreamFrame {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { return InstalledAIStreamFrame() }
        switch kind {
        case .openCode: return openCode(object, type: type)
        case .claude: return claude(object, type: type, servers: servers)
        case .cursor: return cursor(object, type: type)
        case .grok: return grok(object, type: type)
        case .codex: return InstalledAIStreamFrame()
        }
    }

    /// 解码 OpenCode 的流帧。
    private static func openCode(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame(sessionID: object["sessionID"] as? String)
        let part = object["part"] as? [String: Any]
        switch type {
        case "text":
            if let text = part?["text"] as? String, !text.isEmpty { frame.events = [.text(text)] }
        case "step_start":
            frame.events = [.thinking]
        case "step_finish":
            if let tokens = part?["tokens"] as? [String: Any] {
                frame.events.append(
                    .usage(
                        AIUsage(
                            inputTokens: integer(tokens["input"]),
                            outputTokens: integer(tokens["output"]))))
            }
            frame.completed = true
        case "error":
            frame.error = message(in: object) ?? "OpenCode could not finish the response."
        default:
            break
        }
        return frame
    }

    /// 解码 Claude 的流帧（含工具与控制请求）。
    private static func claude(
        _ object: [String: Any], type: String, servers: [AIToolServer]
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame()
        if !servers.isEmpty, type == "control_request" {
            frame.controlRequest = ClaudeControlProtocol.request(object)
            frame.unsupportedRequestID = ClaudeControlProtocol.unsupportedRequestID(object)
            return frame
        }
        if !servers.isEmpty, type == "assistant" || type == "user" {
            frame.events = toolEvents(in: object, servers: servers)
            return frame
        }
        // 摘要会分成多个 thinking 块到达；插入换行避免它们连成一片。
        if type == "stream_event", let event = object["event"] as? [String: Any],
            event["type"] as? String == "content_block_start",
            (event["content_block"] as? [String: Any])?["type"] as? String == "thinking"
        {
            frame.events = [.thinking, .reasoning("\n\n")]
            return frame
        }
        if type == "stream_event", let event = object["event"] as? [String: Any],
            let delta = event["delta"] as? [String: Any]
        {
            switch delta["type"] as? String {
            case "text_delta":
                if let text = delta["text"] as? String, !text.isEmpty {
                    frame.events = [.text(text)]
                }
            case "thinking_delta":
                let thinking = delta["thinking"] as? String ?? ""
                frame.events = thinking.isEmpty ? [.thinking] : [.thinking, .reasoning(thinking)]
            default:
                break
            }
            return frame
        }
        guard type == "result" else { return frame }
        // 触发上限的 subtype 会带空的 `result`，因此要在判断 error 之前先读取它。
        if object["subtype"] as? String == "error_max_turns" {
            frame.stoppedAtRoundCap = true
            return frame
        }
        if object["is_error"] as? Bool == true {
            frame.error = object["result"] as? String ?? "Claude could not finish the response."
            return frame
        }
        if let usage = object["usage"] as? [String: Any] {
            frame.events.append(.usage(claudeUsage(usage, result: object)))
        }
        frame.completed = true
        return frame
    }

    /// `tool_use` 与 `tool_result` 块，构成转录行所需的两个事件。
    private static func toolEvents(
        in object: [String: Any], servers: [AIToolServer]
    ) -> [AIStreamEvent] {
        guard let message = object["message"] as? [String: Any],
            let content = message["content"] as? [[String: Any]]
        else { return [] }
        return content.compactMap { block in
            switch block["type"] as? String {
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String,
                    let call = ClaudeMCPLaunch.route(name)
                else { return nil }
                return .toolCall(
                    id: id, origin: AIToolServerRow.title(of: call.handle, in: servers),
                    title: AIToolServerRow.label(call.tool))
            case "tool_result":
                guard let id = block["tool_use_id"] as? String else { return nil }
                return .toolResult(id: id, isError: block["is_error"] as? Bool == true)
            default:
                return nil
            }
        }
    }

    /// 缓存的 prompt token 不计入 `input_tokens`，且只有 `modelUsage` 给出上下文窗口。
    private static func claudeUsage(_ usage: [String: Any], result: [String: Any]) -> AIUsage {
        let cached = [usage["cache_read_input_tokens"], usage["cache_creation_input_tokens"]]
            .compactMap(integer)
        let details = usage["output_tokens_details"] as? [String: Any]
        // 本轮可能同时用到辅助模型（如 Haiku）；以读取 prompt 最大的那个作为主模型。
        let model = (result["modelUsage"] as? [String: Any])?.values
            .compactMap { $0 as? [String: Any] }
            .max { rank($0) < rank($1) }
        return AIUsage(
            inputTokens: integer(usage["input_tokens"]),
            outputTokens: integer(usage["output_tokens"]),
            cachedInputTokens: cached.isEmpty ? nil : cached.reduce(0, +),
            reasoningTokens: integer(details?["thinking_tokens"]),
            contextWindow: integer(model?["contextWindow"]),
            costUSD: (result["total_cost_usd"] as? NSNumber)?.doubleValue)
    }

    /// 以 prompt token 总量与上下文窗口作为主模型排序依据。
    private static func rank(_ model: [String: Any]) -> (prompt: Int, window: Int) {
        let prompt = ["inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"]
            .compactMap { integer(model[$0]) }.reduce(0, +)
        return (prompt, integer(model["contextWindow"]) ?? 0)
    }

    /// Grok 的错误结果省略 `result`，把原因写在 `errors` 中。
    private static func grok(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        // Grok 复用帧结构但从不走工具：`--deny *` 会拒绝所有调用。
        var frame = claude(object, type: type, servers: [])
        if let sessionID = object["session_id"] as? String, !sessionID.isEmpty {
            frame.sessionID = sessionID
        }
        if type == "result", object["is_error"] as? Bool == true {
            frame.error = grokFailure(object)
        }
        return frame
    }

    /// 从 Grok 的错误结果中提取可读的错误文本。
    private static func grokFailure(_ object: [String: Any]) -> String {
        if let errors = object["errors"] as? [Any] {
            let lines = errors.compactMap { item -> String? in
                guard let text = item as? String else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !lines.isEmpty { return lines.joined(separator: "\n") }
        }
        if let result = object["result"] as? String {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Grok could not finish the response."
    }

    /// 解码 Cursor 的流帧。
    private static func cursor(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame()
        if let sessionID = object["session_id"] as? String, !sessionID.isEmpty {
            frame.sessionID = sessionID
        }
        switch type {
        case "assistant":
            // 实时增量带 timestamp_ms；缓冲冲刷则省略它或带 model_call_id。
            guard object["timestamp_ms"] != nil, object["model_call_id"] == nil else {
                return frame
            }
            if let text = assistantText(in: object), !text.isEmpty {
                frame.events = [.text(text)]
            }
        case "result":
            if object["is_error"] as? Bool == true
                || (object["subtype"] as? String) == "error"
            {
                frame.error =
                    (object["result"] as? String)
                    ?? message(in: object)
                    ?? "Cursor could not finish the response."
                return frame
            }
            frame.completed = true
        default:
            break
        }
        return frame
    }

    /// 从 assistant 消息中拼接出文本内容。
    private static func assistantText(in object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any],
            let content = message["content"] as? [[String: Any]]
        else { return nil }
        let parts = content.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" || part["type"] == nil else { return nil }
            return part["text"] as? String
        }
        let text = parts.joined()
        return text.isEmpty ? nil : text
    }

    /// 把 NSNumber 转为 Int。
    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// 从 message 或 error.message 中取出错误文本。
    private static func message(in object: [String: Any]) -> String? {
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return nil
    }
}
