// 文件职责：把 GearMac 的 MCP 服务器展开为 `codex app-server` 的 `-c` 覆盖参数与环境变量，并解析 Codex 的授权询问。
// 分层：Model；只生成参数/环境对，不写入用户的 `~/.codex`。
import Foundation

/// 把 GearMac 的服务器表示为 `codex app-server` 的启动覆盖；不会写入 `~/.codex`。
enum CodexMCPLaunch {
    /// Codex 中 GearMac 服务器的名称；`-c` 会合并进用户同名的表。
    static func serverName(for handle: String) -> String { serverPrefix + handle }

    /// 从 Codex 报告的名称还原 handle；非 GearMac 的服务器返回 `nil`。
    static func handle(ofServer name: String) -> String? {
        guard name.hasPrefix(serverPrefix), name.count > serverPrefix.count else { return nil }
        return String(name.dropFirst(serverPrefix.count))
    }

    /// GearMac 服务器名称的统一前缀。
    private static let serverPrefix = "gearmac-"

    /// `codex mcp list --json` 报告的名称列表；输出不是该列表时返回 `nil`。
    static func foreignNames(listing: String) -> [String]? {
        guard let entries = JSONValue(data: Data(listing.utf8))?.arrayValue else { return nil }
        var names: [String] = []
        for entry in entries {
            guard let name = entry.objectValue?["name"]?.stringValue else { return nil }
            names.append(name)
        }
        return names
    }

    /// 用户某个无法用 `-c` 关闭的服务器：名称中的点或 `=` 会拆散它以之命名的键。
    static func unaddressableName(_ foreignNames: [String]) -> String? {
        foreignNames.first { $0.contains(".") || $0.contains("=") }
    }

    /// 用户已存在与我们某个启用服务器同名的服务器，会被合并进去。
    static func takenName(servers: [AIToolServer], foreignNames: [String]) -> String? {
        servers.map { serverName(for: $0.handle) }.first { foreignNames.contains($0) }
    }

    /// GearMac 服务器的 `-c` 键值对，以及按名称禁用用户自有服务器的参数。
    static func arguments(servers: [AIToolServer], disabling foreignNames: [String]) -> [String] {
        var arguments: [String] = []
        for name in foreignNames {
            arguments += ["-c", "mcp_servers.\(name).enabled=false"]
        }
        for (index, server) in servers.enumerated() {
            let key = "mcp_servers.\(serverName(for: server.handle))"
            arguments += ["-c", "\(key).enabled=true"]
            // Codex 对服务器标记为只读的工具不会询问；是否信任由 GearMac 决定。
            arguments += ["-c", "\(key).default_tools_approval_mode=\(quoted("prompt"))"]
            switch server.transport {
            case .command(let path, let commandArguments, let environment):
                let launch = command(
                    path: path, arguments: commandArguments, environment: environment,
                    server: index)
                arguments += ["-c", "\(key).command=\(quoted(launch.path))"]
                arguments += ["-c", "\(key).args=\(array(launch.arguments))"]
                let names = forwardedNames(environment).indices.map {
                    variable(server: index, key: $0)
                }
                arguments += ["-c", "\(key).env_vars=\(array(names))"]
            case .url(let url, let headerName, let headerValue):
                arguments += ["-c", "\(key).url=\(quoted(url))"]
                guard !headerValue.isEmpty else { continue }
                let name = variable(server: index, key: 0)
                if bearerToken(headerName: headerName, headerValue: headerValue) != nil {
                    arguments += ["-c", "\(key).bearer_token_env_var=\(quoted(name))"]
                } else {
                    arguments += [
                        "-c", "\(key).env_http_headers={\(quoted(headerName))=\(quoted(name))}"
                    ]
                }
            }
        }
        return arguments
    }

    /// 覆盖参数引用的取值，通过环境变量传递；若两个服务器会共用同一变量则返回 `nil` 拒绝启动。
    static func environment(servers: [AIToolServer]) -> [String: String]? {
        var pairs: [(name: String, value: String)] = []
        for (index, server) in servers.enumerated() {
            switch server.transport {
            case .command(_, _, let environment):
                for (key, name) in forwardedNames(environment).enumerated() {
                    pairs.append((variable(server: index, key: key), environment[name] ?? ""))
                }
            case .url(_, let headerName, let headerValue):
                guard !headerValue.isEmpty else { continue }
                let value = bearerToken(headerName: headerName, headerValue: headerValue)
                pairs.append((variable(server: index, key: 0), value ?? headerValue))
            }
        }
        return distinct(pairs)
    }

