// 文件职责：执行文件搜索：解析搜索范围，走 Spotlight（MDQuery）查询或家目录根部分支，并把命中路径解析为结果。
// 分层：Service；无 UI，依赖 CoreServices 的 Spotlight API，所有方法均为 nonisolated。
import CoreServices
import Foundation
import UniformTypeIdentifiers

/// 基于 Spotlight 索引的文件搜索实现。
enum FileSearchService {
    /// 创建或启动 MDQuery 失败时抛出的错误。
    enum Failure: Error {
        case couldNotCreateQuery
        case couldNotStartQuery
    }

    /// 空查询对应空白屏：列出最近使用或修改过的文件，最新的在前。
    nonisolated static func search(
        query rawQuery: String, policy: FileSearchPolicy, filter: FileSearchFilter = .all
    ) throws -> [FileSearchResult] {
        try Signposts.interval("FileSearchService.search") {
            let selection = resolveScopes(policy)
            guard !rawQuery.isEmpty else {
                return try recent(scopes: selection.directories, policy: policy, filter: filter)
            }
            var results = rootResults(selection, query: rawQuery, policy: policy, filter: filter)
            guard
                !selection.directories.isEmpty,
                let expression = FileSearchQuery.expression(
                    for: rawQuery, excluding: policy.ignore.spotlightNameExclusions, filter: filter)
            else { return FileSearchQuery.rank(results, for: rawQuery, ignoring: policy.ignore) }

            var seen = Set(results.map(\.id))
            // 在 stat 之前先排除：被忽略的目录树只需一次字符串判断，而不是一次文件读取。
            for path in try spotlightPaths(expression: expression, scopes: selection.directories)
            where !FileSearchQuery.isExcludedPath(path, ignoring: policy.ignore)
                && seen.insert(path).inserted
            {
                guard let result = resolve(path, homeDirectory: policy.homeDirectory) else {
                    continue
                }
                results.append(result)
            }
            return FileSearchQuery.rank(results, for: rawQuery, ignoring: policy.ignore)
        }
    }

    /// 两个排序查询按日期合并：Spotlight 只能按单个属性排序，而两种时间戳都重要。
    private nonisolated static func recent(
        scopes: [URL], policy: FileSearchPolicy, filter: FileSearchFilter
    ) throws -> [FileSearchResult] {
        guard !scopes.isEmpty else { return [] }
        let exclusions = policy.ignore.spotlightNameExclusions
        let limit = FileSearchQuery.recentLimit
        var dated: [String: Date] = [:]
        for stamp in FileSearchQuery.RecentStamp.allCases {
            let expression = FileSearchQuery.recentExpression(
                stamp: stamp, excluding: exclusions, filter: filter)
            // 只有排序列表的头部才可能进入合并结果，因此只为这些条目读取日期。
            for (path, date) in try spotlightPaths(
                expression: expression, scopes: scopes,
                sortedBy: stamp.rawValue as CFString, dating: limit)
            where !FileSearchQuery.isExcludedPath(path, ignoring: policy.ignore) {
                dated[path] = max(dated[path] ?? .distantPast, date)
            }
        }
        return dated.sorted { $0.value > $1.value }
            .lazy
            .compactMap { resolve($0.key, homeDirectory: policy.homeDirectory) }
            .prefix(limit)
            .map { $0 }
    }

    /// 对家目录根部的候选条目做类型筛选与名称匹配，生成结果。
    private nonisolated static func rootResults(
        _ selection: FileSearchScope.Selection, query: String, policy: FileSearchPolicy,
        filter: FileSearchFilter
    ) -> [FileSearchResult] {
        selection.rootItems.compactMap { candidate in
            guard
                filter.accepts(
                    contentType: candidate.contentType, isDirectory: candidate.isDirectory),
                FileSearchQuery.matches(filename: candidate.url.lastPathComponent, query: query)
            else { return nil }
            return FileSearchResult(
                url: candidate.url, isDirectory: candidate.isDirectory,
                homeDirectory: policy.homeDirectory)
        }
    }

    /// 路径是 `MDQuery` 唯一免费返回的属性，其余属性都需要额外抓取。
    private nonisolated static func spotlightPaths(
        expression: String, scopes: [URL]
    ) throws -> [String] {
        try execute(expression: expression, scopes: scopes, sortedBy: nil) { query, count in
            (0..<count).compactMap { path(in: query, at: $0) }
        }
    }

