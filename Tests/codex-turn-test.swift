// 文件职责：Codex app-server 回合执行的集成测试 harness，覆盖自定义 provider 鉴权、MCP 服务器启动与工具同意、并发启动、多会话隔离与中断语义。
// 分层：测试 harness；用真实 CodexAppServerClient/CodexTurnRunner 对接 `Tests/ai-fixtures/codex-stub.js` 桩服务器。
import Foundation

/// 一个回合的 ID 会出现两次且两者都可能迟到，因此 Stop 可能先于两者到达。
@main
@MainActor
struct CodexTurnTests {
    static var failures = 0
    static var passes = 0

    /// 记录一次断言结果，失败时打印消息并累加计数。
    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 依次运行全部用例；存在失败时以退出码 1 结束。
    static func main() async {
        await aCustomProviderIsReadyWithoutAnAccount()
        await aColdTurnChecksAccessItself()
        await aSignedOutRouteIsNeverReady()
        await stopBeforeTurnStartedStillInterrupts()
        await aTurnNamedTwiceIsInterruptedOnce()
        await gearmacsServersAreLaunchedAndTheUsersOwnAreNot()
        await anElicitationIsAnsweredByTheTrustDialog()
        await aRefusedCallIsAFailedRowAndAnHonestReply()
        await aForeignServersElicitationIsNeverAsked()
        await aListThatCannotBeReadRefusesToStart()
        await theListingRunsUnderFindersPath()
        await concurrentStartsLaunchOnce()
        await aStatusCheckJoinsATurnsPendingLaunch()
        await aChangedListRelaunchesAndTheSameOneDoesNot()
        await aWithdrawnServerStopsTheIdleHelper()
        await twoCallsAreAskedAboutByTheirOwnNames()
        await theRoundCapInterruptsTheTurn()
        await unlimitedNeverStopsOnACount()
        await twoChatsStreamSideBySide()
        await stoppingOneChatLeavesTheOther()
        await twoChatsStartingColdShareOneHandshake()
        await aRelaunchEndsTheOtherChatsThreadWithAReason()
        await followUpsKeepTheirChatsResearch()
        await identicalChatsKeepSeparateResearch()
        await changedTurnsStartWithTheSuppliedHistory()
        await failedAndStoppedTurnsNeverBecomeContext()
        await resettingAndRelaunchingDropRetainedThreads()
        await enabledToolsHaveConsistentInstructions()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 同一对话的追问应能访问上一回合已获取的来源（临时 thread 保持不重建）。
    static func followUpsKeepTheirChatsResearch() async {
        guard let server = StubServer(mode: "research") else {
            expect(false, "the research stub installs")
            return
        }
        defer { server.tearDown() }
        let id = UUID()
        let question = AIMessage(role: .user, text: "Find recent benchmarks")
        let first = AIRequest(messages: [question], webSearch: true, conversationID: id)
        let summary = await server.reply(to: first)
        expect(summary.text == "A model benchmark." && summary.error == nil, "research completes")
        let next = AIRequest(
            messages: [
                question, AIMessage(role: .assistant, text: summary.text),
                AIMessage(role: .user, text: "Elaborate")
            ],
            webSearch: true, conversationID: id)
        let detail = await server.reply(to: next)
        expect(
            detail.text == "https://example.com/thread-1/benchmark" && detail.error == nil,
            "a follow-up can access the source fetched in the preceding turn")
        expect(
            server.received.split(separator: "\n").count { $0 == "thread/start" } == 1,
            "a completed conversation keeps its ephemeral thread")
        expect(!server.received.contains("thread/inject_items"), "continuing never duplicates history")
        let withEffort = await server.reply(
            to: AIRequest(
                messages: next.messages + [
                    AIMessage(role: .assistant, text: detail.text),
                    AIMessage(role: .user, text: "Verify")
                ],
                webSearch: true, conversationID: id), effort: "high")
        expect(withEffort.text == detail.text, "changing effort preserves research")
        expect(server.parameters("turn").last?["effort"]?.stringValue == "high", "the new effort is sent")
    }

    /// 转录内容完全相同的两个对话必须各自保留独立的研究来源。
    static func identicalChatsKeepSeparateResearch() async {
        guard let server = StubServer(mode: "research") else {
            expect(false, "the research stub installs")
            return
        }
        defer { server.tearDown() }
        let question = AIMessage(role: .user, text: "Find recent benchmarks")
        let firstID = UUID()
        let secondID = UUID()
        let first = await server.reply(
            to: AIRequest(messages: [question], webSearch: true, conversationID: firstID))
        let second = await server.reply(
            to: AIRequest(messages: [question], webSearch: true, conversationID: secondID))
        _ = await server.reply(to: AIRequest(messages: [AIMessage(role: .user, text: "Name this chat")]))
        for (id, summary, thread) in [(firstID, first.text, "thread-1"), (secondID, second.text, "thread-2")]
        {
            let detail = await server.reply(
                to: AIRequest(
                    messages: [
                        question, AIMessage(role: .assistant, text: summary),
                        AIMessage(role: .user, text: "Elaborate")
                    ],
                    webSearch: true, conversationID: id))
            expect(
                detail.text == "https://example.com/\(thread)/benchmark",
                "identical transcripts keep their own sources")
        }
        expect(
            server.parameters("thread").count == 3,
            "a title gets its own thread without disturbing either chat")
    }

    /// 内容变更（重生、裁剪、编辑、换模型/指令/搜索/附件）的回合应用调用方提供的可见历史开启新 thread。
    static func changedTurnsStartWithTheSuppliedHistory() async {
        let question = AIMessage(role: .user, text: "Find recent benchmarks")
        let followUp = AIMessage(role: .user, text: "Elaborate")
        let complete = [question, AIMessage(role: .assistant, text: "A model benchmark."), followUp]
        let image = AIImage(data: Data([1, 2]), mimeType: "image/png")
        for change in ["regenerate", "trimmed", "edited", "model", "instructions", "search", "attachment"] {
            guard let server = StubServer(mode: "research") else {
                expect(false, "the research stub installs")
                return
            }
            let id = UUID()
            let initial = AIRequest(
                messages: [
                    AIMessage(role: .user, text: question.text, images: change == "attachment" ? [image] : [])
                ],
                webSearch: true, conversationID: id)
            _ = await server.reply(to: initial)
            var messages = complete
            if change == "regenerate" { messages = [question] }
            if change == "trimmed" { messages = [followUp] }
            if change == "edited" { messages[1] = AIMessage(role: .assistant, text: "An edited answer.") }
            let next = AIRequest(
                instructions: change == "instructions" ? "Be concise." : nil,
                messages: messages, webSearch: change != "search", conversationID: id)
            let reply = await server.reply(
                to: next, model: change == "model" ? "another-model" : "gpt-5-codex")
            expect(reply.error == nil, "\(change): the replacement turn completes")
            expect(server.parameters("thread").count == 2, "\(change): a fresh thread avoids stale context")
            let suppliedHistory = server.parameters("history").last?["items"]?.arrayValue ?? []
            expect(
                suppliedHistory.count == messages.count - 1,
                "\(change): only the supplied history is injected")
            if change == "search" {
                expect(
                    server.parameters("thread").last?["config"]?.objectValue?["web_search"]?.stringValue
                        == "disabled",
                    "switching search off takes effect on the new thread")
            }
            server.tearDown()
        }
    }

    /// 失败或被停止的回合不得成为后续上下文。
    static func failedAndStoppedTurnsNeverBecomeContext() async {
        for prompt in ["Fail", "Hold"] {
            guard let server = StubServer(mode: "research") else {
                expect(false, "the research stub installs")
                return
            }
            let id = UUID()
            let question = AIMessage(role: .user, text: "Find recent benchmarks")
            _ = await server.reply(to: AIRequest(messages: [question], webSearch: true, conversationID: id))
            let history = [question, AIMessage(role: .assistant, text: "A model benchmark.")]
            let pending = AIRequest(
                messages: history + [AIMessage(role: .user, text: prompt)], webSearch: true,
                conversationID: id)
            if prompt == "Hold" {
                let task = Task { await server.reply(to: pending) }
                expect(await server.awaitTurns(2), "the turn to stop starts")
                task.cancel()
                _ = await task.value
                expect(await server.awaitLog("interrupt:"), "stopping the retained thread interrupts it")
            } else {
                let failed = await server.reply(to: pending)
                expect(failed.error != nil, "a failed turn is reported")
            }
            let next = await server.reply(
                to: AIRequest(
                    messages: pending.messages + [AIMessage(role: .user, text: "Elaborate")],
                    webSearch: true, conversationID: id))
            expect(
                next.text == "Please provide the source.",
                "\(prompt): the incomplete turn's context is discarded")
            expect(server.parameters("thread").count == 2, "\(prompt): the next send rebuilds its thread")
            server.tearDown()
        }
    }

    /// reset、delete 与 relaunch 都必须丢弃已保留的 thread。
    static func resettingAndRelaunchingDropRetainedThreads() async {
        for change in ["reset", "delete", "relaunch"] {
            guard let server = StubServer(mode: "research") else {
                expect(false, "the research stub installs")
                return
            }
            let id = UUID()
            let question = AIMessage(role: .user, text: "Find recent benchmarks")
            _ = await server.reply(to: AIRequest(messages: [question], webSearch: true, conversationID: id))
            if change == "reset" { server.runner.reset() }
            if change == "delete" { server.runner.discardConversation(id: id) }
            if change == "relaunch" {
                do {
                    try await server.client.start(toolServers: server.servers())
                } catch {
                    expect(false, "the helper relaunches: \(error)")
                }
            }
            let next = await server.reply(
                to: AIRequest(
                    messages: [
                        question, AIMessage(role: .assistant, text: "A model benchmark."),
                        AIMessage(role: .user, text: "Elaborate")
                    ],
                    webSearch: true, conversationID: id))
            expect(next.error == nil, "\(change): a later turn still completes")
            expect(server.parameters("thread").count == 2, "\(change): the old thread cannot be reused")
            expect(
                server.parameters("history").count == 1,
                "\(change): a new thread receives the visible history")
            server.tearDown()
        }
    }

    /// 工具与搜索开关的各种组合下，developerInstructions 必须保持一致。
    static func enabledToolsHaveConsistentInstructions() async {
        for hasTools in [false, true] {
            for search in [false, true] {
                guard let server = StubServer(mode: "research") else {
                    expect(false, "the research stub installs")
                    return
                }
                let stream = server.runner.stream(
                    AIRequest(messages: [AIMessage(role: .user, text: "Hello")], webSearch: search),
                    model: "gpt-5-codex", effort: nil,
                    toolServers: hasTools ? server.session(allowing: true, asked: Box()) : nil)
                do {
                    for try await _ in stream {}
                } catch {
                    expect(false, "the permission probe completes: \(error)")
                }
                let parameters = server.parameters("thread").last ?? [:]
                let instructions = parameters["developerInstructions"]?.stringValue ?? ""
                expect(parameters["ephemeral"]?.boolValue == true, "threads keep research in memory")
                expect(
                    instructions.contains("Never execute commands, read local files"),
                    "local access stays forbidden")
                expect(
                    instructions.contains("Never invoke tools") == (!search && !hasTools),
                    "only a turn with no tools forbids every tool")
                expect(
                    instructions.contains("the MCP tools supplied") == hasTools,
                    "MCP permission matches the supplied tools")
                expect(
                    instructions.contains("Do not use web search.") == !search,
                    "search permission matches the configuration")
                server.tearDown()
            }
        }
    }

    /// 自定义 provider 的 `account/read` 表示无账号且 `requiresOpenaiAuth: false`。
    static func aCustomProviderIsReadyWithoutAnAccount() async {
        guard let server = StubServer(mode: "api-auth") else {
            expect(false, "the custom provider stub installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        defer {
            manager.stop()
            server.tearDown()
        }

        await manager.refresh().value
        expect(
            manager.isConnected && manager.access == .provider && manager.account == nil,
            "a custom provider is ready without an OpenAI account")
        expect(
            manager.models.map(\.id) == ["custom-model"],
            "the custom provider's models are listed")

        let first = await reply(from: manager)
        let second = await reply(from: manager)
        expect(
            first.text == "ready" && second.text == "ready",
            "turns run on the custom provider: \(first.error ?? second.error ?? "")")
        expect(
            server.received.split(separator: "\n").count { $0 == "account/read" } == 1,
            "access is read once by the check, not again before every turn")
    }

    /// 不仅是状态检查，回合守卫本身也必须接受自定义 provider。
    static func aColdTurnChecksAccessItself() async {
        guard let server = StubServer(mode: "api-auth") else {
            expect(false, "the custom provider stub installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        defer {
            manager.stop()
            server.tearDown()
        }

        let cold = await reply(from: manager)
        expect(
            cold.text == "ready" && manager.isConnected && manager.access == .provider,
            "a turn with no check before it runs on a custom provider: \(cold.error ?? "")")
    }

    /// 无账号即视为未登录，除非 Codex 明确说明无需账号。
    static func aSignedOutRouteIsNeverReady() async {
        for mode in ["auth-required", "auth-undetermined"] {
            guard let server = StubServer(mode: mode) else {
                expect(false, "the \(mode) stub installs")
                continue
            }
            let checked = ChatGPTSubscriptionManager(supportDirectory: server.root)
            await checked.refresh().value
            expect(
                checked.phase == .signedOut && !checked.isConnected && checked.models.isEmpty,
                "\(mode): a check without an account is signed out")
            checked.stop()

            let stops = { server.received.split(separator: "\n").count { $0 == "stdin-closed" } }
            let checkStopped = await server.awaitCondition { stops() == 1 }
            let cold = ChatGPTSubscriptionManager(supportDirectory: server.root)
            let attempt = await reply(from: cold)
            expect(
                attempt.error?.contains("codex login") == true && cold.phase == .signedOut,
                "\(mode): a turn without an account asks for sign-in and shows signed out")
            let turnStopped = await server.awaitCondition { stops() == 2 }
            expect(
                checkStopped && turnStopped,
                "\(mode): the signed-out server is stopped, as after a check")
            cold.stop()
            server.tearDown()
        }
    }

    private static func reply(
        from manager: ChatGPTSubscriptionManager
    ) async -> (text: String, error: String?) {
        let stream = manager.turns.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "custom-model", effort: nil)
        var text = ""
        do {
            for try await event in stream {
                if case .text(let delta) = event { text += delta }
            }
        } catch {
            return (text, error.localizedDescription)
        }
        return (text, nil)
    }

    /// 启动即边界：按名启动 GearMac 自己的服务器、按名禁用用户自配的服务器，且从不写入用户配置。
    static func gearmacsServersAreLaunchedAndTheUsersOwnAreNot() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let asked = Box()
        let turn = server.startTurn(toolServers: server.session(allowing: true, asked: asked))
        _ = await server.awaitLog("turn-params:")
        turn.cancel()

        let argv = server.argv
        let key = "mcp_servers.gearmac-probe"
        expect(
            argv.contains(#"\#(key).command="/bin/sh""#)
                && argv.contains {
                    $0.hasPrefix("\(key).args=") && $0.hasSuffix(#""/bin/echo","probe"]"#)
                },
            "GearMac's server is on the launch line under its own name, behind the renaming shell")
        expect(
            argv.contains(#"\#(key).default_tools_approval_mode="prompt""#),
            "in the mode that asks for every tool, so one marked read-only cannot run unasked")
        expect(
            argv.contains("mcp_servers.user-one.enabled=false")
                && argv.contains("mcp_servers.user-two.enabled=false"),
            "and every server the user configured for their own Codex is disabled by name")
        expect(
            argv.contains("mcp_servers.probe.enabled=false")
                && !argv.contains { $0.hasPrefix("mcp_servers.probe.") && !$0.hasSuffix("=false") },
            "including the reader's own `probe`, which GearMac's `probe` never merges into")
        expect(
            server.listArgv.contains("mcp") && server.listArgv.contains("--json"),
            "which were read by a short-lived `mcp list`, so none of them ever started")
        expect(
            server.listArgv.contains("features.plugins=false"),
            "under the same flags the app-server runs with, or the list would name a plugin's")
        expect(
            !argv.contains(where: { $0.contains("s3cret") }),
            "no secret is on argv, where `ps` would show it")
        expect(
            server.environment["TC_MCP_0_0"] == "s3cret",
            "the value reached the child's environment instead")
        expect(
            !server.received.contains("config/value/write")
                && !server.received.contains("config/batchWrite"),
            "and nothing was written to the user's Codex configuration")
        expect(
            server.received.contains(#""approvalPolicy":"untrusted""#),
            "the thread asks before a tool runs, rather than refusing every call")
    }

    /// 用户自配的服务器如果无法被关闭，就会在对话内被启动，因此这里一律不启动。
    static func aListThatCannotBeReadRefusesToStart() async {
        let cases = [
            ("list-fails", "could not read which MCP servers"),
            ("list-garbage", "could not read which MCP servers"),
            ("list-dotted", "\u{201C}has.dot\u{201D} cannot be kept out")
        ]
        for (mode, reason) in cases {
            guard let server = StubServer(mode: mode) else {
                expect(false, "the stub app-server installs")
                return
            }
            var message = ""
            do {
                try await server.client.start()
            } catch {
                message = error.localizedDescription
            }
            expect(
                message.contains(reason) && server.argv.isEmpty && !server.client.isRunning,
                "\(mode): Codex does not start, and says why, rather than run the reader's servers")
            server.tearDown()
        }
    }

    /// Finder 启动的应用 PATH 里没有 `node`，而 npm 或 Homebrew 安装的 `codex` 是 `env node`。
    static func theListingRunsUnderFindersPath() async {
        let rule = ExecutableLocator.environment(
            running: URL(fileURLWithPath: "/opt/tools/bin/codex"),
            adding: ["PATH": "/elsewhere", "NO_COLOR": "0", "TOKEN": "t"],
            inherited: ["PATH": "/usr/bin:/bin", "HOME": "/Users/reader"])
        expect(
            rule["PATH"] == "/opt/tools/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "a CLI's own folder leads its PATH, then Homebrew's, then the PATH the app inherited")
        expect(
            rule["NO_COLOR"] == "1" && rule["TOKEN"] == "t" && rule["HOME"] == "/Users/reader",
            "added variables arrive, but never override the PATH or NO_COLOR")

        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }
        let bin = server.root.appending(path: "bin", directoryHint: .isDirectory)
        let codex = bin.appending(path: "codex")
        let work = server.root.appending(path: "work", directoryHint: .isDirectory)
        let node = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "node") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        // 放在 CLI 旁边，与 npm 和 nvm 的布局一致，这样在本机查找它无需 Homebrew。
        guard let node,
            (try? FileManager.default.createSymbolicLink(
                at: bin.appending(path: "node"), withDestinationURL: node)) != nil
        else {
            expect(false, "node is linked beside the stub")
            return
        }
        var finder = ProcessInfo.processInfo.environment
        finder["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"

        let names = await CodexAppServerClient.foreignServerNames(
            executable: codex, workspace: work,
            codexHome: server.root.appending(path: "home", directoryHint: .isDirectory),
            inherited: finder)
        expect(
            names?.contains("probe") == true,
            "the reader's servers are read under Finder's PATH, so Codex can start")

        let shellPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", finder["PATH"] ?? "", 1)
        let probe = await InstalledAIProbe.run(
            executable: codex, arguments: ["mcp", "list", "--json"], workspace: work)
        setenv("PATH", shellPath, 1)
        expect(probe.status == 0, "a status probe of an `env node` CLI runs under Finder's PATH too")
    }

    /// 与回合竞争的状态检查，或两次快速发送，必须共用同一个 app-server。
    static func concurrentStartsLaunchOnce() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        setenv("TC_STUB_LIST_DELAY", "300", 1)
        defer {
            unsetenv("TC_STUB_LIST_DELAY")
            server.tearDown()
        }
        let client = server.client
        async let first: Void = client.start()
        async let second: Void = client.start()
        let firstStarted = (try? await first) != nil
        let secondStarted = (try? await second) != nil
        expect(
            firstStarted && secondStarted && server.launches == 1 && client.isRunning,
            "two starts at once launch one app-server, and both callers get the running one")

        let stopped = Task { try await client.start(toolServers: server.servers(key: "one")) }
        _ = await server.awaitCondition { server.launches == 1 && server.listed == 2 }
        client.stop()
        let outcome = await stopped.result
        expect(
            (try? outcome.get()) == nil && server.launches == 1 && !client.isRunning,
            "and a Stop that lands while a launch reads the list keeps it from starting afterwards")
    }

    /// 状态检查没有自己的服务器列表，因此绝不能在没有列表时重启回合的 app-server。
    static func aStatusCheckJoinsATurnsPendingLaunch() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        setenv("TC_STUB_LIST_DELAY", "300", 1)
        defer {
            unsetenv("TC_STUB_LIST_DELAY")
            manager.stop()
            server.tearDown()
        }
        let stream = manager.turns.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]), model: "gpt-5-codex",
            effort: nil, toolServers: server.session(allowing: true, asked: Box()))
        let turn = Task {
            var finished = false
            do {
                for try await event in stream where event == .finished { finished = true }
            } catch {}
            return finished
        }
        _ = await server.awaitCondition { server.listed == 1 }
        await manager.refresh().value
        let finished = await turn.value
        expect(
            finished && server.launches == 1
                && server.argv.contains { $0.hasPrefix("mcp_servers.gearmac-probe.") },
            "a status check during a turn's launch joins it, and the turn keeps its servers")
    }

