// 文件职责：驱动本地 HTTP fixture 服务器，验证 ExtensionFetcher 的共享传输复用、请求取消隔离与连接释放行为。
// 分层：测试 harness；依赖 Tests/ext-fixtures/http-server.js 子进程，通过状态文件同步，请求走真实网络回环。

import Foundation

/// 扩展网络抓取（ExtensionFetcher）的集成测试：用本地 HTTP fixture 观察连接生命周期。
@MainActor
enum ExtensionFetchTests {
    /// fixture 服务器写入状态文件的结构，用于观察连接的开启/关闭/挂起计数。
    private struct ServerState: Decodable {
        let port: Int
        let opened: Int
        let closed: Int
        let holding: Int
        let slow: Int
    }

    /// 委托 ExtensionTests.check 记录断言结果。
    private static func expect(_ condition: Bool, _ message: String) {
        ExtensionTests.check(message, condition)
    }

    /// 读取并解码 fixture 状态文件，失败时返回 nil。
    private static func readState(_ file: URL) -> ServerState? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ServerState.self, from: data)
    }

    /// 轮询状态文件（最多约 3 秒），命中给定条件即返回 true。
    private static func waitForState(_ file: URL, matching predicate: (ServerState) -> Bool) async -> Bool {
        for _ in 0..<150 {
            if let state = readState(file), predicate(state) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// 发起一次扩展抓取请求，并把 base64 响应体解码为 UTF-8 文本（失败时返回空串）。
    private static func request(
        _ fetcher: ExtensionFetcher, url: String, token: String = ""
    ) async throws -> String {
        let result = try await fetcher.request(
            .object([
                "url": .string(url), "headers": .object(["Authorization": .string(token)])
            ]))
        guard let encoded = result["bodyBase64"] as? String, let data = Data(base64Encoded: encoded),
            let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    /// 用一次性 fetcher 请求给定 URL，用于观察临时 fetcher 的连接释放。
    private static func transientRequest(_ url: String) async throws {
        let fetcher = ExtensionFetcher()
        _ = try await request(fetcher, url: url)
    }

    /// 校验共享传输：取消一个请求不影响另一个，且复用传输不携带旧凭据或 Cookie。
    private static func sharedRequests(_ url: String, stateFile: URL) async throws {
        let fetcher = ExtensionFetcher()
        let cancelled = Task { try await request(fetcher, url: url + "/hold", token: "fixture-a") }
        let started = await waitForState(stateFile) { $0.holding == 1 }
        expect(started, "request reaches the server before cancellation")
        let survivor = Task { try await request(fetcher, url: url + "/slow", token: "fixture-b") }
        let concurrent = await waitForState(stateFile) { $0.slow == 1 }
        expect(concurrent, "requests overlap on the shared transport")
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            expect(false, "cancelled fetch returns cancellation")
        } catch {
            expect(
                (error as? URLError)?.code == .cancelled || error is CancellationError,
                "cancelled fetch returns cancellation")
        }
        let text = try await survivor.value
        expect(
            text.contains("fixture-b") && !text.contains("fixture-a"),
            "cancelling one request preserves another request and its headers")
        let next = try await request(fetcher, url: url + "/echo")
        expect(
            next == #"{"authorization":"","cookie":""}"#,
            "reused transport carries neither previous authorization nor response cookies")
    }

    /// 启动 node fixture 服务器并依次运行抓取检查，结束时清理进程与临时目录。
    static func runChecks() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "gearmac-fetch-\(UUID())")
        let stateFile = directory.appendingPathComponent("state.json")
        let server = Process()
        defer {
            if server.isRunning { server.terminate(); server.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("ext-fixtures/http-server.js")
            server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            server.arguments = ["node", fixture.path, stateFile.path]
            server.standardOutput = FileHandle.nullDevice
            try server.run()
            let ready = await waitForState(stateFile) { $0.port != 0 }
            guard ready, let state = readState(stateFile) else {
                expect(false, "HTTP fixture starts")
                return
            }
            let url = "http://127.0.0.1:\(state.port)"
            for _ in 0..<20 { try await transientRequest(url) }
            let released = await waitForState(stateFile) { $0.opened >= 20 && $0.closed == $0.opened }
            expect(released, "discarding transient fetchers closes all HTTP connections")
            try await sharedRequests(url, stateFile: stateFile)
            let sharedReleased = await waitForState(stateFile) { $0.closed == $0.opened }
            expect(sharedReleased, "shared transport closes its connections when its owner releases it")
        } catch {
            expect(false, "HTTP fixture: \(error)")
        }
    }
}
