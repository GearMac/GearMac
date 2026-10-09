// 文件职责：AI 连接与模型路由的核心模型：provider 种类、连接配置、模型能力、模型来源与选择、HTTP 端点配置以及端点校验策略。
// 分层：Model；纯数据、映射与校验，不得 import AppKit/SwiftUI。
import Foundation

/// GearMac 支持的 API provider 种类。
enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case anthropic
    case gemini
    case openRouter
    case openAICompatible

    var id: String { rawValue }

    /// 设置界面中的 provider 名称。
    var title: String {
        switch self {
        case .openAI: return "OpenAI API"
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .openAICompatible: return "OpenAI Compatible"
        }
    }

    /// 该 provider 的默认 base URL。
    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAICompatible: return "https://api.openai.com/v1"
        }
    }

    /// 该 provider 的请求体/响应所遵循的 API 形态。
    var apiShape: AIHTTPConfiguration.APIShape {
        self == .anthropic ? .anthropic : .openAICompatible
    }
}

/// 一个 API provider 连接的配置：名称、provider、base URL、模型列表与推理选项。
struct AIConnection: Codable, Equatable, Identifiable, Sendable {
    /// 某模型可选的推理强度配置。
    struct ReasoningOptions: Codable, Equatable, Sendable {
        static let noEffort = "none"

        let efforts: [String]
        let defaultEffort: String?

        /// 采用 OpenRouter 自己的命名；那里的 `none` 同样表示完全关闭推理。
        static let thinkingSwitch = ReasoningOptions(
            efforts: ["default", "none"], defaultEffort: "default")

        /// 解析实际使用的推理强度：优先传入值，其次默认值，最后取第一个可选值。
        func resolvedEffort(_ preferred: String?) -> String? {
            guard !efforts.isEmpty else { return nil }
            if let preferred, efforts.contains(preferred) { return preferred }
            if let defaultEffort, efforts.contains(defaultEffort) { return defaultEffort }
            return efforts.first
        }
    }

    let id: UUID
    var name: String
    var provider: AIProviderKind
    var baseURL: String
    var models: [String]
    /// 目录中标记为支持图片输入的模型；只有 OpenRouter 的目录会声明，因此也只有它受此限制。
    var visionModels: [String]
    /// OpenRouter 按模型提供的目录元数据；不发布该契约的 API 为 nil。
    var reasoningOptions: [String: ReasoningOptions]?

    /// 构造连接；`baseURL` 为 nil 时取 provider 的默认地址。
    init(
        id: UUID = UUID(), name: String = "", provider: AIProviderKind = .openAI,
        baseURL: String? = nil, models: [String] = [], visionModels: [String] = [],
        reasoningOptions: [String: ReasoningOptions]? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.models = models
        self.visionModels = visionModels
        self.reasoningOptions = reasoningOptions
    }

    /// 预设被指向非自家 API 的地址即为网关，而只有网关接受 thinking 字段。
    var takesThinkingField: Bool {
        provider.apiShape == .openAICompatible
            && baseURL.trimmingCharacters(in: .whitespacesAndNewlines) != provider.defaultBaseURL
    }

    /// 网关不发布目录，因此唯一确定支持的强度取值就是关闭开关。
    func reasoningOptions(for model: String) -> ReasoningOptions? {
        reasoningOptions?[model] ?? (takesThinkingField ? .thinkingSwitch : nil)
    }

    /// 连接的显示名；为空时退回 provider 名称。
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.title : trimmed
    }

    /// 该连接下某模型支持的能力集。
    func capabilities(for model: String) -> AIModelCapabilities {
        AIModelCapabilities(
            images: provider != .openRouter || visionModels.contains(model),
            // 只有这两种形态的请求体由 GearMac 自己书写；网关会先对上传计费。
            documents: provider == .openAI || provider == .anthropic,
            webSearch: provider == .openRouter, tools: true)
    }
}

/// 选择器可为某模型提供的能力：厂商 API 默认接受图片，除非其目录明确否定。
struct AIModelCapabilities: Equatable, Sendable {
    let images: Bool
    /// 是否支持把 PDF 作为原生块发送；有四条路由没有对应字段，因此直接拒绝而不是静默丢弃。
    let documents: Bool
    let webSearch: Bool
    /// 除端侧路由和三个没有自带 MCP 开关的 CLI 之外的所有路由。
    let tools: Bool

