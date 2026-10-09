// 文件职责：封装 OSSignposter，提供同步/异步两种区间计时，用于性能观测。
// 分层：Service；仅依赖 os，无外部状态；未附加 Instruments 时运行开销极低。
import os

/// 粗粒度的常驻区间；除非附加了 Instruments 会话，运行时开销极低。
enum Signposts {
    private static let signposter = OSSignposter(
        subsystem: "com.gearmac.perf", category: "Performance")

    /// 自行掌管 `defer`：被包裹的工作抛错时 `withIntervalSignpost` 会跳过其结束事件。
    static func interval<T>(_ name: StaticString, around work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    /// 异步版本的区间计时，语义与同步版一致。
    static func interval<T>(
        _ name: StaticString, around work: () async throws -> T
    ) async rethrows
        -> T
    {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}
