// 文件职责：驱动每日的发布检查轮询，缓存最新版本、上次检查时间与被跳过的版本。
// 分层：Service/状态（@MainActor @Observable）；网络请求可注入，便于测试。
import Foundation

/// 每日发布检查。详见 docs/features/updates.md。
@MainActor
@Observable
final class UpdateCheckStore {
    private nonisolated static let endpoint = URL(
        string: "https://api.github.com/repos/\(ReleaseFeed.repository)/releases?per_page=20")!
    /// 以 `lastCheckedAt` 为起点按天计算，因此重新启动不会重复请求 GitHub。
    private static let refreshInterval: TimeInterval = 24 * 3600
    /// 更短的重试间隔，使启动时离线的机器在恢复联网后很快就能看到新版本。
    private static let retryInterval: TimeInterval = 2 * 3600
    /// 被暂缓的提示按此间隔重新提供，最多这么多次，之后交给下一次每日检查。
    private static let withheldInterval: TimeInterval = 120
    private static let withheldRetryLimit = 15
    /// 让首次检查（及它可能弹出的窗口）避开登录后最拥挤的时段。
    private static let startupDelay = Duration.seconds(30)

    let channel: ReleaseChannel
    let runningVersion: AppVersion?

    /// 该通道上的最新发布，无论是否新于当前运行版本。
    private(set) var latest: AvailableRelease?
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking = false

    /// 在出现未被跳过的发布时调用；返回 `false` 表示提示被暂缓、仍需重试。
    @ObservationIgnored var onUpdateAvailable: (@MainActor (AvailableRelease) -> Bool)?

    private let fileURL: URL
    @ObservationIgnored private let fetch: @Sendable () async -> Data?
    private var skippedVersion: AppVersion?
    /// 每次启动中，每个版本最多主动出现一次。
    @ObservationIgnored private var announcedVersion: AppVersion?
    @ObservationIgnored private var withheldRetries = 0
    @ObservationIgnored private var pump: Task<Void, Never>?

    /// 注入通道、运行版本、缓存路径与网络请求实现，并载入磁盘上的缓存。
    init(
        channel: ReleaseChannel = ReleaseChannel(bundleID: Bundle.main.bundleIdentifier),
        runningVersion: AppVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init),
        fileURL: URL = AppPaths.caches().appendingPathComponent("update-check.json"),
        fetch: @escaping @Sendable () async -> Data? = UpdateCheckStore.body
    ) {
        self.channel = channel
        self.runningVersion = runningVersion
        self.fileURL = fileURL
        self.fetch = fetch
        guard let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        latest = cache.latest
        lastCheckedAt = cache.lastCheckedAt
        skippedVersion = cache.skippedVersion
    }

    deinit { pump?.cancel() }

    /// 新于当前运行版本。窗口提供的版本，包含已被跳过的那个。
    var update: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion, skipped: nil)
    }

    /// 同上，但排除已被跳过的版本。只有它才会打断用户。
    var unskippedUpdate: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion, skipped: skippedVersion)
    }

    /// 启动轮询任务；非自更新通道或运行版本未知时不启动。
    func start(after delay: Duration = UpdateCheckStore.startupDelay) {
        guard channel.updatesItself, runningVersion != nil else { return }
        // 直接替换而不提前返回：已退出的循环仍会留下非 nil 的任务，从而阻塞重启。
        stop()
        pump = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                // 使用可选链：sleep 不得持有 store，否则它将无法被释放。
                guard let wait = await self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// 停止轮询并复位暂缓重试计数。
    func stop() {
        pump?.cancel()
        pump = nil
        withheldRetries = 0
    }

    /// 手动检查路径：忽略新鲜度，并返回 GitHub 是否真的作出了应答。
    @discardableResult
    func check() async -> Bool {
        guard channel.updatesItself, !isChecking else { return false }
        isChecking = true
        defer { isChecking = false }
        guard let data = await fetch(), !Task.isCancelled else { return false }
        latest = ReleaseFeed.newest(from: data, channel: channel, architecture: .current)
        lastCheckedAt = Date()
        persist()
        return true
    }

    /// 跳过一个版本即可让它不再询问；更高的版本仍会再次提示。
    func skip(_ release: AvailableRelease) {
        skippedVersion = release.version
        persist()
    }

    /// 轮询的一轮：到期则检查、有待提供则提示，并返回下次等待时长。
    private func advance() async -> TimeInterval {
        // 做下限截断，避免时间戳在未来的检查把循环阻塞超过一个间隔。
        let age = max(0, lastCheckedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
        var wait = Self.refreshInterval - age
        if wait <= 0 {
            wait = await check() ? Self.refreshInterval : Self.retryInterval
        }
        if announce() {
            withheldRetries = 0
        } else if withheldRetries < Self.withheldRetryLimit {
            // 启动后直接进入面板的场景，不应消耗掉当天唯一一次提示机会。
            withheldRetries += 1
            wait = min(wait, Self.withheldInterval)
        }
        return wait
    }

    /// 仅在有待提供版本被暂缓时返回 `false`，以便轮询稍后再来。
    private func announce() -> Bool {
        guard !Task.isCancelled else { return true }
        guard let release = unskippedUpdate, announcedVersion != release.version else { return true }
        guard onUpdateAvailable?(release) ?? true else { return false }
        announcedVersion = release.version
        return true
    }

    /// 把检查状态原子地写入缓存文件。
    private func persist() {
        let cache = Cache(
            lastCheckedAt: lastCheckedAt, latest: latest, skippedVersion: skippedVersion)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 持久化到磁盘的检查状态。
    private struct Cache: Codable {
        var lastCheckedAt: Date?
        var latest: AvailableRelease?
        var skippedVersion: AppVersion?
    }

    /// 不使用缓存，且绝不使用 `URLSession.shared`，使磁盘上的快照是唯一副本。
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// 拉取 GitHub Releases 响应体；非 200 响应或请求失败时返回 nil。
    private nonisolated static func body() async -> Data? {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        // GitHub 会直接拒绝不带 User-Agent 的 API 请求。
        request.setValue("GearMac", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
