// 文件职责：本地 stdio MCP 服务器的端到端测试：握手、工具列表、调用，以及连接结束的各种方式。
// 分层：测试 harness；以真实子进程方式启动 stub MCP 服务器，覆盖连接与 MCPServerManager 的行为。

import Foundation

/// MCP stdio 连接的端到端用例集合。
@main
@MainActor
struct MCPStdioTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：条件不成立时累加失败数并打印失败信息。
    static func expect(_ condition: Bool, _ message: String) {
        if condition { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    /// 依次运行全部用例，并在有失败时以非零状态码退出。
    static func main() async {
        await aServerConnectsListsAndAnswers()
        await aToolsOwnFailureIsContentNotAnError()
        await aServerThatRefusesToStartSaysWhy()
        await aServerThatDiesMidCallFailsThatCall()
        await anUnsolicitedServerRequestIsDeclined()
        await stoppingLeavesNothingRunning()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 握手后应列出工具、按 handle 命名空间化，并原样传递调用参数与文本结果。
    static func aServerConnectsListsAndAnswers() async {
        guard let stub = StubMCPServer() else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        expect(connection.status == .ready(tools: 2), "a handshake ends in the tools it listed")
        expect(
            connection.tools.map(\.wireName) == ["stub__read_file", "stub__write_file"],
            "and every tool arrives namespaced by the handle that routes it")

        let answer = try? await connection.call(
            "read_file", arguments: .object(["path": .string("/tmp/x")]))
        expect(
            answer?.0 == #"{"path":"/tmp/x"}"# && answer?.1 == false,
            "arguments reach the server intact and its text comes back as content")
        connection.stop()
    }

    /// `isError` 表示工具本身拒绝了这次调用，模型可以读到它并绕过处理。
    static func aToolsOwnFailureIsContentNotAnError() async {
        guard let stub = StubMCPServer() else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        let answer = try? await connection.call("write_file", arguments: .object([:]))
        expect(answer?.1 == true, "a refusing tool is marked as one")
        expect(answer?.0 == "read only", "and its reason survives to the model")
        connection.stop()
    }

    /// 服务器在握手期间退出时应进入 failed 状态，保留其自身打印的原因，并可重新启动。
    static func aServerThatRefusesToStartSaysWhy() async {
        guard let stub = StubMCPServer(mode: "die-on-initialize") else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        guard case .failed(let message) = connection.status else {
            expect(false, "a server that exits during the handshake ends up failed")
            return
        }
        expect(
            message.contains("refused to start"),
            "and the row shows what the server itself printed, not a generic sentence")
        expect(connection.tools.isEmpty, "a failed server offers nothing")
        expect(
            connection.isIdle,
            "and is startable again, so the next visit to chat retries rather than staying broken")
    }

    /// 进程退出时必须让进行中的调用失败，否则该轮会一直等待一个已消失的进程；该调用应抛错而不是挂起，且连接不再声称就绪。
    static func aServerThatDiesMidCallFailsThatCall() async {
        guard let stub = StubMCPServer(mode: "die-on-call") else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        expect(connection.status.isReady, "the server starts before it is asked to die")
        do {
            _ = try await connection.call("read_file", arguments: .object([:]))
            expect(false, "a call to a server that exits throws rather than hanging")
        } catch {
            expect(true, "a call to a server that exits throws rather than hanging")
        }
        expect(!connection.status.isReady, "and the connection stops claiming to be ready")
    }

    /// 服务器主动发来的请求应被拒绝，且不打断握手流程。
    static func anUnsolicitedServerRequestIsDeclined() async {
        guard let stub = StubMCPServer(mode: "unsolicited-request") else { return }
        defer { stub.tearDown() }

        let connection = stub.connection()
        await connection.start()
        expect(
            connection.status.isReady,
            "a server asking GearMac for something is declined without derailing the handshake")
        connection.stop()
    }

    /// 停止连接后应撤回所有工具并清除连接状态。
    static func stoppingLeavesNothingRunning() async {
        guard let stub = StubMCPServer() else { return }
        defer { stub.tearDown() }

        let manager = MCPServerManager(secrets: MCPSecretStore(keychain: .init(scope: "mcp-test")))
        manager.reconcile([stub.server])
        let ready = await stub.awaitCondition { manager.status(of: stub.server.id).isReady }
        expect(ready, "the manager starts what Settings holds")
        expect(manager.tools.count == 2, "and publishes what it found")

        manager.stop()
        expect(manager.tools.isEmpty, "stopping withdraws every tool")
        expect(manager.status(of: stub.server.id) == .stopped, "and forgets the connection")
    }
}

/// 端到端测试用的 stub MCP 服务器夹具：把脚本安装到临时目录并置入 PATH。
@MainActor
final class StubMCPServer {
    let root: URL
    let server: MCPServer

    /// 把 stub 脚本复制到临时目录并加入 PATH 后构建服务器描述；安装失败返回 nil。
    init?(mode: String = "normal") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mcp-stdio-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executable = root.appending(path: "bin/gearmac-mcp-stub")
        do {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "Tests/ai-fixtures/mcp-stub.js"), to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            print("FAIL: the stub MCP server could not be installed: \(error)")
            return nil
        }
        // 定位器会遍历 PATH，因此 stub 会像真实服务器一样被找到。
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(executable.deletingLastPathComponent().path):\(inherited)", 1)
        setenv("TC_MCP_MODE", mode, 1)

        self.root = root
        server = MCPServer(
            name: "Stub", slug: "stub",
            transport: .stdio(
                command: "gearmac-mcp-stub", arguments: [], environmentKeys: []))
    }

    /// 为 stub 服务器创建一个尚未启动的连接。
    func connection() -> MCPServerConnection {
        MCPServerConnection(server: server, secrets: MCPSecretStore.Secrets())
    }

    /// 采用轮询而不是固定睡眠：成功时按需耗时，失败时也能结束。
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

    /// 删除临时安装目录，清理夹具。
    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
