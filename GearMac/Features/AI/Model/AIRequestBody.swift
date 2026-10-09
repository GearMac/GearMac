// 文件职责：按 API 形态（openAICompatible / anthropic）把 AIRequest 组装为对应的 JSON 请求体。
// 分层：Model；纯函数构造字典，不得 import AppKit/SwiftUI。
import Foundation

/// 各路由期望的 JSON 请求体。刻意保持纯函数：形状写错会导致对话中途返回 400。
enum AIRequestBody {
    /// 按配置的 API 形态分派到对应的请求体构造器。
    static func make(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        switch configuration.shape {
        case .openAICompatible: return openAI(input, configuration: configuration)
        case .anthropic: return anthropic(input, configuration: configuration)
        }
    }

    /// 构造 OpenAI 兼容形态的请求体：system 指令、联网插件、推理强度与工具定义。
    private static func openAI(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        var messages = input.messages.compactMap(openAIMessage)
        if let instructions = input.instructions?.nonEmpty {
            messages.insert(["role": "system", "content": instructions], at: 0)
        }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "stream": true
        ]
        // OpenRouter 自带的搜索层，对它路由的所有模型都生效。
        if input.webSearch, configuration.provider == .openRouter {
            body["plugins"] = [["id": "web"]]
        }
        if let effort = configuration.effort, configuration.provider == .openRouter {
            body["reasoning"] = ["effort": effort]
        }
        if configuration.disablesThinking {
            body["thinking"] = ["type": "disabled"]
        }
        if !input.tools.isEmpty {
            body["tools"] = input.tools.map {
                [
                    "type": "function",
                    "function": [
                        "name": $0.name, "description": $0.description,
                        "parameters": $0.parameters.jsonObject
                    ]
                ]
            }
        }
        return body
    }

    /// 构造 Anthropic Messages 形态的请求体：system 段落、max_tokens 与工具定义。
    private static func anthropic(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        let systemParts =
            ([input.instructions]
            + input.messages.compactMap { $0.role == .system ? $0.text : nil })
            .compactMap { $0?.nonEmpty }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": anthropicMessages(input.messages),
            "max_tokens": input.maxOutputTokens,
            "stream": true
        ]
        if !systemParts.isEmpty { body["system"] = systemParts.joined(separator: "\n\n") }
        if !input.tools.isEmpty {
            body["tools"] = input.tools.map {
                [
                    "name": $0.name, "description": $0.description,
                    "input_schema": $0.parameters.jsonObject
                ]
            }
        }
        return body
    }

    /// 纯文本仍用字符串；只有带附件的消息才使用 content part 数组。
    private static func openAIMessage(_ message: AIMessage) -> [String: Any]? {
        if let result = message.toolResult {
            return [
                "role": "tool", "tool_call_id": result.callID, "content": result.content
            ]
        }
        let text = message.text.nonEmpty
        if !message.toolCalls.isEmpty {
            return [
                "role": message.role.rawValue,
                "content": text ?? "",
                "tool_calls": message.toolCalls.map(openAIToolCall)
            ]
        }
        let hasAttachments = !message.images.isEmpty || !message.documents.isEmpty
        guard text != nil || hasAttachments else { return nil }
        guard hasAttachments else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = []
        if let text { parts.append(["type": "text", "text": text]) }
        parts += message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
        parts += message.documents.map {
            ["type": "file", "file": ["filename": $0.name, "file_data": $0.dataURL]]
        }
        return ["role": message.role.rawValue, "content": parts]
    }

    /// 把一次工具调用编码为 OpenAI 形态，并附上 Gemini 的 thought signature。
    private static func openAIToolCall(_ call: AIToolCall) -> [String: Any] {
        var encoded: [String: Any] = [
            "id": call.id, "type": "function",
            "function": ["name": call.name, "arguments": call.arguments]
        ]
        if let signature = call.thoughtSignature {
            encoded["extra_content"] = ["google": ["thought_signature": signature]]
        }
        return encoded
    }

    /// Anthropic 要求工具结果作为 user 内容，且连续多个结果必须合并成一整轮发送。
    private static func anthropicMessages(_ messages: [AIMessage]) -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        var results: [[String: Any]] = []
        for message in messages {
            if let result = message.toolResult {
                results.append([
                    "type": "tool_result", "tool_use_id": result.callID,
                    "content": result.content, "is_error": result.isError
                ])
                continue
            }
            if !results.isEmpty {
                encoded.append(["role": "user", "content": results])
                results = []
            }
            if let value = anthropicMessage(message) { encoded.append(value) }
        }
        if !results.isEmpty { encoded.append(["role": "user", "content": results]) }
        return encoded
    }

    /// 编码单条 Anthropic 消息；system 角色由调用方另行处理，此处返回 nil。
    private static func anthropicMessage(_ message: AIMessage) -> [String: Any]? {
        guard message.role != .system else { return nil }
        let text = message.text.nonEmpty
        if !message.toolCalls.isEmpty {
            var parts: [[String: Any]] = text.map { [["type": "text", "text": $0]] } ?? []
            parts += message.toolCalls.map {
                [
                    "type": "tool_use", "id": $0.id, "name": $0.name,
                    "input": JSONValue(data: Data($0.arguments.utf8))?.jsonObject ?? [:]
                ]
            }
            return ["role": message.role.rawValue, "content": parts]
        }
        let hasAttachments = !message.images.isEmpty || !message.documents.isEmpty
        guard text != nil || hasAttachments else { return nil }
        guard hasAttachments else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = message.images.map {
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": $0.mimeType,
                    "data": $0.data.base64EncodedString()
                ]
            ]
        }
        parts += message.documents.map {
            [
                "type": "document",
                "source": [
                    "type": "base64", "media_type": $0.mimeType,
                    "data": $0.data.base64EncodedString()
                ]
            ]
        }
        // 文本放在最后：文档块必须位于引用它的指令之前。
        if let text { parts.append(["type": "text", "text": text]) }
        return ["role": message.role.rawValue, "content": parts]
    }
}

private extension String {
    /// 去掉首尾空白后为空的字符串视为 nil。
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