    static let none = AIModelCapabilities(
        images: false, documents: false, webSearch: false, tools: false)
    static let chatGPT = AIModelCapabilities(
        images: true, documents: false, webSearch: true, tools: false)
    static let codex = AIModelCapabilities(
        images: true, documents: false, webSearch: true, tools: true)
    /// 图片随其 stream-json 输入传入；它自己的客户端负责运行 GearMac 的 MCP 服务器。
    static let claudeCommand = AIModelCapabilities(
        images: true, documents: false, webSearch: false, tools: true)
    /// 端侧模型仅支持文本且不访问外部，因此三项能力都不具备。
    static let appleIntelligence = AIModelCapabilities.none
}

/// 模型的来源路由：端侧、各 CLI 或某个 API 连接。
enum AIModelSource: Codable, Equatable, Hashable, Sendable {
    case appleIntelligence
    case codex
    case claude
    case grok
    case openCode
    case cursor
    case api(UUID)
}

extension AIModelSource {
    /// 供按路由为键的设置使用的稳定名称；连接本身只能通过 id 识别。
    var storageKey: String {
        switch self {
        case .appleIntelligence: return "appleIntelligence"
        case .codex: return "codex"
        case .claude: return "claude"
        case .grok: return "grok"
        case .openCode: return "openCode"
        case .cursor: return "cursor"
        case .api(let id): return "api:" + id.uuidString
        }
    }
}

/// 用户选定的模型来源与具体模型，含可选的推理强度。
enum AIModelSelection: Codable, Equatable, Hashable, Sendable {
    case appleIntelligence
    case codex(model: String, effort: String?)
    case claude(model: String, effort: String?)
    case grok(model: String, effort: String?)
    case openCode(model: String, effort: String?)
    case cursor(model: String, effort: String?)
    case api(connection: UUID, model: String, effort: String?)

    /// 由自带客户端充当 MCP 客户端的路由：它们接收服务器列表，而不使用 GearMac 的工具循环。
    var runsItsOwnTools: Bool {
        switch self {
        case .codex, .claude: return true
        case .appleIntelligence, .grok, .openCode, .cursor, .api: return false
        }
    }

    /// 选中模型是否为 Decisions 模型；是则请求走 `/decisions`，回答是结构化判定而非对话。
    var isDecisionsModel: Bool {
        DecisionsRouting.isDecisionsModel(model)
    }

    /// 对应的来源路由。
    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .codex: return .codex
        case .claude: return .claude
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        case .api(let connection, _, _): return .api(connection)
        }
    }

    /// 选中的模型 id。
    var model: String {
        switch self {
        case .appleIntelligence: return AppleIntelligence.modelID
        case .codex(let model, _), .claude(let model, _), .grok(let model, _),
            .openCode(let model, _), .cursor(let model, _), .api(_, let model, _):
            return model
        }
    }

    /// 选中的推理强度；端侧路由为 nil。
    var effort: String? {
        switch self {
        case .codex(_, let effort), .claude(_, let effort), .grok(_, let effort),
            .openCode(_, let effort), .cursor(_, let effort), .api(_, _, let effort):
            return effort
        case .appleIntelligence:
            return nil
        }
    }

    /// 返回同一条选择、换用新推理强度的副本；端侧路由保持不变。
    func withEffort(_ effort: String?) -> AIModelSelection {
        switch self {
        case .codex(let model, _): return .codex(model: model, effort: effort)
        case .claude(let model, _): return .claude(model: model, effort: effort)
        case .grok(let model, _): return .grok(model: model, effort: effort)
        case .openCode(let model, _): return .openCode(model: model, effort: effort)
        case .cursor(let model, _): return .cursor(model: model, effort: effort)
        case .api(let connection, let model, _):
            return .api(connection: connection, model: model, effort: effort)
        case .appleIntelligence: return self
        }
    }

    /// 唯一无需计费也无需配置的路由，因此不需要能力开关限制。
    var isOnDevice: Bool { self == .appleIntelligence }

    private enum CodingKeys: String, CodingKey {
        case appleIntelligence
        case codex
        case chatGPT
        case claude
        case grok
        case openCode
        case cursor
        case api
    }

    private enum ValueKeys: String, CodingKey {
        case model
        case effort
        case connection
    }

    /// 兼容旧字段名（`chatGPT` 即现在的 `codex`）的自定义解码。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.appleIntelligence) {
            self = .appleIntelligence
            return
        }
        if container.contains(.codex) || container.contains(.chatGPT) {
            let key: CodingKeys = container.contains(.codex) ? .codex : .chatGPT
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: key)
            self = .codex(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        if container.contains(.claude) {
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .claude)
            self = .claude(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        if container.contains(.grok) {
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .grok)
            self = .grok(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        if container.contains(.openCode) {
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .openCode)
            self = .openCode(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        if container.contains(.cursor) {
            let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .cursor)
            self = .cursor(
                model: try value.decode(String.self, forKey: .model),
                effort: try value.decodeIfPresent(String.self, forKey: .effort))
            return
        }
        let value = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: .api)
        self = .api(
            connection: try value.decode(UUID.self, forKey: .connection),
            model: try value.decode(String.self, forKey: .model),
            effort: try value.decodeIfPresent(String.self, forKey: .effort))
    }

    /// 写回与解码对应的紧凑编码形式。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appleIntelligence:
            _ = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .appleIntelligence)
        case .codex(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .codex)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .claude(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .claude)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .grok(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .grok)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .openCode(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .openCode)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .cursor(let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .cursor)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        case .api(let connection, let model, let effort):
            var value = container.nestedContainer(keyedBy: ValueKeys.self, forKey: .api)
            try value.encode(connection, forKey: .connection)
            try value.encode(model, forKey: .model)
            try value.encodeIfPresent(effort, forKey: .effort)
        }
    }
}

