// 文件职责：模型厂商（品牌）枚举与解析：为选择器提供品牌图标资源名，并从 provider 与 model id 推断所属品牌。
// 分层：Model；纯映射与字符串匹配，不得 import AppKit/SwiftUI。
import Foundation

/// 模型背后的厂商，用于选择器每行的图标：一个按符号方式着色的模板资源。
enum AIBrand: String, CaseIterable, Sendable {
    case openAI, claude, gemini, openRouter, x, deepSeek, qwen, mistral, meta, kimi, miniMax
    case perplexity, zai
    /// 三条本机已安装路由的标志；没有任何 model id 会被解析到它们。
    case grok, cursor, openCode

    /// 该品牌在图集（asset catalog）中的图标资源名。
    var assetName: String {
        switch self {
        case .openAI: return "AIBrandOpenAI"
        case .claude: return "AIBrandClaude"
        case .gemini: return "AIBrandGemini"
        case .openRouter: return "AIBrandOpenRouter"
        case .x: return "AIBrandX"
        case .deepSeek: return "AIBrandDeepSeek"
        case .qwen: return "AIBrandQwen"
        case .mistral: return "AIBrandMistral"
        case .meta: return "AIBrandMeta"
        case .kimi: return "AIBrandKimi"
        case .miniMax: return "AIBrandMiniMax"
        case .perplexity: return "AIBrandPerplexity"
        case .zai: return "AIBrandZAI"
        case .grok: return "AIBrandGrok"
        case .cursor: return "AIBrandCursor"
        case .openCode: return "AIBrandOpenCode"
        }
    }

    /// 先命中者优先：路由器 id 的 `vendor/` 前缀，或裸 id 中的模型家族名。
    private static let needles: [(AIBrand, [String])] = [
        (.claude, ["anthropic", "claude"]),
        (.openAI, ["openai", "gpt", "chatgpt", "codex"]),
        (.gemini, ["google", "gemini", "gemma"]),
        (.x, ["x-ai", "xai", "grok"]),
        (.deepSeek, ["deepseek"]),
        (.qwen, ["qwen", "qwq", "alibaba"]),
        (.mistral, ["mistral", "mixtral", "codestral", "magistral", "devstral", "ministral"]),
        (.meta, ["meta-llama", "meta/", "llama"]),
        (.kimi, ["moonshot", "kimi"]),
        (.miniMax, ["minimax"]),
        (.perplexity, ["perplexity", "sonar"]),
        (.zai, ["z-ai", "zai", "zhipu", "glm"]),
        (.openRouter, ["openrouter"])
    ]

    /// 厂商自己的端点直接决定品牌；聚合型服务只能靠 model id 判断。
    static func resolve(provider: AIProviderKind, model: String) -> AIBrand? {
        switch provider {
        case .openAI: return .openAI
        case .anthropic: return .claude
        case .gemini: return .gemini
        case .openRouter, .openAICompatible: return resolve(model: model)
        }
    }

    /// 仅凭 model id 推断品牌：先按关键字表命中，再识别 o 系列家族名。
    static func resolve(model: String) -> AIBrand? {
        let id = model.lowercased()
        if let hit = needles.first(where: { _, hits in hits.contains { id.contains($0) } }) {
            return hit.0
        }
        // o 系列（`o3`、`o4-mini`、`openai/o1`）的名字太短，不适合作为子串检索。
        let family = id.split(separator: "/").last ?? Substring(id)
        return family.wholeMatch(of: #/o[134](-.*)?/#) != nil ? .openAI : nil
    }
}
