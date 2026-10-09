// 文件职责：对 FileSearchService 做延迟基准测量，对比默认策略与带忽略模式策略在不同查询下的耗时。
// 分层：测试 harness（性能基准）；直接运行，输出首次/中位数/最大延时与结果数。

import Foundation

/// 文件搜索服务延迟基准的独立 harness（直接运行，可命令行传入查询词）。
@main
struct FileSearchPerformance {
    /// harness 入口：构造两种 FileSearchPolicy，对空查询与各查询词逐次测量。
    static func main() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let arguments = Array(CommandLine.arguments.dropFirst())
        let queries = arguments.isEmpty ? ["a", "e", "swift", "pdf", "project"] : arguments
        // 第二组策略故意偏重，以便让本次运行真实体现模式匹配的开销。
        let policies = [
            (
                "shipped",
                FileSearchPolicy(
                    scopes: FileSearchScope.defaultScopes, ignorePatterns: [],
                    homeDirectory: homeDirectory)
            ),
            (
                "+patterns",
                FileSearchPolicy(
                    scopes: FileSearchScope.defaultScopes,
                    ignorePatterns: ["*.tmp", "*.log", "**/[Cc]ache/**", "**/Logs/**", "vendor"],
                    homeDirectory: homeDirectory)
            )
        ]

        print("File search service latency; the palette adds a 120 ms debounce")
        print("Home: \(homeDirectory.path)")
        for (label, policy) in policies {
            // 空查询就是空白屏自身的列表，它的延时是用户感受最直接的一项。
            for query in [""] + queries {
                try measure(query: query, policy: policy, label: label)
            }
        }
    }

    /// 对单一查询跑 6 次：首次计时单独记录，其余 5 次取中位数与最大值。
    private static func measure(
        query: String, policy: FileSearchPolicy, label: String
    ) throws {
        var samples: [Double] = []
        var first = 0.0
        var resultCount = 0
        for run in 0..<6 {
            let start = ContinuousClock.now
            let results = try FileSearchService.search(query: query, policy: policy)
            let elapsed = milliseconds(start.duration(to: .now))
            if run == 0 {
                first = elapsed
            } else {
                samples.append(elapsed)
            }
            resultCount = results.count
        }
        let ordered = samples.sorted()
        let name = "\(label) \(query.isEmpty ? "(recents)" : query)"
            .padding(toLength: 22, withPad: " ", startingAt: 0)
        let metrics = String(
            format: "first %7.2f ms  repeat median %7.2f ms  max %7.2f ms  %3d results",
            first, ordered[ordered.count / 2], ordered.last ?? 0, resultCount)
        print("\(name) \(metrics)")
    }

    /// 把 Duration 换算为毫秒（Double）。
    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