/// 一次 HTTP 请求所需的 provider、base URL、模型与推理配置。
struct AIHTTPConfiguration: Equatable, Sendable {
    /// 两种请求体形态：OpenAI 兼容与 Anthropic Messages。
    enum APIShape: String, Sendable {
        case openAICompatible
        case anthropic
    }

    let provider: AIProviderKind
    let baseURL: URL
    let model: String
    let effort: String?
    let disablesThinking: Bool

    /// 构造请求配置；默认不指定推理强度，也不关闭思考。
    init(
        provider: AIProviderKind, baseURL: URL, model: String, effort: String? = nil,
        disablesThinking: Bool = false
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.effort = effort
        self.disablesThinking = disablesThinking
    }

    /// 请求体/响应所遵循的 API 形态。
    var shape: APIShape { provider.apiShape }

    /// 实际请求地址：在 base URL 上补齐 chat/completions 或 v1/messages 路径。
    var endpointURL: URL {
        switch shape {
        case .openAICompatible:
            if baseURL.path.hasSuffix("/chat/completions") { return baseURL }
            return baseURL.appending(path: "chat/completions")
        case .anthropic:
            if baseURL.path.hasSuffix("/messages") { return baseURL }
            return baseURL.appending(path: "v1/messages")
        }
    }
}

/// base URL 校验与端点同一性判定策略。
enum AIEndpointPolicy {
    /// 校验失败的原因；`errorDescription` 直接作为界面文案展示。
    enum ValidationError: LocalizedError, Equatable {
        case invalidURL
        case insecureRemoteURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter a valid provider base URL."
            case .insecureRemoteURL: return "Remote AI providers require an HTTPS base URL."
            }
        }
    }

    /// 校验并规范化用户输入的 base URL；scheme 非 http(s) 或远程地址非 HTTPS 时抛错。
    static func validate(_ value: String) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // 只接受传输层支持的两种 scheme：`ftp://localhost` 曾经也被视为合法 provider。
        guard let url = URL(string: value), let host = url.host(),
            url.scheme == "https" || url.scheme == "http"
        else {
            throw ValidationError.invalidURL
        }
        guard url.scheme == "https" || isLoopback(host: host) else {
            throw ValidationError.insecureRemoteURL
        }
        return url
    }

    /// 密钥是针对某个端点签发的，因此 provider 或 base URL 变化后旧密钥不再随行。
    static func sameDestination(_ connection: AIConnection, _ other: AIConnection) -> Bool {
        connection.provider == other.provider && connection.baseURL == other.baseURL
    }

    /// 判断某个 URL 字符串是否指向本机回环地址。
    static func isLoopback(_ value: String) -> Bool {
        guard let host = URL(string: value)?.host() else { return false }
        return isLoopback(host: host)
    }

    /// 主机名是否为回环地址（localhost、127.0.0.1、::1）。
    private static func isLoopback(host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }
}
