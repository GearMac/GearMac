// 文件职责：emoji 搜索性能基准，测量索引加载耗时、内存占用与各查询工作负载的延迟分位。
// 分层：测试 harness/基准脚本；输出 JSON 指标，可选 --names 报告未进入前 5 的条目。

import Foundation

/// emoji 搜索基准入口：加载索引后按预设工作负载采样延迟并打印 JSON。
@main
@MainActor
enum EmojiSearchBenchmark {
    /// 把从 start 到现在的时长换算为毫秒。
    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }

    /// 读取当前进程的常驻内存与物理内存占用。
    static func memory() -> [String: UInt64] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return ["rss_bytes": info.resident_size, "footprint_bytes": info.phys_footprint]
    }

    /// 解析 --languages，加载索引，跑 review/typing/memo 三组工作负载并输出指标。
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("emoji-search-performance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frequent = FrequentEmojiStore(fileURL: directory.appendingPathComponent("frequency.json"))
        let arguments = CommandLine.arguments
        let languages =
            arguments.firstIndex(of: "--languages")
            .flatMap { arguments.dropFirst($0 + 1).first }?
            .split(separator: ",").map(String.init) ?? []
        let index = EmojiIndex()
        let loadStart = ContinuousClock.now
        await index.load(languages: languages, bundle: Bundle(path: "GearMac/Resources") ?? .main)
        var output: [String: Any] = [
            "loaded": memory(), "load_ms": milliseconds(loadStart), "languages": languages
        ]
        // 交替查询会错过单条 memo；重复查询则衡量视图重渲染的开销。
        let workloads: [(String, [String], Int)] = [
            (
                "review",
                [
                    "pray", ":+1:", "lol", "hand waving", "waving hand", "and waving", "dwa",
                    "face joy", "tears joy", "red heart"
                ], 100
            ),
            (
                "typing",
                [
                    "p", "pr", "pra", "pray", "h", "ha", "han", "hand", "hand w", "hand wa",
                    "hand wav", "hand wavi", "hand wavin", "hand waving"
                ], 40
            ),
            ("memo", ["pray"], 10_000)
        ]
        var timings: [[String: Any]] = []
        var checksum = 0
        for (name, queries, iterations) in workloads {
            for query in queries { checksum += index.search(query, frequent: frequent).count }
            var samples: [Double] = []
            let start = ContinuousClock.now
            for _ in 0..<iterations {
                for query in queries {
                    let queryStart = ContinuousClock.now
                    checksum += index.search(query, frequent: frequent).count
                    samples.append(milliseconds(queryStart))
                }
            }
            let total = milliseconds(start)
            samples.sort()
            timings.append([
                "workload": name, "searches": samples.count,
                "mean_ms": total / Double(samples.count),
                "p50_ms": samples[samples.count / 2], "p95_ms": samples[samples.count * 95 / 100]
            ])
        }
        output["timings"] = timings
        output["after_search"] = memory()
        if CommandLine.arguments.contains("--names") {
            var missed: [String] = []
            for entry in index.entries {
                let results = index.search(entry.name, frequent: frequent)
                if !results.prefix(5).contains(where: { $0.glyph == entry.glyph }) {
                    missed.append("\(entry.glyph) \(entry.name)")
                }
            }
            output["name_count"] = index.entries.count
            output["names_missing_from_top5"] = missed
        }
        output["checksum"] = checksum
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
