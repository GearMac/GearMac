// 文件职责：后台拉取并缓存汇率快照（法币与加密货币），按天刷新、失败后短间隔重试，供计算器的货币换算使用。
// 分层：Service；@MainActor 隔离，网络请求走非主线程的 ephemeral URLSession，只有快照落盘。
import Foundation

/// 无缓存的汇率拉取器，详见 docs/features/calculator.md#exchange-rates。
@MainActor
@Observable
final class CurrencyRateStore {
    private nonisolated static let fiatEndpoint = URL(
        string: "https://backend.raycast.com/api/v1/currencies")!
    /// 由应用自身的加密货币表驱动，因此请求内容与该表不会出现偏差。
    private nonisolated static let cryptoEndpoint = URL(
        string: "https://backend.raycast.com/api/v1/currencies/crypto?symbols="
            + CalcCurrency.cryptoCodes.joined(separator: ","))!
    /// 以 `completedAt` 起算的每日刷新间隔，重启应用不会重新拉取仍然新鲜的快照。
    private static let refreshInterval: TimeInterval = 24 * 3600
    /// 更短的重试间隔，使启动时离线的机器在恢复网络后很快拿到汇率。
    private static let retryInterval: TimeInterval = 30 * 60

    /// 最新的汇率快照，首次拉取成功前为 nil。
    private(set) var rates: CurrencyRates?

    private let fileURL: URL
    @ObservationIgnored private var pump: Task<Void, Never>?
    /// 驱动调度：不完整的快照也能用于展示，但只有完整快照才会重置计时。
    @ObservationIgnored private var completedAt: Date?

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")
        guard let data = try? Data(contentsOf: fileURL),
            let cached = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        else { return }
        rates = cached
        // 早于加密货币支持前的缓存仍可给法币定价，但必须马上被替换。
        if CurrencyFeed.pricesCoins(cached) { completedAt = cached.fetchedAt }
    }

    /// 启动（或重启）后台刷新循环。
    func start() {
        // 先取消再重建，而不是直接返回：已退出的循环会留下非 nil 的 task，阻塞重新启动。
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self {
                // 取值下限为 0，避免时间戳位于未来的快照把循环阻塞超过一个刷新周期。
                let age = max(0, self.completedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    /// 执行一次拉取：更新内存快照，并在结果完整时落盘，返回是否成功。
    private func fetchAndStore() async -> Bool {
        guard let result = await Self.fetch() else { return false }
        rates = result.rates
        // 绝不持久化缺少加密货币数据的结果：`pricesCoins` 按定义把缓存视为完整快照。
        guard result.complete, let data = try? JSONEncoder().encode(result.rates) else { return false }
        completedAt = result.rates.fetchedAt
        try? data.write(to: fileURL, options: .atomic)
        return true
    }

    /// 无缓存、绝不用 `URLSession.shared`，使磁盘上的快照始终是唯一副本。
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// 通过 `URLSession` 在主线程之外执行；只有纯值类型 `CurrencyRates` 会跨回主线程。
    private nonisolated static func fetch() async -> (rates: CurrencyRates, complete: Bool)? {
        async let fiat = body(of: fiatEndpoint)
        async let crypto = body(of: cryptoEndpoint)
        let (fiatData, cryptoData) = await (fiat, crypto)
        guard let fiatData else { return nil }
        return try? CurrencyFeed.snapshot(fiat: fiatData, crypto: cryptoData, now: Date())
    }

    /// 请求单个端点，仅在返回 200 时给出响应体。
    private nonisolated static func body(of url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