    /// 服务器列表在 exec 时即固定，只有列表变化才值得再启动一次。
    static func aChangedListRelaunchesAndTheSameOneDoesNot() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }
        let asked = Box()
        _ = await server.collect(toolServers: server.session(allowing: true, asked: asked))
        _ = await server.collect(toolServers: server.session(allowing: true, asked: asked))
        expect(server.launches == 1, "the same server list twice runs in the one app-server")
        _ = await server.collect(
            toolServers: server.session(
                allowing: true, asked: asked, servers: server.servers(key: "rotated")))
        expect(
            server.launches == 2 && server.environment["TC_MCP_0_0"] == "rotated",
            "a changed list, a refreshed secret included, relaunches it with the new values")
    }

    /// 关闭就是关闭：从对话中撤回的服务器不得继续存活于空闲 helper 中。
    static func aWithdrawnServerStopsTheIdleHelper() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        let manager = ChatGPTSubscriptionManager(supportDirectory: server.root)
        defer {
            manager.stop()
            server.tearDown()
        }
        let stream = manager.turns.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]), model: "gpt-5-codex",
            effort: nil, toolServers: server.session(allowing: true, asked: Box()))
        var finished = false
        do {
            for try await event in stream where event == .finished { finished = true }
        } catch {}
        manager.dropWithdrawnServers(keeping: ["probe", "other"])
        let closedEarly = await server.awaitCondition(timeout: .milliseconds(300)) {
            server.received.contains("stdin-closed")
        }
        expect(
            finished && !closedEarly,
            "a helper whose servers are all still offered keeps running between turns")
        manager.dropWithdrawnServers(keeping: ["other"])
        expect(
            await server.awaitLog("stdin-closed"),
            "and one launched with a server no longer offered stops without waiting to idle")
    }

    /// 同时两个调用：各自按自己的名字询问，授权后仍逐个处理。
    static func twoCallsAreAskedAboutByTheirOwnNames() async {
        guard let server = StubServer(mode: "mcp-pair") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }
        let reader = GrantingReader()
        let servers = server.servers()
        let session = AIToolServerSession(rounds: 10) {
            servers
        } consent: { call in
            await reader.answer(call)
        }
        let events = await server.collect(toolServers: session)
        expect(
            reader.calls.map(\.tool).sorted() == ["first_tool", "second_tool"],
            "each question names its own call, not whichever of the server's started last")
        expect(
            reader.mostAtOnce == 1 && reader.dialogs == 1,
            "and the second waits for the first dialog, then sees the grant it made")
        expect(
            server.received.components(separatedBy: #"{"action":"accept"}"#).count == 3
                && events.last == .finished,
            "so both are accepted and the turn finishes")
    }

    /// CLI 路由上的 `.ask` 与 API 路由上是同一个对话框。
    static func anElicitationIsAnsweredByTheTrustDialog() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let asked = Box()
        let events = await server.collect(
            toolServers: server.session(allowing: true, asked: asked))
        expect(
            asked.calls == [AIToolServerCall(handle: "probe", tool: "safe_echo")],
            "the elicitation became a question about the call Codex named")
        expect(
            server.received.contains(#"elicitation:{"action":"accept"}"#),
            "an allowed call is accepted, and nothing about persisting it is sent back")
        expect(
            events.contains(.toolCall(id: "call-1", origin: "Probe", title: "safe_echo")),
            "the call renders as the row the BYOK loop would have written")
        expect(
            events.contains(.toolResult(id: "call-1", isError: false)),
            "and its completion settles that row")
    }

    /// 授权只针对 GearMac 的服务器；对其他服务器的询问直接拒绝，绝不上报用户。
    static func aForeignServersElicitationIsNeverAsked() async {
        guard let server = StubServer(mode: "mcp-foreign") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let asked = Box()
        let events = await server.collect(
            toolServers: server.session(allowing: true, asked: asked))
        expect(
            asked.calls.isEmpty && server.received.contains(#"elicitation:{"action":"decline"}"#),
            "a call on the reader's own `probe` is declined without asking about GearMac's")
        expect(
            events.contains(.toolCall(id: "call-1", origin: "probe", title: "safe_echo")),
            "and its row keeps Codex's name, never the title of GearMac's same-handle server")
    }

    static func aRefusedCallIsAFailedRowAndAnHonestReply() async {
        guard let server = StubServer(mode: "mcp") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let events = await server.collect(
            toolServers: server.session(allowing: false, asked: Box()))
        expect(
            server.received.contains(#"elicitation:{"action":"decline"}"#),
            "Escape declines that one call")
        expect(
            events.contains(.toolResult(id: "call-1", isError: true)),
            "which settles as a failed row rather than a failed turn")
        expect(events.last == .finished, "and the reply still ends")
    }

    /// Codex 自身不标明轮次，因此上限按调用计数，超出后中断该回合。
    static func theRoundCapInterruptsTheTurn() async {
        guard let server = StubServer(mode: "mcp-rounds") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let error = await server.streamError(
            toolServers: server.session(allowing: true, asked: Box(), rounds: 2))
        expect(
            error?.contains("Stopped after 2 rounds of tool calls.") == true,
            "the turn fails with the sentence the loop uses")
        expect(
            await server.awaitLog("interrupt:thread-1:turn-1"),
            "and the turn Codex is still running is interrupted rather than left to finish")
    }

    /// 无上限时不向 Codex 传任何计数，只有模型自己的回答能结束回合。
    static func unlimitedNeverStopsOnACount() async {
        guard let server = StubServer(mode: "mcp-many") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let events = await server.collect(
            toolServers: server.session(allowing: true, asked: Box(), rounds: nil))
        let calls = events.count {
            if case .toolCall = $0 { return true }
            return false
        }
        expect(calls == 120, "all 120 calls run, past the largest step Settings offers")
        expect(
            events.contains(.text("done")) && events.last == .finished && server.interrupts == 0,
            "and the turn finishes on the model's answer, never interrupted")

        guard let capped = StubServer(mode: "mcp-many") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { capped.tearDown() }
        let error = await capped.streamError(
            toolServers: capped.session(allowing: true, asked: Box(), rounds: 100))
        expect(
            error?.contains("Stopped after 100 rounds of tool calls.") == true,
            "while the largest step stops that same turn, naming its own number")
    }

    /// Stop 在任何东西命名该回合之前到达，且 `turn/start` 从不返回。
    static func stopBeforeTurnStartedStillInterrupts() async {
        guard let server = StubServer(mode: "hold-turn") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let turn = server.startTurn(effort: "high")
        guard await server.awaitMark("turn-start-received") else {
            expect(false, "the stub app-server is asked to start a turn")
            return
        }
        expect(
            server.received.contains(#""effort":"high""#),
            "reasoning effort belongs to the turn and does not mutate Codex settings")
        expect(
            !server.received.contains("config/value/write"),
            "a GearMac turn never writes the user's Codex configuration")

        turn.cancel()
        let dropped = await server.awaitCondition { !server.runner.isActive }
        expect(dropped, "Stop drops a turn that nothing has named yet")

        // 服务端直到此刻才命名该回合 —— 此时 runner 已放开该 thread。
        server.mark("stop-landed")
        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "a Stop that beat turn/started still interrupts the turn that starts")
    }

    /// 同一个被停止的回合会收到两个名字；按名字逐个中断会发出两次中断。
    static func aTurnNamedTwiceIsInterruptedOnce() async {
        guard let server = StubServer(mode: "hold-both") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let turn = server.startTurn()
        guard await server.awaitMark("turn-start-received") else {
            expect(false, "the stub app-server is asked to start a turn")
            return
        }

        turn.cancel()
        _ = await server.awaitCondition { !server.runner.isActive }
        server.mark("stop-landed")

        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "a Stopped turn is interrupted as soon as its ID arrives")
        // 在排除第二次中断之前，给足它出现的机会。
        _ = await server.awaitCondition(timeout: .milliseconds(400)) { server.interrupts > 1 }
        expect(server.interrupts == 1, "the turn's second name spends no second interrupt")
    }

    /// 过去第二个对话的回合会以 “A newer request replaced this response.” 结束第一个对话。
    static func twoChatsStreamSideBySide() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        guard await server.awaitTurns(1) else {
            expect(false, "the first chat starts its turn")
            return
        }
        let second = server.collectTurn()
        guard await server.awaitTurns(2) else {
            expect(false, "the second chat starts its turn while the first is live")
            return
        }
        server.mark("release")

        let firstReply = await first.value
        let secondReply = await second.value
        expect(firstReply.error == nil, "the first chat is not replaced by the second")
        expect(firstReply.text == "from thread-1", "the first chat reads only its own thread")
        expect(
            firstReply.reasoning == "**Planning** done.\n\n**Checking**",
            "each summary part opens a paragraph, a split part does not: "
                + firstReply.reasoning.debugDescription)
        expect(secondReply.error == nil, "the second chat finishes too")
        expect(secondReply.text == "from thread-2", "the second chat reads only its own thread")
        expect(!server.runner.isActive, "both finished turns are released")
    }

    /// 回复与其标题一同发出，且都在桩（与 Codex 一样）要求的握手之前。
    static func twoChatsStartingColdShareOneHandshake() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        let second = server.collectTurn()
        guard await server.awaitTurns(2) else {
            expect(false, "both cold turns reach the server: \(server.received)")
            return
        }
        server.mark("release")
        let replies = [await first.value, await second.value]
        expect(
            replies.allSatisfy { $0.error == nil },
            "neither cold turn is sent before the handshake: \(replies.map { String(describing: $0.error) })")
        expect(
            server.received.split(separator: "\n").count { $0 == "initialize" } == 1,
            "one process, one handshake")
    }

    /// 服务器列表在启动时固定：另一个对话带上新列表就会拿走该进程。
    static func aRelaunchEndsTheOtherChatsThreadWithAReason() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        guard await server.awaitTurns(1) else {
            expect(false, "the first chat starts its turn")
            return
        }
        let armed = server.startTurn(toolServers: server.session(allowing: true, asked: Box()))
        let reply = await first.value
        expect(
            String(describing: reply.error).contains("restarted"),
            "the stranded chat is told why its reply ended: \(String(describing: reply.error))")
        armed.cancel()
        _ = await armed.value
    }

    static func stoppingOneChatLeavesTheOther() async {
        guard let server = StubServer(mode: "parallel") else {
            expect(false, "the stub app-server installs")
            return
        }
        defer { server.tearDown() }

        let first = server.collectTurn()
        guard await server.awaitTurns(1) else {
            expect(false, "the first chat starts its turn")
            return
        }
        let second = server.collectTurn()
        guard await server.awaitTurns(2) else {
            expect(false, "the second chat starts its turn while the first is live")
            return
        }
        first.cancel()
        _ = await first.value
        server.mark("release")

        let secondReply = await second.value
        expect(secondReply.error == nil, "Stop on one chat leaves the other streaming")
        expect(secondReply.text == "from thread-2", "the surviving chat keeps its own reply")
        let interrupted = await server.awaitLog("interrupt:thread-1:turn-1")
        expect(interrupted, "the stopped chat's turn is interrupted")
        expect(!server.received.contains("interrupt:thread-2"), "the other chat's turn is not interrupted")
    }
}

