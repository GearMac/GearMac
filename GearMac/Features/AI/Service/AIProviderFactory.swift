// 文件职责：按所选 AI 路由（本地 Apple Intelligence、各类已安装 CLI、或 BYOK API 连接）构造对应的提供方实例。
// 分层：Service；在构造时集中校验路由开关、安装状态、端点与密钥，失败统一抛 `AIProviderError`。
import Foundation

/// 提供方工厂：把 `AIModelSelection` 收敛为一个可直接使用的 `AIProvider`。
@MainActor
enum AIProviderFactory {
    /// `guardrails` 仅传达给本地模型，因为它是唯一在本地做内容过滤的路由。
    static func make(
        selection: AIModelSelection,
        settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager,
        installedAI: InstalledAIManager,
        keyStore: KeychainSecretStore = .aiAPIKeys,
        guardrails: AppleIntelligenceGuardrails = .default,
        toolServers: AIToolServerSession? = nil
    ) throws -> any AIProvider {
        switch selection {
        case .appleIntelligence:
            guard settings.isRouteEnabled(.appleIntelligence) else {
                throw AIProviderError.unavailable("Apple Intelligence is disabled in AI Settings.")
            }
            if let message = AppleIntelligenceProvider.status().message {
                throw AIProviderError.unavailable(message)
            }
            return AppleIntelligenceProvider(guardrails: guardrails)
        case .codex(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.codex) else {
                throw AIProviderError.unavailable("Codex is disabled in AI Settings.")
            }
            return CodexInstalledProvider(
                turns: subscription.turns, model: model, effort: effort,
                toolServers: toolServers)
        case .claude(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.claude) else {
                throw AIProviderError.unavailable("Claude is disabled in AI Settings.")
            }
            return try installedAI.provider(
                kind: .claude, model: model, effort: effort, toolServers: toolServers)
        case .grok(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.grok) else {
                throw AIProviderError.unavailable("Grok is disabled in AI Settings.")
            }
            return try installedAI.provider(kind: .grok, model: model, effort: effort)
        case .openCode(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.openCode) else {
                throw AIProviderError.unavailable("OpenCode is disabled in AI Settings.")
            }
            return try installedAI.provider(kind: .openCode, model: model, effort: effort)
        case .cursor(let model, let effort):
            guard settings.enabledInstalledProviders.contains(.cursor) else {
                throw AIProviderError.unavailable("Cursor is disabled in AI Settings.")
            }
            return try installedAI.provider(kind: .cursor, model: model, effort: effort)
        case .api(let connectionID, let model, let effort):
            guard let connection = settings.connection(id: connectionID) else {
                throw AIProviderError.unavailable("Choose an API connection in Settings.")
            }
            guard settings.isRouteEnabled(.api(connectionID)) else {
                throw AIProviderError.unavailable("\(connection.title) is disabled in AI Settings.")
            }
            let baseURL: URL
            do {
                baseURL = try AIEndpointPolicy.validate(connection.baseURL)
            } catch let error as AIEndpointPolicy.ValidationError {
                throw AIProviderError.unavailable(error.localizedDescription)
            }
            let key: String
            do {
                key = try keyStore.secret(for: connection.id) ?? ""
            } catch {
                throw AIProviderError.unavailable("The API key could not be read from Keychain.")
            }
            guard AIEndpointPolicy.isLoopback(connection.baseURL) || !key.isEmpty else {
                throw AIProviderError.unavailable("Add an API key in Settings.")
            }
            // 模型即路由：Decisions 模型的请求走 /decisions，而不是 /chat/completions。
            if DecisionsRouting.isDecisionsModel(model) {
                let endpoint =
                    (try? AIEndpointPolicy.validate(
                        DecisionsRouting.normalizeBase(connection.baseURL))) ?? baseURL
                return DecisionsChatProvider(
                    client: DecisionsClient(endpoint: endpoint, model: model, apiKey: key),
                    questions: settings.decisionsQuestions)
            }
            return HTTPAIProvider(
                configuration: AIHTTPConfiguration(
                    provider: connection.provider, baseURL: baseURL, model: model, effort: effort,
                    disablesThinking: effort == AIConnection.ReasoningOptions.noEffort
                        && connection.takesThinkingField),
                apiKey: key)
        }
    }
}
