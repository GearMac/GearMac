// 文件职责：描述 GearMac 可接入的已安装 CLI（种类、命令、登录方式与隔离说明），并从各 CLI 输出解析模型目录与账号信息。
// 分层：Model；纯枚举与解析函数，不做进程启动或网络请求。
import Foundation

/// GearMac 可接入的已安装 AI CLI 种类。
enum InstalledAIKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case grok
    case openCode
    case cursor

    /// Claude、Grok、OpenCode 与 Cursor —— Codex 改用其 app-server。
    static let managedCLIKinds: [InstalledAIKind] = [.claude, .grok, .openCode, .cursor]

    /// 以 rawValue 作为标识。
    var id: String { rawValue }

    /// 展示名称。
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .openCode: return "OpenCode"
        case .cursor: return "Cursor"
        }
    }

    /// 可执行命令名。
    var command: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .grok: return "grok"
        case .openCode: return "opencode"
        case .cursor: return "agent"
        }
    }

    /// 安装/文档链接。
    var installURL: URL {
        switch self {
        case .codex: return URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")!
        case .grok: return URL(string: "https://x.ai/cli")!
        case .openCode: return URL(string: "https://opencode.ai/docs")!
        case .cursor: return URL(string: "https://cursor.com/docs/cli/overview")!
        }
    }

    /// 把命令安装到定位器已搜索的公共 `bin` 之外的安装方式。
    var extraExecutablePaths: [String] {
        switch self {
        case .claude: return [".claude/local/claude"]
        case .grok: return [".grok/bin/grok"]
        case .codex, .openCode, .cursor: return []
        }
    }

    /// 对应的模型来源。
    var source: AIModelSource {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        }
    }

    /// Providers 行展示的提示：Cursor 仍使用用户的 MCP；Claude 的由托管策略掌控。
    func isolationCaveat(hasManagedMCPPolicy: Bool) -> String? {
        switch self {
        case .cursor: return "Ask mode · your Cursor MCP servers still apply"
        case .claude:
            return hasManagedMCPPolicy
                ? "MCP on this route is managed by your organization" : nil
        case .codex, .grok, .openCode: return nil
        }
    }

    /// 登录命令。
    var signInCommand: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude auth login"
        case .grok: return "grok login"
        case .openCode: return "opencode auth login"
        case .cursor: return "agent login"
        }
    }
}

extension AIModelSource {
    /// 该来源对应的已安装命令；GearMac 自行接入的两种路由返回 `nil`。
    var installedKind: InstalledAIKind? {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .grok: return .grok
        case .openCode: return .openCode
        case .cursor: return .cursor
        case .appleIntelligence, .api: return nil
        }
    }
}

