// 文件职责：把法币与加密货币两条汇率数据源解码合并为一份汇率快照。
// 分层：Model；纯解码逻辑，不做任何 IO，Data 由调用方提供（store 负责真正的网络/磁盘访问）。
import Foundation

/// 把两条汇率数据源解码合并为一份快照。纯函数，便于测试覆盖；真正的 IO 由 store 负责。
enum CurrencyFeed {
    /// 法币报价以 `<base><code>` 为键，且不含基准币自身那一行。
    private struct FiatPayload: Decodable {
        let success: Bool
        let source: String
        let quotes: [String: Double]
    }

    /// 加密货币的报价方向相反 —— 一单位该币值多少 `target`。
    private struct CryptoPayload: Decodable {
        let success: Bool
        let target: String
        let rates: [String: Double]
    }

    /// 合并两条数据源，得到「1 基准币 = N 目标币」的汇率表；当加密货币未取到时 `complete` 为 false。
    static func snapshot(
        fiat: Data, crypto: Data?, now: Date
    ) throws -> (rates: CurrencyRates, complete: Bool) {
        let payload = try JSONDecoder().decode(FiatPayload.self, from: fiat)
        let base = payload.source
        guard payload.success, base.count == 3 else { throw URLError(.cannotParseResponse) }

        var rates: [String: Double] = [:]
        rates.reserveCapacity(payload.quotes.count + 1)
        for (pair, rate) in payload.quotes where usable(rate) {
            guard pair.count == 6, pair.hasPrefix(base) else { continue }
            rates[String(pair.dropFirst(3))] = rate
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        rates[base] = 1

        var coins = 0
        // 放在最后，这样当法币表也报价同一符号时，以加密货币源的价格为准。
        if let crypto, let payload = try? JSONDecoder().decode(CryptoPayload.self, from: crypto),
            payload.success, payload.target == base
        {
            for (code, price) in payload.rates where usable(price) && usable(1 / price) {
                rates[code] = 1 / price
                coins += 1
            }
        }

        return (CurrencyRates(base: base, rates: rates, fetchedAt: now), coins > 0)
    }

    /// 只有完整快照才会被持久化，因此一个不含任何加密货币价格的缓存快照必然早于加密货币上线。
    static func pricesCoins(_ snapshot: CurrencyRates) -> Bool {
        CalcCurrency.cryptoCodes.contains { snapshot.rates[$0] != nil }
    }

    /// 判断汇率数值是否可用：必须为正且为有限值。
    private static func usable(_ rate: Double) -> Bool {
        rate > 0 && rate.isFinite
    }
}
