// 文件职责：表情使用频次的持久化存储，维护使用次数与最近使用时间，并提供改用最多的字形列表。
// 分层：Service；状态在主 actor 上维护，数据以 JSON 写入应用支持目录。
import Foundation

/// 单个表情的使用计数，以基础（未着色）字形为键。
struct FrequentEmoji: Codable, Hashable, Sendable {
    let glyph: String
    var count: Int
    var lastUsed: Date
}

/// 有上限的表情历史与使用计数，同时持久化为网格与搜索所用。
@MainActor
@Observable
final class FrequentEmojiStore {
    private static let cap = 300

    private let fileURL: URL

    private(set) var records: [FrequentEmoji]

    /// 搜索会在多次查询间反复读取 `top()`，因此每次计数只需排序一次。
    @ObservationIgnored private var sortedMemo = Memo<Int, [String]>()
    private(set) var revision = 0

    /// 从磁盘读取已保存的计数；无文件或解析失败时以空历史开始。
    init(fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("emoji-frequency.json")) {
        self.fileURL = fileURL

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([FrequentEmoji].self, from: data)
        {
            records = Self.history(decoded)
        } else {
            records = []
        }
    }

    /// 计入一次使用：已存在则计数加一并置顶，否则新建记录，并裁剪到上限后写入磁盘。
    func record(_ glyph: String) {
        revision &+= 1
        if let index = records.firstIndex(where: { $0.glyph == glyph }) {
            var entry = records.remove(at: index)
            entry.count += 1
            entry.lastUsed = Date()
            records.insert(entry, at: 0)
        } else {
            records.insert(FrequentEmoji(glyph: glyph, count: 1, lastUsed: Date()), at: 0)
        }
        if records.count > Self.cap {
            records.removeLast(records.count - Self.cap)
        }
        persist()
    }

    /// 用备份整体替换计数，并套用与 `record` 相同的上限。
    func replace(_ imported: [FrequentEmoji]) {
        revision &+= 1
        records = Self.history(imported)
        persist()
    }

    /// 使用最多的字形（次数相同取最近使用），新习惯排在前。
    func top(_ n: Int = 16) -> [String] {
        let sorted = sortedMemo.value(for: revision) {
            records
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed }
                .map(\.glyph)
        }
        return Array(sorted.prefix(n))
    }

    /// 备份中可能重复出现同一字形；只保留其最新计数，使每个字形只占一个网格单元。
    private static func history(_ tallies: [FrequentEmoji]) -> [FrequentEmoji] {
        var seen = Set<String>()
        return Array(
            tallies
                .filter { !$0.glyph.isEmpty && $0.count > 0 }
                .sorted { $0.lastUsed > $1.lastUsed }
                .filter { seen.insert($0.glyph).inserted }
                .prefix(cap))
    }

    /// 将当前计数原子写入磁盘，失败时静默忽略。
    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
