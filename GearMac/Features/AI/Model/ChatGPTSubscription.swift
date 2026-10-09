// 文件职责：ChatGPT 订阅（Codex 路由）的账号、套餐、访问方式、推理强度、模型与用量限额模型。
// 分层：Model；纯数据结构，不得 import AppKit/SwiftUI。
import Foundation

/// ChatGPT 订阅相关数据的命名空间。
enum ChatGPTSubscription {
    /// 订阅连接当前所处的阶段。
    enum Phase: Equatable, Sendable {
        case idle
        case starting
        case signedOut
        case connected
        case unavailable(String)
        case failed(String)

        /// 是否处于不可用状态。
        var isUnavailable: Bool {
            if case .unavailable = self { return true }
            return false
        }
    }

    /// 已登录的 ChatGPT 账号信息。
    struct Account: Equatable, Sendable {
        let email: String?
        let plan: String

        /// 套餐代码对应的展示名称。
        var planTitle: String {
            switch plan {
            case "free": return "Free"
            case "go": return "Go"
            case "plus": return "Plus"
            case "pro": return "Pro 20x"
            case "prolite": return "Pro 5x"
            case "team": return "Team"
            case "self_serve_business_prolite", "self_serve_business_usage_based", "business":
                return "Business"
            case "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "enterprise":
                return "Enterprise"
            case "edu", "edu_plus", "edu_pro": return "Edu"
            case "apiKey", "api_key": return "API key"
            default: return "Account"
            }
        }
    }

    /// `account/read` 确认的本次请求可用的访问方式。
    enum Access: Equatable, Sendable {
        case account(Account)
        /// 自定义 provider 自带密钥，因此 Codex 不上报账号，也不需要账号。
        case provider
    }

    /// 一种可选的推理强度。
    struct Effort: Equatable, Identifiable, Sendable {
        let id: String
        let detail: String?

        /// 推理强度的展示名称。
        var title: String {
            switch id {
            case "xhigh": return "Extra high"
            case "minimal": return "Minimal"
            default: return id.prefix(1).uppercased() + id.dropFirst()
            }
        }
    }

    /// 订阅下可用的模型及其推理强度选项。
    struct Model: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let efforts: [Effort]
        let defaultEffort: String?
        let isDefault: Bool

        /// 解析最终使用的推理强度：优先调用方指定的值，其次模型默认值，最后取第一个可选值。
        func resolvedEffort(_ preferred: String?) -> String? {
            guard !efforts.isEmpty else { return nil }
            if let preferred, efforts.contains(where: { $0.id == preferred }) { return preferred }
            if let defaultEffort, efforts.contains(where: { $0.id == defaultEffort }) {
                return defaultEffort
            }
            return efforts.first?.id
        }
    }

    /// 一个用量窗口的已用比例与重置信息。
    struct UsageWindow: Equatable, Sendable {
        let usedPercent: Int
        let durationMinutes: Int?
        let resetsAt: Date?

        /// 剩余百分比，夹在 0…100 之间。
        var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
    }

    /// 主、次两个用量窗口。
    struct RateLimits: Equatable, Sendable {
        let primary: UsageWindow?
        let secondary: UsageWindow?
    }
}
