// 文件职责：对 TextDiffEngine.diff 做基准计时与精确性校验，并将结果以 JSON 打印到标准输出。
// 分层：测试 harness / 性能脚本；由命令行参数（token 数、工作负载、迭代次数）驱动。

import Foundation

/// 文本差异算法的基准与探针脚本（直接运行，不依赖 XCTest）。
@main
enum TextDiffPerformance {
    /// 入口：按参数指定的工作负载重复求 diff 并输出计时 JSON；传入 --probe 时改为导出差分结果。
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--probe"] {
            try probe()
            return
        }
        guard let argument = arguments.first,
            let count = Int(argument), (1...4_001).contains(count)
        else { fatalError("Pass a token count from 1 through 4001, or --probe") }
        let workload = arguments.count > 1 ? arguments[1] : "dense"
        let iterations = arguments.count > 2 ? Int(arguments[2]) ?? 0 : 1
        precondition(iterations > 0)

        let original = workload == "empty" ? "" : input(word: "old", tokens: count)
        let modified: String
        switch workload {
        case "dense", "empty": modified = input(word: "new", tokens: count)
        case "sparse": modified = "new" + original.dropFirst(3)
        case "equal": modified = original
        default: fatalError("Workload must be dense, sparse, equal or empty")
        }
        _ = TextDiffEngine.diff(original: "warm up", modified: "warm down")

        var chunks: [TextDiffEngine.Chunk] = []
        var checksum = 0
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            chunks = TextDiffEngine.diff(original: original, modified: modified)
            checksum += chunks.count
        }
        let duration = start.duration(to: .now).components
        let milliseconds =
            (Double(duration.seconds) * 1_000
                + Double(duration.attoseconds) / 1e15) / Double(iterations)

        let expected: [TextDiffEngine.Chunk]
        if workload == "equal" {
            expected = [.equal(original)]
        } else if workload == "empty" {
            expected = [.inserted(modified)]
        } else if count > TextDiffEngine.maxTokens {
            expected = [.deleted(original), .inserted(modified)]
        } else if workload == "sparse" {
            let suffix = String(original.dropFirst(3))
            expected =
                [.deleted("old"), .inserted("new")]
                + (suffix.isEmpty ? [] : [.equal(suffix)])
        } else {
            expected = (0..<count).flatMap { index in
                index.isMultiple(of: 2)
                    ? [.deleted("old"), .inserted("new")] : [.equal(" ")]
            }
        }
        precondition(chunks == expected, "Complete chunks must match the synthetic oracle")
        precondition(checksum == expected.count * iterations)
        let result: [String: Any] = [
            "tokens_per_side": count,
            "workload": workload,
            "iterations": iterations,
            "diff_milliseconds": milliseconds,
            "chunks": chunks.count,
            "exact_output_passed": true
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { fatalError("JSON must be UTF-8") }
        print(json)
    }

    /// 生成交替排列的合成输入：偶数位置放 word，奇数位置放空格。
    static func input(word: String, tokens: Int) -> String {
        (0..<tokens).map { $0.isMultiple(of: 2) ? word : " " }.joined()
    }

    /// 对固定样例与伪随机组合求 diff，导出完整块序列用于跨实现比对。
    static func probe() throws {
        var pairs = [
            ("", ""), ("", "new"), ("old", ""), ("same", "same"),
            ("a b", "b a"), ("one one two", "one two one"),
            ("café", "cafe\u{301}"), (" 👩🏽‍💻\n中文", "\t中文 👩🏽‍💻")
        ]
        let fragments = [
            "", "a", "b", "a", " ", "  ", "\n", "\t", ".!?", "—",
            "café", "e\u{301}", "👩🏽‍💻", "中文", "مرحبا", "123"
        ]
        var seed: UInt64 = 0x54494E5943415354
        func next(_ limit: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 32) % limit
        }
        for _ in 0..<2_000 {
            let original = (0..<next(20)).map { _ in fragments[next(fragments.count)] }.joined()
            let modified = (0..<next(20)).map { _ in fragments[next(fragments.count)] }.joined()
            pairs.append((original, modified))
        }
        let results = pairs.map { original, modified in
            TextDiffEngine.diff(original: original, modified: modified).map { chunk in
                switch chunk {
                case .equal(let text): ["equal", text]
                case .deleted(let text): ["deleted", text]
                case .inserted(let text): ["inserted", text]
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { fatalError("JSON must be UTF-8") }
        print(json)
    }
}
