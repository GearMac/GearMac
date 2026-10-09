// 文件职责：AI 请求侧的数据模型：图片/文档附件、附件预算、消息与请求、用量统计，以及流式事件与错误定义。
// 分层：Model；纯值类型与预算计算，不得 import AppKit/SwiftUI。
import Foundation

/// 已按传输格式编码的图片附件；所有 provider 都以 data URL 形式接收。
struct AIImage: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// 由路由原生读取的文件；文本类文件不会走这里，而是以内联文本形式发送。
struct AIDocument: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String
    /// 与图片不同，该名称会随请求发送：同时收到三个 PDF 的模型需要能区分它们。
    let name: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// 请求体积上限约为 25 MB，data URL 还会再增加约三分之一体积，因此该上限在此处定义。
enum AIAttachmentBudget {
    static let maxCount = 6
    static let maxBytes = 10 * 1_048_576
    /// 内联文本随最新一轮发送且不会被裁剪，因此在入队前就限制其大小。
    static let maxInlinedTextBytes = 32 * 1_024

    /// 数量与体积合并计算：若各自独立设限，将允许图片与文档各六个同时通过。
    static func admits(images: [AIImage], documents: [AIDocument], addingBytes bytes: Int) -> Bool {
        let used =
            images.reduce(0) { $0 + $1.data.count }
            + documents.reduce(0) { $0 + $1.data.count }
        return images.count + documents.count < maxCount && used + bytes <= maxBytes
    }

    /// 保留能放下的最长前缀，用于非输入区构造的轮次。
    /// 图片优先占用额度，因此不会因为排在后面的文档而丢弃图片。
    static func bounded(
        _ images: [AIImage], _ documents: [AIDocument]
    )
        -> (images: [AIImage], documents: [AIDocument])
    {
        var total = 0
        var count = 0
        let keptImages = images.prefix { image in
            guard count < maxCount, total + image.data.count <= maxBytes else { return false }
            total += image.data.count
            count += 1
            return true
        }
        let keptDocuments = documents.prefix { document in
            guard count < maxCount, total + document.data.count <= maxBytes else { return false }
            total += document.data.count
            count += 1
            return true
        }
        return (Array(keptImages), Array(keptDocuments))
    }
}

/// 发送给 provider 的一条消息。
struct AIMessage: Equatable, Sendable {
    /// 消息角色。
    enum Role: String, Equatable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let text: String
    let images: [AIImage]
    /// 只有 PDF 会出现在这里：文本类文件在任何传输之前就已内联进 `text`。
    let documents: [AIDocument]
    /// 仅 assistant 角色：本轮请求的工具调用，以及随调用一起出现的文本。
    let toolCalls: [AIToolCall]
    /// 仅 tool 角色：对其中的一次调用的回复。
    let toolResult: AIToolResult?

    /// 构造消息；未提供的附件与工具字段为空。
    init(
        role: Role, text: String, images: [AIImage] = [], documents: [AIDocument] = [],
        toolCalls: [AIToolCall] = [], toolResult: AIToolResult? = nil
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.documents = documents
        self.toolCalls = toolCalls
        self.toolResult = toolResult
    }
}

/// 一次发往 provider 的完整请求。
struct AIRequest: Equatable, Sendable {
    let conversationID: UUID?
    let instructions: String?
    let messages: [AIMessage]
    let maxOutputTokens: Int
    /// 是否允许模型联网搜索；各路由有各自的开关，默认全部关闭。
    let webSearch: Bool
    /// 无法调用工具的路由此处为空，传输层无需再判断是否有权调用。
    let tools: [AITool]

    /// 构造请求；默认不联网、不带工具，输出上限为 4096。
    init(
        instructions: String? = nil, messages: [AIMessage], maxOutputTokens: Int = 4_096,
        webSearch: Bool = false, tools: [AITool] = [], conversationID: UUID? = nil
    ) {
        self.conversationID = conversationID
        self.instructions = instructions
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.webSearch = webSearch
        self.tools = tools
    }

    /// 把同一轮继续下去，并带上外层循环可调用的工具。
    func continuing(with messages: [AIMessage], tools: [AITool]) -> AIRequest {
        AIRequest(
            instructions: instructions, messages: messages, maxOutputTokens: maxOutputTokens,
            webSearch: webSearch, tools: tools, conversationID: conversationID)
    }
}

/// 一次回复的用量统计。
struct AIUsage: Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    /// 命中或写入缓存的 prompt token；Anthropic 不计入 `inputTokens`。
    var cachedInputTokens: Int?
    /// `outputTokens` 中用于思考的部分。
    var reasoningTokens: Int?
    /// 模型的总上下文窗口，仅在路由上报时存在；目前只有 Claude CLI 会上报。
    var contextWindow: Int?
    var costUSD: Double?

    /// 输入与输出 token 之和；任一缺失则为 nil。
    var totalTokens: Int? {
        guard let inputTokens, let outputTokens else { return nil }
        return inputTokens + outputTokens
    }

    /// 当前对话占用的窗口量：全部 prompt token 加上回复本身。
    var contextTokens: Int? {
        totalTokens.map { $0 + (cachedInputTokens ?? 0) }
    }
}

/// 流式输出过程中产生的事件。
enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case thinking
    /// 路由愿意共享的思考文本；绝不是正文，也不会作为上下文回传。
    case reasoning(String)
    case searching(String?)
    case searched(String?)
    /// 传输层发出的事件；由工具循环消费，绝不直接传给转写视图。
    case toolCallRequested(AIToolCall)
    /// 工具循环代替其发出的事件，已带上记录行需要展示的信息。
    case toolCall(id: String, origin: String, title: String)
    case toolResult(id: String, isError: Bool)
    case usage(AIUsage)
    case finished
}

/// provider 侧的错误；`errorDescription` 直接用于展示。
enum AIProviderError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case responseFailed(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .responseFailed(let message): return message
        case .malformedResponse: return "The provider returned malformed streaming data."
        }
    }
}
