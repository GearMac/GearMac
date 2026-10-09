// 文件职责：AI 工具调用的数据模型：工具定义、模型发起的一次调用，以及工具执行结果。
// 分层：Model；纯值类型，不得 import AppKit/SwiftUI。
import Foundation

/// 提供给模型的工具。`parameters` 是各 provider 自己的 schema，原样透传不做改动。
struct AITool: Equatable, Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
    /// 记录行中显示的工具归属，以及工具的展示名。
    let origin: String
    let title: String

    /// 构造工具定义；`title` 缺省时退回 `name`。
    init(
        name: String, description: String, parameters: JSONValue, origin: String,
        title: String? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.origin = origin
        self.title = title ?? name
    }
}

/// 模型请求的一次调用；`arguments` 保持原始 JSON 文本，只由执行器解析。
struct AIToolCall: Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let arguments: String
    /// Gemini 3 要求回传该不透明签名，否则拒绝下一个请求。
    let thoughtSignature: String?

    /// 构造一次调用；未提供签名时为 nil。
    init(id: String, name: String, arguments: String, thoughtSignature: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.thoughtSignature = thoughtSignature
    }
}

/// 失败是模型可读且可据此恢复的内容，绝不作为抛出的错误。
struct AIToolResult: Equatable, Sendable {
    let callID: String
    let content: String
    let isError: Bool

    /// 构造一个失败结果：内容即错误信息，并标记 `isError`。
    static func failure(_ callID: String, _ message: String) -> AIToolResult {
        AIToolResult(callID: callID, content: message, isError: true)
    }
}
