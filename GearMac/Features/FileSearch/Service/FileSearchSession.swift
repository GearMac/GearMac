// 文件职责：管理「搜索文件」查询的生命周期：请求去重、防抖、后台搜索任务调度与结果/状态发布。
// 分层：Service->Session；@MainActor @Observable，只把搜索操作转发给注入的 SearchOperation。
import Foundation

/// 「搜索文件」面板的搜索会话与状态发布。
@MainActor
@Observable
final class FileSearchSession {
    /// 实际执行搜索的异步操作，便于测试时注入替身。
    typealias SearchOperation =
        @Sendable (String, FileSearchFilter, FileSearchPolicy) async throws -> [FileSearchResult]

    /// 会话的发布状态。
    enum State: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    private(set) var results: [FileSearchResult] = []
    private(set) var state: State = .idle
    /// 已发布的搜索：筛选器属于它的一部分，因此改变筛选会用相同的关键词重新搜索。
    private var request: Request?
    private var revision = 0
    @ObservationIgnored private var pendingSearch: PendingSearch?
    @ObservationIgnored private var workerTask: Task<Void, Never>?
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private var policy: FileSearchPolicy
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let searchOperation: SearchOperation

    /// 一次已发布的搜索请求（查询词 + 筛选器）。
    private struct Request: Equatable {
        let query: String
        let filter: FileSearchFilter
    }

    /// 一次等待防抖后执行的搜索，携带可用于作废它的修订号。
    private struct PendingSearch {
        let request: Request
        let revision: Int
        let earliestStart: ContinuousClock.Instant
    }

    /// 默认初始化：使用家目录、默认范围并发执行 FileSearchService。
    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.homeDirectory = homeDirectory
        policy = FileSearchPolicy(
            scopes: FileSearchScope.defaultScopes, ignorePatterns: [],
            homeDirectory: homeDirectory)
        debounce = .milliseconds(120)
        searchOperation = { query, filter, policy in
            try await Task.detached(priority: .userInitiated) {
                try FileSearchService.search(query: query, policy: policy, filter: filter)
            }.value
        }
    }

    /// 可注入策略、防抖与搜索操作的初始化器，供测试与自定义配置使用。
    init(
        policy: FileSearchPolicy, debounce: Duration,
        searchOperation: @escaping SearchOperation
    ) {
        homeDirectory = policy.homeDirectory
        self.policy = policy
        self.debounce = debounce
        self.searchOperation = searchOperation
    }

    /// 在这里解析策略而非每次搜索时解析，避免 glob 编译出现在按键路径上。
    func apply(scopes: [String], ignorePatterns: [String]) {
        let policy = FileSearchPolicy(
            scopes: scopes, ignorePatterns: ignorePatterns, homeDirectory: homeDirectory)
        guard policy != self.policy else { return }
        self.policy = policy
        // 用旧规则找到的结果不能发布，且相同的查询需要重新执行。
        cancel()
    }

    /// 空查询同样是一次请求：空白屏列出最近使用过的文件。
    func search(_ rawQuery: String, filter: FileSearchFilter = .all) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(query: query, filter: filter)
        guard request != self.request || state == .failed else { return }
        revision &+= 1
        self.request = request
        state = .searching
        // 空白屏不做防抖：不存在下一次按键需要合并。
        pendingSearch = PendingSearch(
            request: request, revision: revision,
            earliestStart: ContinuousClock.now.advanced(by: query.isEmpty ? .zero : debounce))
        guard workerTask == nil else { return }
        workerTask = Task { [weak self] in
            guard let self else { return }
            await runWorker()
        }
    }

    /// 取消当前搜索并清空结果与状态。
    func cancel() {
        revision &+= 1
        pendingSearch = nil
        request = nil
        results = []
        state = .idle
    }

    /// 被移到废纸篓的行指向的文件已不存在，因此也要从已发布的结果中移除。
    func remove(_ result: FileSearchResult) {
        results.removeAll { $0.id == result.id }
    }

    /// 取出并执行待处理搜索，按修订号作废过期的结果。
    private func runWorker() async {
        while let pending = pendingSearch {
            let delay = ContinuousClock.now.duration(to: pending.earliestStart)
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard pendingSearch?.revision == pending.revision else { continue }
            pendingSearch = nil
            let request = pending.request
            do {
                let candidates = try await searchOperation(request.query, request.filter, policy)
                guard revision == pending.revision, self.request == request else { continue }
                results = candidates
                state = .ready
            } catch {
                guard revision == pending.revision, self.request == request else { continue }
                results = []
                state = .failed
            }
        }
        workerTask = nil
    }
}