/// 记录 runner 询问过的调用，跨过 consent 闭包的那一跳收集。
@MainActor
final class Box {
    var calls: [AIToolServerCall] = []
}

/// 一次只被询问一次、思考一会儿、然后为该对话授权服务器的读取方。
@MainActor
final class GrantingReader {
    var calls: [AIToolServerCall] = []
    var dialogs = 0
    var mostAtOnce = 0
    private var atOnce = 0
    private var granted = false

    func answer(_ call: AIToolServerCall) async -> Bool {
        calls.append(call)
        atOnce += 1
        mostAtOnce = max(mostAtOnce, atOnce)
        defer { atOnce -= 1 }
        guard !granted else { return true }
        dialogs += 1
        try? await Task.sleep(for: .milliseconds(150))
        granted = true
        return true
    }
}

/// 面向 `Tests/ai-fixtures/codex-stub.js` 桩服务器的真实客户端。
@MainActor
final class StubServer {
    let root: URL
    let client: CodexAppServerClient
    let runner: CodexTurnRunner

    /// 在临时目录安装桩脚本，并把 PATH/ZDOTDIR 指向它，以拦截真实的 `codex`。
    init?(mode: String) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-turn-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = root.appending(path: "bin/codex")
        do {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "Tests/ai-fixtures/codex-stub.js"), to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            print("the stub app-server could not be installed: \(error)")
            return nil
        }

        // 定位器会遍历 PATH，因此桩只需排在真实 `codex` 之前。
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(executable.deletingLastPathComponent().path):\(inherited)", 1)
        // 定位器会先询问登录 shell；用户的 rc 文件会把真实的 `codex` 排到前面。
        setenv("ZDOTDIR", root.path, 1)
        // `/etc/zprofile` 的 path_helper 会把 Homebrew 的 `codex` 排到桩之前；此处撤销该影响。
        try? #"export GEARMAC_SAVED_PATH="$PATH""#.write(
            to: root.appending(path: ".zshenv"), atomically: true, encoding: .utf8)
        try? #"[ -n "$GEARMAC_SAVED_PATH" ] && export PATH="$GEARMAC_SAVED_PATH""#.write(
            to: root.appending(path: ".zprofile"), atomically: true, encoding: .utf8)
        setenv("TC_STUB_ROOT", root.path, 1)
        setenv("TC_STUB_MODE", mode, 1)

        let client = CodexAppServerClient(
            codexHome: root.appending(path: "home", directoryHint: .isDirectory),
            workspace: root.appending(path: "work", directoryHint: .isDirectory))
        let runner = CodexTurnRunner(client: client)
        runner.connect = { servers in
            try await client.start(toolServers: servers)
            return []
        }
        client.onNotification = { method, params in
            runner.handle(method: method, params: params)
        }

        self.root = root
        self.client = client
        self.runner = runner
    }

    /// 模拟应用行为：一个遍历 provider 流的 task，其中 Stop 即取消该 task。
    func startTurn(
        effort: String? = nil, toolServers: AIToolServerSession? = nil
    ) -> Task<Void, Never> {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: effort, toolServers: toolServers)
        return Task {
            do {
                for try await _ in stream {}
            } catch {}
        }
    }

    /// 跑一个回合并收集其全部流事件。
    func collect(toolServers: AIToolServerSession?) async -> [AIStreamEvent] {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: nil, toolServers: toolServers)
        var events: [AIStreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
        } catch {}
        return events
    }

    /// 发送一个请求，返回拼接后的文本与可能的错误描述。
    func reply(
        to request: AIRequest, model: String = "gpt-5-codex", effort: String? = nil
    )
        async -> (text: String, error: String?)
    {
        var text = ""
        do {
            for try await event in runner.stream(request, model: model, effort: effort) {
                if case .text(let delta) = event { text += delta }
            }
            return (text, nil)
        } catch {
            return (text, error.localizedDescription)
        }
    }

    /// 跑一个回合并返回其抛出的错误描述，未出错则为 nil。
    func streamError(toolServers: AIToolServerSession?) async -> String? {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: nil, toolServers: toolServers)
        do {
            for try await _ in stream {}
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// 一个本地服务器，其密钥用于区分两次启动的列表。
    func servers(key: String = "s3cret") -> [AIToolServer] {
        [
            AIToolServer(
                handle: "probe", title: "Probe",
                transport: .command(
                    path: "/bin/echo", arguments: ["probe"], environment: ["API_KEY": key]))
        ]
    }

    /// 对所有调用都给出同一答复的读取方。
    func session(
        allowing: Bool, asked: Box, rounds: Int? = 10, servers: [AIToolServer]? = nil
    ) -> AIToolServerSession {
        let servers = servers ?? self.servers()
        return AIToolServerSession(rounds: rounds) {
            servers
        } consent: { call in
            await MainActor.run { asked.calls.append(call) }
            return allowing
        }
    }

    /// 按转录稿的方式收集单个回合的文本，并保留结束它的原因。
    func collectTurn() -> Task<(text: String, reasoning: String, error: Error?), Never> {
        let stream = runner.stream(
            AIRequest(messages: [AIMessage(role: .user, text: "Hello")]),
            model: "gpt-5-codex", effort: nil)
        return Task {
            var text = ""
            var reasoning = ""
            do {
                for try await event in stream {
                    if case .text(let delta) = event { text += delta }
                    if case .reasoning(let delta) = event { reasoning += delta }
                }
            } catch {
                return (text, reasoning, error)
            }
            return (text, reasoning, nil)
        }
    }

    /// 等待服务端至少记录 `count` 个回合参数。
    func awaitTurns(_ count: Int) async -> Bool {
        await awaitCondition {
            self.received.split(separator: "\n").count { $0.hasPrefix("turn-params:") } >= count
        }
    }

    /// 桩服务器记录的全部输入日志。
    var received: String {
        (try? String(contentsOf: root.appending(path: "received.log"), encoding: .utf8)) ?? ""
    }

    /// 解析指定类型（如 `thread`、`turn`、`history`）的参数记录。
    func parameters(_ kind: String) -> [[String: JSONValue]] {
        let prefix = "\(kind)-params:"
        return received.split(separator: "\n").compactMap { line in
            guard line.hasPrefix(prefix), let data = line.dropFirst(prefix.count).data(using: .utf8) else {
                return nil
            }
            return JSONValue(data: data)?.objectValue
        }
    }

    /// 最近一次启动 app-server 的 argv。
    var argv: [String] {
        decode(root.appending(path: "argv.log"))
    }

    /// 已启动的 app-server 数量，每个占一行 `argv.log`；列表查询不算在内。
    var launches: Int {
        text(root.appending(path: "argv.log")).split(separator: "\n").count
    }

    /// 已执行的列表查询数量，每个占一行 `list-argv.log`。
    var listed: Int {
        text(root.appending(path: "list-argv.log")).split(separator: "\n").count
    }

    /// 最近一次列表查询的 argv。
    var listArgv: [String] {
        decode(root.appending(path: "list-argv.log"))
    }

    /// 子进程最终继承的环境变量。
    var environment: [String: String] {
        guard let line = text(root.appending(path: "env.log")).split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let values = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return values
    }

    /// 读取日志文件最后一行并解析为字符串数组。
    private func decode(_ url: URL) -> [String] {
        guard let line = text(url).split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return values
    }

    /// 读取文件内容，失败时返回空字符串。
    private func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 已发出的中断次数。
    var interrupts: Int {
        received.split(separator: "\n").count { $0.hasPrefix("interrupt:") }
    }

    /// 落下一个标记文件，供测试与服务端同步。
    func mark(_ name: String) {
        FileManager.default.createFile(atPath: root.appending(path: name).path, contents: nil)
    }

    /// 等待某个标记文件出现。
    func awaitMark(_ name: String) async -> Bool {
        await awaitCondition {
            FileManager.default.fileExists(atPath: self.root.appending(path: name).path)
        }
    }

    /// 等待接收日志中出现指定文本。
    func awaitLog(_ line: String) async -> Bool {
        await awaitCondition { self.received.contains(line) }
    }

    /// 采用轮询而非固定睡眠，使通过只花必需的时间，失败也能及时结束。
    func awaitCondition(
        timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// 停止客户端并删除临时目录。
    func tearDown() {
        client.stop()
        try? FileManager.default.removeItem(at: root)
    }
}