    /// 每个变量对应一个值，否则返回 `nil`：重名会把一台服务器的密钥交给另一台。
    static func distinct(_ pairs: [(name: String, value: String)]) -> [String: String]? {
        var result: [String: String] = [:]
        for pair in pairs {
            guard result.updateValue(pair.value, forKey: pair.name) == nil else { return nil }
        }
        return result
    }

    /// Codex 无法重命名转发的环境变量，因此用 `/bin/sh` 把每个变量改名为对应服务器的名字。
    static func command(
        path: String, arguments: [String], environment: [String: String], server index: Int
    ) -> (path: String, arguments: [String]) {
        let names = forwardedNames(environment)
        guard !names.isEmpty else { return (path, arguments) }
        let derived = names.indices.map { variable(server: index, key: $0) }
        // 先全部读取再导出：服务器自身的变量名可能与派生的名字相同。
        let capture = "set -- " + derived.map { "\"$\($0)\"" }.joined(separator: " ") + #" "$@""#
        let exports = names.enumerated().map { key, name in "export \(name)=\"${\(key + 1)}\"" }
        let script =
            ([capture, "unset " + derived.joined(separator: " ")] + exports
            + ["shift \(names.count)", #"exec "$@""#]).joined(separator: "; ")
        return ("/bin/sh", ["-c", script, "gearmac-mcp", path] + arguments)
    }

    /// 只有 `export` 接受的变量名才能传给服务器；其余一律不转发。
    private static func forwardedNames(_ environment: [String: String]) -> [String] {
        environment.keys.sorted().filter(isShellName)
    }

    /// 判断变量名是否是合法的 shell 标识符。
    private static func isShellName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else {
            return false
        }
        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// 用位置而非 handle/key 拼写来命名，避免两台服务器的拼写冲突。
    static func variable(server: Int, key: Int) -> String {
        "TC_MCP_\(server)_\(key)"
    }

    /// Codex 会自行拼出 `Bearer`，因此变量里只放裸 token。
    private static func bearerToken(headerName: String, headerValue: String) -> String? {
        guard headerName.caseInsensitiveCompare("Authorization") == .orderedSame,
            headerValue.count > 7,
            headerValue.prefix(7).caseInsensitiveCompare("Bearer ") == .orderedSame
        else { return nil }
        return String(headerValue.dropFirst(7))
    }

    /// 把字符串数组编码为 TOML 数组字面量。
    private static func array(_ values: [String]) -> String {
        "[" + values.map(quoted).joined(separator: ",") + "]"
    }

    /// TOML 基本字符串，按 Unicode 标量转义：CRLF 在 `Character` 层面只是一个字符，会漏过检查。
    static func quoted(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                let hex = String(scalar.value, radix: 16, uppercase: true)
                escaped += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"" + escaped + "\""
    }
}

/// GearMac 唯一会应答的服务器请求：某个 MCP 工具调用是否可执行；其余一律拒绝。
struct CodexElicitation: Equatable, Sendable {
    /// 应答内容。从不发送 `persist`：只有设置才能改变长期生效的决定。
    enum Action: String, Sendable {
        case accept
        case decline
    }

    let serverName: String
    /// 发起询问的线程，使应答来自做出该调用的会话轮次。
    let threadID: String?
    let toolName: String
    /// Codex 发送时的 `_meta.tool_name`：唯一与该次调用绑定、而非最新调用的名称。
    let namedTool: String?

    /// 对其它所有 elicitation（表单、采样请求等）返回 `nil`，保持拒绝。
    init?(params: [String: JSONValue]) {
        guard let serverName = params["serverName"]?.stringValue, !serverName.isEmpty else {
            return nil
        }
        let meta = params["_meta"]?.objectValue ?? [:]
        guard meta["codex_approval_kind"]?.stringValue == "mcp_tool_call" else { return nil }
        self.serverName = serverName
        threadID = params["threadId"]?.stringValue
        namedTool = meta["tool_name"]?.stringValue
        toolName =
            namedTool ?? meta["tool_title"]?.stringValue
            ?? Self.quotedName(in: params["message"]?.stringValue ?? "") ?? "a tool"
    }

    /// 消息用引号指出了工具名；当 `_meta` 未携带任何名称时作为最后手段。
    private static func quotedName(in message: String) -> String? {
        guard let open = message.firstIndex(of: "\u{201C}"),
            let close = message.lastIndex(of: "\u{201D}"), open < close
        else { return nil }
        let name = message[message.index(after: open)..<close]
        return name.isEmpty ? nil : String(name)
    }
}
