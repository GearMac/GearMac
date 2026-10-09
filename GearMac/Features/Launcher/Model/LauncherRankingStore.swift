// 文件职责：以设备端 frecency 数据学习用户打开了什么、以及通过哪个查询打开，并提供排序所需的快照与持久化。
// 分层：Model（`@MainActor` 的存储类型）；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// 单个条目的使用记录：一个随时间衰减的分数，以及最近打开时使用的搜索词。
struct LauncherVisit: Codable, Hashable, Sendable {
    /// 衰减分数回落到 1 的时刻，因此更晚的锚点总是对应更高的分数。
    var anchor: Date
    var openedAt: Date
    /// 去重并折叠，最近的排在最后，最多 `LauncherRankingStore.termLimit` 个。
    var searchTerms: [String]
}

/// 单个条目在一次排序中读取的使用数据：衰减分数与仍生效的搜索词。
struct LauncherUsage: Sendable, Equatable {
    /// 从未打开、或打开时间过于久远的条目为 1。
    let frecency: Double
    /// 只有当条目在足够近期内被打开、其搜索词仍能影响查询时才非空。
    let searchTerms: [String]

    static let unused = LauncherUsage(frecency: 1, searchTerms: [])
}

/// 以受控的设备端 frecency 数据，学习用户打开了什么、以及通过哪个查询打开。
@MainActor
@Observable
final class LauncherRankingStore {
    /// 每次访问给分数加 100；分数每十天减半，且从不下低于 1。
    nonisolated static let halfLife: TimeInterval = 10 * 86_400
    nonisolated static let visitWeight = 100.0
    /// 距上次打开超过该时长后，条目的搜索词不再影响排序。
    nonisolated static let termWindow: TimeInterval = 408 * 3_600
    nonisolated static let termLimit = 3
    /// 刚超过该值时 `exp` 会使 `Double` 溢出。
    private nonisolated static let exponentCeiling = 709.78
    /// 限制粘贴输入的长度，避免一次访问把整段文字存成搜索词。
    private static let queryLimit = 64

    private let fileURL: URL
    private let now: () -> Date

    private(set) var visits: [String: LauncherVisit]
    /// `AppIndex` 缓存键的一部分，在访问或重置后使结果失效。
    private(set) var revision = 0

    /// 正在进行的持久化操作，由下一次操作等待，避免连续写入乱序落盘。
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    /// 从磁盘载入历史记录，并丢弃已过期的锚点；`fileURL` 为 nil 时使用默认路径。
    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now
        let decoded =
            (try? Data(contentsOf: self.fileURL))
            .flatMap { try? JSONDecoder().decode([String: LauncherVisit].self, from: $0) } ?? [:]
        visits = Self.live(decoded, at: now())
    }

    /// 是否还没有任何使用记录。
    var isEmpty: Bool { visits.isEmpty }

    /// 等待尚未完成的持久化。启动器本身并不需要，但回读文件时需要。
    func flush() async {
        await writeTask?.value
    }

    /// 当输入文本并非对该条目的搜索（如分类词）时，`query` 为 nil。
    func visit(itemKey: String, query: String?) {
        guard !itemKey.isEmpty else { return }
        let timestamp = now()
        let previous = visits[itemKey]
        let score = previous.map { Self.frecency(anchor: $0.anchor, at: timestamp) } ?? 1
        var terms = previous?.searchTerms ?? []
        if let term = query.map(Self.normalize), !term.isEmpty, term.count <= Self.queryLimit {
            terms.removeAll { $0 == term }
            terms.append(term)
            terms = Array(terms.suffix(Self.termLimit))
        }
        visits[itemKey] = LauncherVisit(
            anchor: Self.anchor(visitedWith: score, at: timestamp), openedAt: timestamp,
            searchTerms: terms)
        didMutate()
    }

    /// 单次排序读取的全部数据，整轮只读取一次时钟。
    func snapshot() -> Snapshot { Snapshot(visits: visits, now: now()) }

    /// 某次排序使用的不可变快照，把时间固定下来以便多条目一致比较。
    struct Snapshot: Sendable {
        let visits: [String: LauncherVisit]
        let now: Date

        func usage(for itemKey: String) -> LauncherUsage {
            LauncherRankingStore.usage(of: visits[itemKey], at: now)
        }
    }

    /// 该条目是否有任何使用记录。
    func hasRanking(for itemKey: String) -> Bool {
        visits[itemKey] != nil
    }

    /// 清除单个条目的使用记录。
    func reset(itemKey: String) {
        guard visits.removeValue(forKey: itemKey) != nil else { return }
        didMutate()
    }

    /// 清除全部使用记录。
    func resetAll() {
        guard !visits.isEmpty else { return }
        visits = [:]
        didMutate()
    }

    /// 从备份整体替换该表，并丢弃初始化器同样会丢弃的内容。
    func replace(_ imported: [String: LauncherVisit]) {
        visits = Self.live(imported, at: now())
        didMutate()
    }

    /// 查询用于匹配的形式，使存储的搜索词与排序时的比较形式一致。
    nonisolated static func normalize(_ query: String) -> String {
        SearchText(query.trimmingCharacters(in: .whitespacesAndNewlines), transliterated: true).string
    }

    /// 由锚点与当前时间计算衰减后的分数，最小为 1。
    nonisolated static func frecency(anchor: Date, at timestamp: Date) -> Double {
        let exponent = decay * anchor.timeIntervalSince(timestamp)
        return max(1, exp(min(exponent, exponentCeiling)))
    }

    /// 使分数在当前时刻恰好等于 `score + visitWeight` 的锚点。
    nonisolated static func anchor(visitedWith score: Double, at timestamp: Date) -> Date {
        timestamp.addingTimeInterval(log(score + visitWeight) / decay)
    }

    /// 把存储的访问记录转换为一次排序所需的使用数据，并判断搜索词是否仍在生效窗口内。
    nonisolated static func usage(of visit: LauncherVisit?, at timestamp: Date) -> LauncherUsage {
        guard let visit else { return .unused }
        let frecency = frecency(anchor: visit.anchor, at: timestamp)
        let recent = frecency > 1 && timestamp.timeIntervalSince(visit.openedAt) < termWindow
        return LauncherUsage(frecency: frecency, searchTerms: recent ? visit.searchTerms : [])
    }

    private nonisolated static let decay = log(2) / halfLife

    /// 已过期的锚点分数为 1 且搜索词被禁用，与从未打开过的条目完全一致。
    private nonisolated static func live(
        _ table: [String: LauncherVisit], at timestamp: Date
    ) -> [String: LauncherVisit] {
        table.filter { !$0.key.isEmpty && $0.value.anchor > timestamp }
    }

    private func didMutate() {
        revision &+= 1
        // 在主线程之外执行：该写入发生在 ↵ 按下、启动之前。通过链式等待保证写入顺序。
        let snapshot = visits
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 放在 Application Support 而非 Caches：让用户重新学习一套排序需要数周使用。
    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gearmac.app"
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launcher-ranking.json")
    }
}
