// 文件职责：定义 MCP 服务器的传输方式、信任等级、持久化模型与可用的 `@slug` 句柄。
// 分层：Model；不得 import AppKit/SwiftUI，密钥只以名称引用而不保存明文。
import Foundation

/// GearMac 如何连接到服务器。这里从不保存密钥——只保存引用它们的名称。
enum MCPTransportKind: Codable, Equatable, Hashable, Sendable {
    case http(url: String, headerName: String)
    case stdio(command: String, arguments: [String], environmentKeys: [String])

    static let defaultHeaderName = "Authorization"

    /// 供界面展示的简要描述：HTTP 为 URL，stdio 为命令行。
    var summary: String {
        switch self {
        case .http(let url, _): return url
        case .stdio(let command, let arguments, _):
            return ([command] + arguments).joined(separator: " ")
        }
    }
}

/// 服务器的工具是否可运行：`.ask` 会让本轮对话的首次调用先经过对话框。
enum MCPTrust: String, CaseIterable, Codable, Identifiable, Sendable {
    case ask
    case always
    case never

    var id: String { rawValue }

    /// 界面展示的信任等级名称。
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .ask: return L10n.string(MCPKey.trustAsk, language: language)
        case .always: return L10n.string(MCPKey.trustAlways, language: language)
        case .never: return L10n.string(MCPKey.trustNever, language: language)
        }
    }
}

/// 一个已配置的 MCP 服务器：名称、传输方式、启用状态与信任等级。
struct MCPServer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var transport: MCPTransportKind
    var isEnabled: Bool
    var trust: MCPTrust
    var oauth: Bool?

    /// 创建服务器配置；默认使用空 URL 的 HTTP 传输与 `.ask` 信任。
    init(
        id: UUID = UUID(), name: String = "", slug: String = "",
        transport: MCPTransportKind = .http(
            url: "", headerName: MCPTransportKind.defaultHeaderName),
        isEnabled: Bool = true, trust: MCPTrust = .ask
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.transport = transport
        self.isEnabled = isEnabled
        self.trust = trust
    }

    /// 展示名：名称去除空白后为空时退回 slug。
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slug : trimmed
    }

    /// 交给 CLI 自行运行的形态；`bearerToken` 来自 OAuth 会话，仅借用于本轮。
    func toolServer(
        headerValue: String, environment: [String: String], bearerToken: String?
    ) -> AIToolServer? {
        switch transport {
        case .http(let url, let headerName):
            guard !url.isEmpty else { return nil }
            if let bearerToken {
                return AIToolServer(
                    handle: slug, title: title,
                    transport: .url(
                        url, headerName: MCPTransportKind.defaultHeaderName,
                        headerValue: "Bearer \(bearerToken)"))
            }
            // 未登录时，OAuth 服务器只会返回 CLI 无法解释的 401。
            guard oauth != true else { return nil }
            let name = headerName.trimmingCharacters(in: .whitespaces)
            let value = name.isEmpty ? "" : headerValue
            return AIToolServer(
                handle: slug, title: title,
                transport: .url(url, headerName: name, headerValue: value))
        case .stdio(let command, let arguments, let environmentKeys):
            guard !command.isEmpty else { return nil }
            let values = environment.filter { environmentKeys.contains($0.key) }
            return AIToolServer(
                handle: slug, title: title,
                transport: .command(path: command, arguments: arguments, environment: values))
        }
    }

    /// CLI 路由会自行启动一份本地服务器，因此这里再启动只会重复运行一次。
    func runsInGearMac(whileCLIRouteSelected cliRoute: Bool) -> Bool {
        guard cliRoute, case .stdio = transport else { return true }
        return false
    }
}

/// `@slug` 所寻址的句柄，由名称推导而来，因此无需再单独命名。
enum MCPSlug {
    static let maxLength = 24

    /// 由名称生成唯一 slug；冲突时追加序号后缀。
    static func make(from name: String, existing: Set<String>) -> String {
        let base = normalize(name)
        guard existing.contains(base) else { return base }
        // 用后缀而非直接拒绝：两个服务器确实可能想要同一个名字。
        for suffix in 2...99 {
            let candidate = "\(base.prefix(maxLength - 3))-\(suffix)"
            if !existing.contains(candidate) { return candidate }
        }
        return UUID().uuidString.prefix(8).lowercased()
    }

    /// 规范化名称：保留字母数字，用连字符连接，并截断到最大长度。
    static func normalize(_ name: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.append(character)
            } else {
                pendingSeparator = true
            }
            if slug.count >= maxLength { break }
        }
        return slug.isEmpty ? "server" : slug
    }
}
