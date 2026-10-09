// 文件职责：测试 FileSearchSession 的异步调度语义：防抖合并、串行化、取消、策略变更丢弃旧结果等。
// 分层：测试 harness；通过 FileSearchProbe 伪服务观察真实调用顺序与并发度。

import Foundation

/// 伪文件搜索服务：记录每次调用、并发峰值，并可在指定查询上暂停以观察会话调度行为。
actor FileSearchProbe {
    private var active = 0
    private var calls: [String] = []
    private var maximumActive = 0
    private let pausedQuery: String?
    private var pauseEnabled: Bool
    private var pausedContinuation: CheckedContinuation<Void, Never>?

    init(pausing query: String? = nil) {
        pausedQuery = query
        pauseEnabled = query != nil
    }

    /// 记录调用并返回单一合成结果；若 query 等于 pausedQuery 则挂起等待外部恢复。
    func search(
        query: String, filter: FileSearchFilter, policy: FileSearchPolicy
    ) async -> [FileSearchResult] {
        active += 1
        calls.append(filter == .all ? query : "\(query) [\(filter.localizedTitle(.english))]")
        maximumActive = max(maximumActive, active)
        if pauseEnabled, query == pausedQuery {
            await withCheckedContinuation { continuation in
                pausedContinuation = continuation
            }
        } else {
            try? await Task.sleep(for: .milliseconds(80))
        }
        active -= 1
        return [
            FileSearchResult(
                url: policy.homeDirectory.appending(path: query), isDirectory: false,
                homeDirectory: policy.homeDirectory)
        ]
    }

    /// 返回截至当前的调用记录与曾达到的最大并发数。
    func snapshot() -> (calls: [String], maximumActive: Int) {
        (calls, maximumActive)
    }

    /// 轮询等待搜索挂起到暂停点，超时（1 秒）则返回 false 并关闭暂停。
    func waitUntilPaused() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while pausedContinuation == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard pausedContinuation != nil else {
            pauseEnabled = false
            return false
        }
        return true
    }

    /// 恢复被暂停的搜索，并永久关闭暂停开关。
    func resumePausedSearch() {
        pauseEnabled = false
        pausedContinuation?.resume()
        pausedContinuation = nil
    }
}

/// FileSearchSession 调度行为的独立测试 harness（直接运行，不依赖 XCTest）。
@main
@MainActor
struct FileSearchSessionTests {
    nonisolated(unsafe) static var failures = 0
    static let home = URL(fileURLWithPath: "/Users/test")

    /// 断言辅助：条件不成立时累加失败计数并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// harness 入口：依次运行全部异步用例，打印结果并以退出码反映成败。
    static func main() async {
        await coalescesDebouncingQueries()
        await serializesRunningQueries()
        await cancellationPreventsPendingWork()
        await policyChangeDiscardsStaleResults()
        await unchangedPolicyKeepsResults()
        await blankQueryLoadsRecents()
        await filterChangeRerunsTheQuery()

        print(failures == 0 ? "File search session tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// 验证防抖窗口内只有最新的查询会被真正执行并发布结果。
    static func coalescesDebouncingQueries() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(30))
        session.search("annual")
        session.search("annual report")
        await waitUntil { session.state == .ready }

        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["annual report"], "the debounce runs only the newest query")
        expect(session.results.first?.name == "annual report", "the newest query publishes")
    }

    /// 验证后续查询会接管前一个查询，但底层 Spotlight 调用绝不重叠。
    static func serializesRunningQueries() async {
        let probe = FileSearchProbe(pausing: "first")
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("first")
        let firstStarted = await probe.waitUntilPaused()
        expect(firstStarted, "the first query starts")
        guard firstStarted else { return }
        session.search("second")
        await probe.resumePausedSearch()
        await waitUntil { session.state == .ready && session.results.first?.name == "second" }

        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["first", "second"], "the superseding query still runs")
        expect(snapshot.maximumActive == 1, "Spotlight operations never overlap")
    }

    /// 验证在防抖期间取消会阻止搜索发出，并清空会话状态。
    static func cancellationPreventsPendingWork() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(30))
        session.search("cancelled")
        session.cancel()
        try? await Task.sleep(for: .milliseconds(60))

        let snapshot = await probe.snapshot()
        expect(snapshot.calls.isEmpty, "cancelling during the debounce prevents the search")
        expect(session.state == .idle && session.results.isEmpty, "cancellation clears the session")
    }

    /// 验证策略变更后，旧规则下找到的结果永不被发布，相同查询会在新规则下重跑。
    static func policyChangeDiscardsStaleResults() async {
        let probe = FileSearchProbe(pausing: "report")
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("report")
        let oldSearchStarted = await probe.waitUntilPaused()
        expect(oldSearchStarted, "the old-policy query starts")
        guard oldSearchStarted else { return }
        session.apply(scopes: FileSearchScope.defaultScopes, ignorePatterns: ["*.log"])

        expect(
            session.state == .idle && session.results.isEmpty,
            "a result found under the old rules never publishes")
        session.search("report")
        await probe.resumePausedSearch()
        await waitUntil { session.state == .ready && session.results.first?.name == "report" }
        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["report", "report"], "the same query re-runs under the new rules")
    }

    /// 验证重复应用完全相同的设置不会影响已发布的结果。
    static func unchangedPolicyKeepsResults() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("report")
        await waitUntil { session.state == .ready }
        session.apply(scopes: FileSearchScope.defaultScopes, ignorePatterns: [])

        expect(
            session.state == .ready && session.results.first?.name == "report",
            "re-applying identical settings leaves the published results alone")
    }

    /// 验证空查询自身就是一次真实请求（用于空白屏的最近项），而非无请求。
    static func blankQueryLoadsRecents() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("")
        await waitUntil { session.state == .ready }
        session.search("report")
        await waitUntil { session.state == .ready && session.results.first?.name == "report" }

        let snapshot = await probe.snapshot()
        expect(
            snapshot.calls == ["", "report"],
            "the blank screen is a request of its own, not the absence of one")
    }

    /// 验证收窄过滤器会重跑同一查询词，而重复提交相同过滤器不产生新请求。
    static func filterChangeRerunsTheQuery() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("report")
        await waitUntil { session.state == .ready }
        session.search("report", filter: .images)
        await waitUntil { session.state == .ready }
        session.search("report", filter: .images)
        try? await Task.sleep(for: .milliseconds(40))

        let snapshot = await probe.snapshot()
        expect(
            snapshot.calls == ["report", "report [Images]"],
            "narrowing the filter re-runs the same words, and re-stating it runs nothing")
    }

    /// 构造一个使用默认策略、并转发给给定 probe 的会话。
    static func makeSession(probe: FileSearchProbe, debounce: Duration) -> FileSearchSession {
        let policy = FileSearchPolicy(
            scopes: FileSearchScope.defaultScopes, ignorePatterns: [], homeDirectory: home)
        return FileSearchSession(policy: policy, debounce: debounce) { query, filter, policy in
            await probe.search(query: query, filter: filter, policy: policy)
        }
    }

    /// 轮询等待条件成立，超时（1 秒）则记为一次失败。
    static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        expect(condition(), "the async operation completed before the timeout")
    }
}
