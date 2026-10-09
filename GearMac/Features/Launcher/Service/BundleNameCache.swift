// 文件职责：缓存每个 bundle 在磁盘上携带的全部名称，仅在修改日期变化时重新读取。
// 分层：Service（名称解析缓存）；纯值类型、Sendable，不做主线程隔离。
import Foundation

/// bundle 在磁盘上携带的全部名称，仅当其修改日期变化时才重新读取。
struct BundleNameCache: Sendable {
    /// 缓存中单个 bundle 的一条记录：修改时间与解析出的名称列表。
    private struct Entry: Sendable {
        let modified: Date?
        /// 首选语言的名称排在最前；`scan` 取第一个作为展示名。
        let names: [String]
    }

    private let languages: [String]
    private let previous: [String: Entry]
    private var current: [String: Entry] = [:]

    init() {
        languages = []
        previous = [:]
    }

    /// 只有本次扫描询问过的条目会被延续；系统语言变化时全部丢弃。
    init(reusing cache: BundleNameCache, languages: [String]) {
        self.languages = languages
        previous = cache.languages == languages ? cache.current : [:]
    }

    /// 返回该 bundle 的名称列表：缓存命中时直接复用，否则读取磁盘并写入缓存。
    mutating func names(for url: URL, base: String, developmentRegion: String?) -> [String] {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cached = previous[url.path], cached.modified == modified {
            current[url.path] = cached
            return cached.names
        }
        let names = BundleLocalization.names(
            for: url, base: base, developmentRegion: developmentRegion, languages: languages)
        current[url.path] = Entry(modified: modified, names: names)
        return names
    }
}
