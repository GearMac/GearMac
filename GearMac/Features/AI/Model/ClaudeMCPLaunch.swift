// 文件职责：把 GearMac 的 MCP 服务器写成 Claude 的配置文件与启动参数，并把 `mcp__<handle>__<tool>` 名称路由回服务器调用。
// 分层：Model；仅生成配置/参数与解析名称，不启动进程。
import Foundation

/// 把 GearMac 的服务器表示为 Claude 自身的 MCP 配置：用文件承载，因为 argv 会出现在 `ps` 中。
enum ClaudeMCPLaunch {
    /// Claude 给 MCP 工具加的名称前缀。
    static let toolPrefix = "mcp__"
    /// 每轮一份，避免后一轮覆盖或删除仍在进行的轮次配置。
    static func configurationFileName(_ id: UUID = UUID()) -> String {
        "gearmac-mcp-\(id.uuidString).json"
    }
    /// 分隔 handle 与 tool 的名称分隔符。
    private static let separator = "__"

    /// 生成 `mcpServers` 配置 JSON 文本。
    static func configuration(servers: [AIToolServer]) -> String {
        var entries: [String: Any] = [:]
        for server in servers {
            switch server.transport {
            case .command(let path, let arguments, let environment):
                entries[server.handle] = [
                    "command": path, "args": arguments, "env": environment
                ]
            case .url(let url, let headerName, let headerValue):
                var entry: [String: Any] = ["type": "http", "url": url]
                if !headerValue.isEmpty { entry["headers"] = [headerName: headerValue] }
                entries[server.handle] = entry
            }
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["mcpServers": entries], options: [.sortedKeys]),
            let text = String(bytes: data, encoding: .utf8)
        else { return #"{"mcpServers":{}}"# }
        return text
    }

    /// 启用这些服务器的启动参数；`--disallowedTools *` 会连 MCP 工具一起禁掉，因此不使用。
    static func arguments(configurationPath: String, handles: [String], rounds: Int?) -> [String] {
        var result = [
            "--strict-mcp-config",
            "--mcp-config", configurationPath,
            "--permission-prompt-tool", "stdio",
            "--permission-mode", "default",
            "--settings", askSettings(handles: handles)
        ]
        // Claude 自身没有轮次上限，因此「不限」就是不传该参数。
        if let rounds { result += ["--max-turns", "\(rounds)"] }
        return result
    }

    /// ask 规则优先于用户的 allow 规则，用户的设置不会预先批准任何调用。
    static func askSettings(handles: [String]) -> String {
        let rules = handles.map { toolPrefix + $0 }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["permissions": ["ask": rules]], options: [.sortedKeys]),
            let text = String(bytes: data, encoding: .utf8)
        else { return #"{"permissions":{"ask":[]}}"# }
        return text
    }

    /// 把 `mcp__<handle>__<tool>` 还原为 GearMac 的二元组；handle 不含 `_`，tool 可以含。
    static func route(_ wireName: String) -> AIToolServerCall? {
        guard wireName.hasPrefix(toolPrefix) else { return nil }
        let rest = wireName.dropFirst(toolPrefix.count)
        guard let separator = rest.range(of: Self.separator) else { return nil }
        let handle = String(rest[..<separator.lowerBound])
        let tool = String(rest[separator.upperBound...])
        guard !handle.isEmpty, !tool.isEmpty else { return nil }
        return AIToolServerCall(handle: handle, tool: tool)
    }
}
