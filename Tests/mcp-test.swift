// 文件职责：MCP 纯逻辑部分的测试：线路帧格式、路由调用的名称、信任策略，以及聊天中的 @handle 寻址。
// 分层：测试 harness；只覆盖纯函数与值类型，不启动进程或网络。

import Foundation

/// MCP 纯逻辑层的单元测试集合。
@main
@MainActor
struct MCPTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：失败时累加失败数并打印失败信息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 依次运行全部用例，并在有失败时以非零状态码退出。
    static func main() {
        framingCarriesTheProtocolVersion()
        parsingTellsRepliesFromNotifications()
        slugsAreDerivedAndUnique()
        toolNamesRouteBackToTheirServer()
        toolListsDropWhatCannotBeCalled()
        outputFlattensToWhatAModelCanRead()
        trustDecidesFromStandingAndChatGrants()
        addressingTakesOnlyAKnownHandle()
        settingsPersistAndKeepHandlesApart()
        serversBecomeWhatACLICanRunItself()
        onlyOneCopyOfALocalServerRuns()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 服务器若收不到 `"jsonrpc"` 字段，会以错误而不是结果作答。
    static func framingCarriesTheProtocolVersion() {
        guard let data = try? MCPProtocol.request(id: 7, method: "tools/list"),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            expect(false, "a request encodes to a JSON object")
            return
        }
        expect(object["jsonrpc"] as? String == "2.0", "every message names JSON-RPC 2.0")
        expect(object["id"] as? Int == 7, "the id survives encoding")
        expect(object["params"] == nil, "no params means the key is absent, not null")
        expect(data.last != 0x0A, "an HTTP body is not newline-terminated")

        let framed = try? MCPProtocol.request(
            id: 1, method: "initialize", params: ["a": 1], newlineTerminated: true)
        expect(framed?.last == 0x0A, "a stdio message ends in the newline that frames it")

        let notification = try? MCPProtocol.notification(method: "notifications/initialized")
        let decoded =
            notification.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        expect(decoded?["id"] == nil, "a notification carries no id")
    }

    /// 解析能区分回复、错误、通知与需要 GearMac 应答的服务器请求。
    static func parsingTellsRepliesFromNotifications() {
        let response = MCPProtocol.parse(Data(#"{"jsonrpc":"2.0","id":3,"result":{"ok":true}}"#.utf8))
        expect(
            response == .response(id: 3, result: .object(["ok": .bool(true)])),
            "a result parses as the reply to its id")

        let failure = MCPProtocol.parse(
            Data(#"{"jsonrpc":"2.0","id":3,"error":{"code":-1,"message":"nope"}}"#.utf8))
        expect(failure == .failure(id: 3, message: "nope"), "an error carries the server's message")

        let notification = MCPProtocol.parse(
            Data(#"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#.utf8))
        expect(
            notification == .notification(method: "notifications/tools/list_changed", params: .object([:])),
            "a method without an id is a notification")

        guard
            case .request(let id, let method) = MCPProtocol.parse(
                Data(#"{"jsonrpc":"2.0","id":"a1","method":"sampling/createMessage"}"#.utf8))
        else {
            expect(false, "a method with an id is a request GearMac must answer")
            return
        }
        expect(
            id == .string("a1") && method == "sampling/createMessage",
            "a server request keeps its string id, so the decline can address it")
        expect(
            MCPProtocol.parse(Data("not json".utf8)) == .invalid,
            "garbage on the wire is invalid, never a silent success")
    }

    /// slug 由名称派生、只含可输入字符，并在冲突时追加序号。
    static func slugsAreDerivedAndUnique() {
        expect(MCPSlug.normalize("GitHub Issues") == "github-issues", "a name becomes a handle")
        expect(MCPSlug.normalize("  ") == "server", "a nameless server still gets a handle")
        expect(
            MCPSlug.normalize("Files!! & Folders").allSatisfy {
                $0.isLowercase || $0.isNumber || $0 == "-"
            }, "punctuation never reaches a handle")
        expect(
            MCPSlug.normalize(String(repeating: "a", count: 60)).count <= MCPSlug.maxLength,
            "a handle stays typeable")
        expect(
            MCPSlug.make(from: "github", existing: ["github"]) == "github-2",
            "a taken handle is suffixed rather than refused")
        expect(
            MCPSlug.make(from: "github", existing: ["github", "github-2"]) == "github-3",
            "and keeps counting past the first collision")
    }

    /// 工具名由 handle 与工具名合成，并能反向解析回原服务器。
    static func toolNamesRouteBackToTheirServer() {
        let wire = MCPToolName.compose(slug: "github", tool: "search_issues")
        expect(wire == "github__search_issues", "a name is the handle, the separator, the tool")
        let parsed = MCPToolName.parse(wire)
        expect(
            parsed?.slug == "github" && parsed?.tool == "search_issues",
            "and parses back to exactly what composed it")
        expect(MCPToolName.parse("plain_name") == nil, "a name without the separator is not ours")

        let awkward = MCPToolName.compose(slug: "github", tool: "search issues/now")
        expect(
            awkward.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") },
            "a name only ever uses characters both providers accept")
        let long = MCPToolName.compose(slug: "github", tool: String(repeating: "x", count: 200))
        expect(long.count <= MCPToolName.maxLength, "and never exceeds the tighter provider's cap")
        expect(
            MCPToolName.parse(long)?.slug == "github",
            "the handle is the half that survives a trim, because it is what routes the call")
    }

    /// 工具列表中缺名或缺 schema 的条目会被丢弃或补全，使其仍可被调用。
    static func toolListsDropWhatCannotBeCalled() {
        let listed = JSONValue([
            "tools": [
                ["name": "read_file", "description": "Reads", "inputSchema": ["type": "object"]],
                ["description": "no name here"],
                ["name": "write_file"]
            ]
        ])
        let id = UUID()
        let tools = MCPTool.list(listed, serverID: id, serverSlug: "fs", serverTitle: "Files")
        expect(tools.count == 2, "an entry without a name is dropped rather than offered")
        expect(tools.first?.wireName == "fs__read_file", "a tool carries the handle that routes it")
        expect(
            tools.last?.inputSchema.objectValue?["type"]?.stringValue == "object",
            "a tool without a schema still gets one the providers accept")
        let ai = tools.first?.aiTool
        expect(
            ai?.origin == "Files" && ai?.title == "read_file",
            "the transcript pair travels with the tool, so the AI layer never parses a wire name")
    }

    /// 工具输出被展平成模型可读的文本，并保留 isError 标记。
    static func outputFlattensToWhatAModelCanRead() {
        let text = MCPToolOutput.flatten(
            JSONValue(["content": [["type": "text", "text": "one"], ["type": "text", "text": "two"]]]))
        expect(text.content == "one\ntwo" && !text.isError, "text blocks join in order")

        let failed = MCPToolOutput.flatten(
            JSONValue(["isError": true, "content": [["type": "text", "text": "denied"]]]))
        expect(failed.isError, "a tool's own failure stays marked as one")

        let image = MCPToolOutput.flatten(JSONValue(["content": [["type": "image", "data": "…"]]]))
        expect(
            image.content.contains("omitted"),
            "a picture is named rather than inlined into a text context")

        let structured = MCPToolOutput.flatten(JSONValue(["structuredContent": ["count": 2]]))
        expect(structured.content.contains("count"), "structured-only output is read as JSON")
        expect(
            MCPToolOutput.flatten(JSONValue([:])).content.isEmpty == false,
            "an empty answer still says something rather than nothing")
    }

    /// 信任决策由服务器的信任设置与当前聊天的临时授权共同决定。
    static func trustDecidesFromStandingAndChatGrants() {
        expect(
            MCPTrustPolicy.decide(trust: .never, isGrantedForChat: true) == .refuse,
            "a withheld server stays withheld, whatever a chat granted")
        expect(
            MCPTrustPolicy.decide(trust: .always, isGrantedForChat: false) == .allow,
            "a trusted server never asks again")
        expect(
            MCPTrustPolicy.decide(trust: .ask, isGrantedForChat: false) == .ask,
            "the first call of a chat is asked about")
        expect(
            MCPTrustPolicy.decide(trust: .ask, isGrantedForChat: true) == .allow,
            "and the rest of that chat is not")
    }

    /// 只有已知且位于开头的 @handle 才会限定本轮目标。
    static func addressingTakesOnlyAKnownHandle() {
        let slugs: Set<String> = ["github", "files"]
        let addressed = MCPComposerAddress.parse("@github list my issues", slugs: slugs)
        expect(
            addressed.slug == "github" && addressed.rest == "list my issues",
            "a handle scopes the turn and leaves the composer's text behind")
        expect(
            MCPComposerAddress.parse("@GitHub hello", slugs: slugs).slug == "github",
            "a handle is matched however it was capitalised")

        let unknown = MCPComposerAddress.parse("@nosuch hello", slugs: slugs)
        expect(
            unknown.slug == nil && unknown.rest == "@nosuch hello",
            "an unknown handle is text, and is sent exactly as typed")
        expect(
            MCPComposerAddress.parse("email me @github", slugs: slugs).slug == nil,
            "only a leading handle addresses a server")
        expect(MCPComposerAddress.parse("@", slugs: slugs).slug == nil, "a bare @ addresses nothing")
        expect(
            MCPComposerAddress.parse("@files", slugs: slugs).rest.isEmpty,
            "a handle with nothing after it leaves an empty turn rather than its own text")
    }

    /// 服务器设置可持久化，且各服务器的 handle 始终唯一。
    static func settingsPersistAndKeepHandlesApart() {
        let suite = "mcp-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "the harness can open its own defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MCPSettingsStore(defaults: defaults)
        store.save(
            MCPServer(name: "GitHub", transport: .http(url: "https://x/mcp", headerName: "Authorization")))
        store.save(
            MCPServer(name: "GitHub", transport: .stdio(command: "npx", arguments: [], environmentKeys: [])))
        expect(store.servers.count == 2, "two servers may honestly share a name")
        expect(
            Set(store.servers.map(\.slug)).count == 2,
            "but never a handle, or `@slug` would name both")

        var edited = store.servers[0]
        edited.trust = .always
        store.save(edited)
        expect(store.servers.count == 2, "saving an existing server updates it rather than adding")
        expect(store.server(id: edited.id)?.trust == .always, "and keeps what was edited")

        let reloaded = MCPSettingsStore(defaults: defaults)
        expect(
            reloaded.servers.map(\.slug) == store.servers.map(\.slug),
            "servers survive a relaunch")
        expect(reloaded.server(slug: "github") != nil, "and stay reachable by handle")

        store.remove(id: edited.id)
        expect(store.servers.count == 1, "removal takes exactly one")
    }

    /// 把同样的服务器转换成 CLI 路由自带客户端能直接运行的形态。
    static func serversBecomeWhatACLICanRunItself() {
        var remote = MCPServer(
            name: "Linear", slug: "linear",
            transport: .http(url: "https://mcp.linear.app/mcp", headerName: "Authorization"))
        remote.oauth = true
        expect(
            remote.toolServer(headerValue: "", environment: [:], bearerToken: "tok-9")?.transport
                == .url(
                    "https://mcp.linear.app/mcp", headerName: "Authorization",
                    headerValue: "Bearer tok-9"),
            "an OAuth server lends the session's token as the header GearMac itself would send")
        expect(
            remote.toolServer(headerValue: "", environment: [:], bearerToken: nil) == nil,
            "and an OAuth server nobody is signed into is not offered at all")
        var switched = MCPServer(
            name: "Switched", slug: "switched",
            transport: .http(url: "https://switched.example/mcp", headerName: "X-Api-Key"))
        switched.oauth = true
        expect(
            switched.toolServer(headerValue: "stale", environment: [:], bearerToken: "tok-1")?
                .transport
                == .url(
                    "https://switched.example/mcp", headerName: "Authorization",
                    headerValue: "Bearer tok-1"),
            "a lent token always goes as Authorization, never under a header name left from before")

        let open = MCPServer(
            name: "Open", slug: "open",
            transport: .http(url: "https://open.example/mcp", headerName: "Authorization"))
        expect(
            open.toolServer(headerValue: "", environment: [:], bearerToken: nil)?.transport
                == .url("https://open.example/mcp", headerName: "Authorization", headerValue: ""),
            "a server that needs no credential is still offered, with no header to send")

        let header = MCPServer(
            name: "Notes", slug: "notes",
            transport: .http(url: "https://notes.example/mcp", headerName: " X-Api-Key "))
        expect(
            header.toolServer(headerValue: "k1", environment: [:], bearerToken: nil)?.transport
                == .url("https://notes.example/mcp", headerName: "X-Api-Key", headerValue: "k1"),
            "a header-authenticated server carries its own name and value, trimmed")

        let local = MCPServer(
            name: "Files", slug: "files",
            transport: .stdio(
                command: "/bin/node", arguments: ["s.js"], environmentKeys: ["API_KEY"]))
        expect(
            local.toolServer(
                headerValue: "", environment: ["API_KEY": "s3cret", "OTHER": "x"],
                bearerToken: nil)?
                .transport
                == .command(
                    path: "/bin/node", arguments: ["s.js"], environment: ["API_KEY": "s3cret"]),
            "a local server takes only the variables it declared, never the whole secret item")
        expect(
            local.toolServer(headerValue: "", environment: [:], bearerToken: nil)?.title == "Files",
            "and both kinds keep the handle and title a transcript row is written from")
        expect(
            MCPServer(
                name: "Empty", slug: "empty",
                transport: .stdio(
                    command: "", arguments: [], environmentKeys: [])
            )
            .toolServer(headerValue: "", environment: [:], bearerToken: nil) == nil,
            "a server with no command is nothing a CLI could start")
    }

    /// Codex 与 Claude 会自行启动本地服务器的副本；GearMac 再启动就会是第二个。
    static func onlyOneCopyOfALocalServerRuns() {
        let local = MCPServer(
            name: "Files", slug: "files",
            transport: .stdio(command: "/bin/node", arguments: [], environmentKeys: []))
        let remote = MCPServer(
            name: "Linear", slug: "linear",
            transport: .http(url: "https://mcp.linear.app/mcp", headerName: "Authorization"))
        expect(
            local.runsInGearMac(whileCLIRouteSelected: false),
            "on an API route GearMac runs a local server, since it is the one calling it")
        expect(
            !local.runsInGearMac(whileCLIRouteSelected: true),
            "on Codex or Claude it leaves the local server to the CLI's own copy")
        expect(
            remote.runsInGearMac(whileCLIRouteSelected: true),
            "while a remote one stays connected: a session, no process, and a live status row")
    }
}