/// 某个已安装 CLI 提供的一个模型选项。
struct InstalledAIModel: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let efforts: [ChatGPTSubscription.Effort]

    init(id: String, name: String, efforts: [ChatGPTSubscription.Effort] = []) {
        self.id = id
        self.name = name
        self.efforts = efforts
    }

    /// 在偏好档位无效时回退到 high，再回退到第一档；无档位则返回 `nil`。
    func resolvedEffort(_ preferred: String?) -> String? {
        guard !efforts.isEmpty else { return nil }
        if let preferred, efforts.contains(where: { $0.id == preferred }) { return preferred }
        if efforts.contains(where: { $0.id == "high" }) { return "high" }
        return efforts.first?.id
    }

    /// Claude `initialize` 控制请求的内容；其应答即 Claude 自己的 `/model` 列表。
    static let claudeInitializeRequest =
        #"{"type":"control_request","request_id":"gearmac-models","request":{"subtype":"initialize"}}"#
        + "\n"

    /// 标题生成控制请求使用的 request_id。
    static let claudeTitleRequestID = "gearmac-title"

    /// 调用 Claude Code 自带的会话命名能力，且不向其历史写入任何记录。
    static func claudeTitleRequest(_ description: String) -> String? {
        let request: [String: Any] = [
            "type": "control_request", "request_id": claudeTitleRequestID,
            "request": [
                "subtype": "generate_session_title", "description": description,
                "persist": false
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
            let line = String(bytes: data, encoding: .utf8)
        else { return nil }
        return line + "\n"
    }

    /// 从 CLI 输出中取出标题生成请求的应答标题。
    static func claudeTitle(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let response = object["response"] as? [String: Any],
                response["request_id"] as? String == claudeTitleRequestID,
                let payload = response["response"] as? [String: Any],
                let title = payload["title"] as? String
            else { continue }
            return title
        }
        return nil
    }

    /// CLI 自己的选择列表，每个解析后的模型一行：`default` 只是另一条目的重复。
    static func claudeCatalog(_ output: String) -> [InstalledAIModel] {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "control_response",
                let response = object["response"] as? [String: Any],
                let payload = response["response"] as? [String: Any],
                let entries = payload["models"] as? [[String: Any]]
            else { continue }
            var models: [InstalledAIModel] = []
            var resolved = Set<String>()
            for entry in entries {
                guard let id = entry["value"] as? String, !id.isEmpty, id != "default" else {
                    continue
                }
                let target = entry["resolvedModel"] as? String ?? id
                guard resolved.insert(target).inserted else { continue }
                models.append(
                    InstalledAIModel(
                        id: id, name: claudeName(entry, fallback: id),
                        efforts: (entry["supportedEffortLevels"] as? [String] ?? []).map {
                            ChatGPTSubscription.Effort(id: $0, detail: nil)
                        }))
            }
            return models
        }
        return []
    }

    /// 列出模型的同一应答也给出了账号信息，无需额外请求。
    static func claudeAccount(_ output: String) -> InstalledAIAccount? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "control_response",
                let response = object["response"] as? [String: Any],
                let payload = response["response"] as? [String: Any],
                let account = payload["account"] as? [String: Any]
            else { continue }
            let email = account["email"] as? String
            let plan = account["subscriptionType"] as? String
            guard email != nil || plan != nil else { return nil }
            return InstalledAIAccount(email: email, plan: plan)
        }
        return nil
    }

    /// 旧版 CLI 在 `description` 开头写版本（"Opus 5.5 · Best…"）；新版则直接给出名称。
    private static func claudeName(_ entry: [String: Any], fallback: String) -> String {
        let parts = (entry["description"] as? String ?? "").components(separatedBy: " · ")
        let versioned = parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
        let displayed = entry["displayName"] as? String ?? ""
        let name = [versioned, displayed].first { !$0.isEmpty } ?? fallback
        return name.hasPrefix("Claude") ? name : "Claude " + name
    }

    /// `/effort` 提供这四档；模型只响应自己支持的档位。
    private static let grokEfforts = ["low", "medium", "high", "xhigh"].map {
        ChatGPTSubscription.Effort(id: $0, detail: nil)
    }

    /// 解析 `grok models` 输出中的模型列表（去除 ANSI 转义序列）。
    static func grokCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var models: [InstalledAIModel] = []
        var seen = Set<String>()
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*") || line.hasPrefix("-") else { continue }
            let rest = line.drop(while: { $0 == "*" || $0 == "-" || $0.isWhitespace })
            let token = rest.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).first
            guard let token, !token.isEmpty else { continue }
            let id = String(token)
            guard seen.insert(id).inserted else { continue }
            models.append(InstalledAIModel(id: id, name: id, efforts: grokEfforts))
        }
        return models
    }

    /// CLI 未登录时 `grok models` 仍以 0 退出并打印目录。
    static func grokSignedIn(_ output: String) -> Bool {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression
        )
        .lowercased()
        return !clean.contains("not authenticated") && !clean.contains("not signed in")
    }

    /// 解析 OpenCode 输出中的模型及其变体档位。
    static func openCodeCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var entries: [(String, [String])] = []
        var id: String?
        var objectLines: [String] = []

        func appendEntry() {
            guard let id else { return }
            let data = Data(objectLines.joined(separator: "\n").utf8)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let variants = object?["variants"] as? [String: Any] ?? [:]
            entries.append((id, variants.keys.sorted(by: effortOrder)))
        }

        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw == line, line.contains("/"), !line.hasPrefix("{") {
                appendEntry()
                id = line
                objectLines = []
            } else if id != nil {
                objectLines.append(raw)
            }
        }
        appendEntry()
        return entries.map { id, efforts in
            InstalledAIModel(
                id: id, name: id,
                efforts: efforts.map { ChatGPTSubscription.Effort(id: $0, detail: nil) })
        }
    }

    /// `agent --list-models` 每行形如 `composer-2.5 - Composer 2.5`。
    static func cursorCatalog(_ output: String) -> [InstalledAIModel] {
        let clean = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        var models: [InstalledAIModel] = []
        var seen = Set<String>()
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.range(of: " - ") else { continue }
            let id = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let name = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !name.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            models.append(InstalledAIModel(id: id, name: name))
        }
        return models
    }

    /// 按固定档位顺序排序 effort 名称。
    private static func effortOrder(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        let left = order.firstIndex(of: lhs) ?? order.endIndex
        let right = order.firstIndex(of: rhs) ?? order.endIndex
        return left == right ? lhs < rhs : left < right
    }
}

/// 工具登录的账号信息（若它提供），用于让用户知道计费账户。
struct InstalledAIAccount: Equatable, Sendable {
    let email: String?
    let plan: String?

    /// CLI 有时说 "max"，有时说 "Claude Max"；该行会补上工具名称。
    var planTitle: String? {
        guard var title = plan?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            return nil
        }
        if title.lowercased().hasPrefix("claude ") { title = String(title.dropFirst(7)) }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}

/// 一次探测得到的工具状态：阶段、版本、可执行文件、模型与账号。
struct InstalledAIStatus: Equatable, Sendable {
    /// 探测阶段。
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case ready
        case signInRequired
        case notInstalled
        case failed(String)
    }

    var phase: Phase = .idle
    var version: String?
    var executable: URL?
    var models: [InstalledAIModel] = []
    var account: InstalledAIAccount?

    /// 就绪：阶段为 ready 且存在可执行文件与至少一个模型。
    var isReady: Bool { phase == .ready && executable != nil && !models.isEmpty }
}