    /// 与排序属性配合，只对前 `dating` 条结果读取日期。
    private nonisolated static func spotlightPaths(
        expression: String, scopes: [URL], sortedBy stamp: CFString, dating: Int
    ) throws -> [(path: String, date: Date)] {
        try execute(expression: expression, scopes: scopes, sortedBy: stamp) { query, count in
            (0..<min(dating, count)).compactMap { index in
                guard let path = path(in: query, at: index),
                    let raw = MDQueryGetResultAtIndex(query, index)
                else { return nil }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                guard let date = MDItemCopyAttribute(item, stamp) as? Date else { return nil }
                return (path, date)
            }
        }
    }

    /// 创建、配置并同步执行一次 MDQuery，再把结果交给 `read` 回调提取。
    private nonisolated static func execute<Value>(
        expression: String, scopes: [URL], sortedBy stamp: CFString?,
        reading read: (MDQuery, CFIndex) -> Value
    ) throws -> Value {
        // 排序属性必须在创建时指定；创建后再设置，`MDQuery` 会忽略。
        guard let query = MDQueryCreate(nil, expression as CFString, nil, stamp.map { [$0] as CFArray })
        else { throw Failure.couldNotCreateQuery }
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, FileSearchQuery.candidateLimit)
        if let stamp {
            MDQuerySetSortOptionFlagsForAttribute(
                query, stamp, kMDQueryReverseSortOrderFlag.rawValue)
        }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw Failure.couldNotStartQuery
        }
        return read(query, MDQueryGetResultCount(query))
    }

    /// 读取 MDQuery 指定序号结果的路径属性。
    private nonisolated static func path(in query: MDQuery, at index: CFIndex) -> String? {
        guard let raw = MDQueryGetResultAtIndex(query, index) else { return nil }
        let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
        return MDItemCopyAttribute(item, kMDItemPath) as? String
    }

    /// 一次 stat 就能回答过去三次元数据抓取的问题，代价只有千分之一。
    private nonisolated static func resolve(
        _ path: String, homeDirectory: URL
    ) -> FileSearchResult? {
        let url = URL(fileURLWithPath: path)
        guard
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isHiddenKey, .contentTypeKey
            ]), values.isHidden != true, values.contentType?.conforms(to: .application) != true
        else { return nil }
        return FileSearchResult(
            url: url, isDirectory: values.isDirectory == true, homeDirectory: homeDirectory)
    }

    /// 根据策略得到搜索目录列表与家目录根部展示条目。
    private nonisolated static func resolveScopes(
        _ policy: FileSearchPolicy
    )
        -> FileSearchScope.Selection
    {
        var directories = policy.directRoots
        var rootItems: [FileSearchScope.Candidate] = []
        if policy.includesHome {
            let selection = discoverScopes(homeDirectory: policy.homeDirectory)
            directories += selection.directories
            directories += cloudScopes(homeDirectory: policy.homeDirectory)
            rootItems = selection.rootItems
        }
        return FileSearchScope.Selection(
            directories: deduplicated(directories), rootItems: rootItems)
    }

    /// 列出家目录下的可见子目录，作为可搜索范围候选。
    private nonisolated static func discoverScopes(homeDirectory: URL) -> FileSearchScope.Selection {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .isPackageKey, .contentTypeKey
        ]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: homeDirectory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles])) ?? []
        let candidates = urls.compactMap { url -> FileSearchScope.Candidate? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FileSearchScope.Candidate(
                url: url,
                isDirectory: values.isDirectory == true,
                isHidden: values.isHidden == true,
                isPackage: values.isPackage == true,
                contentType: values.contentType)
        }
        return FileSearchScope.select(candidates)
    }

    /// 返回存在的云盘（iCloud Drive、第三方 CloudStorage）目录作为额外搜索范围。
    private nonisolated static func cloudScopes(homeDirectory: URL) -> [URL] {
        let candidates = [
            homeDirectory.appending(path: "Library/CloudStorage", directoryHint: .isDirectory),
            homeDirectory.appending(
                path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        ]
        return candidates.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    /// 按标准化路径去重，保留首次出现的顺序。
    private nonisolated static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
