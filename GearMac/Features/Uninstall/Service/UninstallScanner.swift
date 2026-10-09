// 文件职责：卸载扫描的文件系统实现——发现候选、测量目录体积、探测完整磁盘访问权限。
// 分层：Service（Uninstall）；承担全部 stat、权限与目录遍历副作用，判定逻辑委托给 Model 层的纯规则。
import Darwin
import Foundation

/// 所有文件系统、stat 与权限读取都在这里；它委托出去的判定属于纯函数那一半。
enum UninstallScanner {
    /// 目录遍历的条目预算，防止超大目录拖垮扫描。
    struct SizeBudget: Sendable {
        /// 取值宽松：某编辑器的支持目录可达约 9 万个条目。25 万条约 1 秒，且在非主线程执行。
        var maxEntries = 250_000
        static let `default` = SizeBudget()
    }

    /// 扫描阶段的失败类型。
    enum Failure: LocalizedError, Sendable {
        case refused

        var errorDescription: String? {
            switch self {
            case .refused:
                return L10n.string(UninstallKey.scanRefused, language: .system)
            }
        }
    }

    /// 返回所有候选，目录体积暂为 nil；速度足够快到列表可以直接基于它渲染。
    nonisolated static func discover(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String],
        isTargetRunning: Bool, roots: [UninstallSearchRoot] = UninstallSearchRoot.all
    ) async throws -> UninstallPlan {
        try await Signposts.interval("UninstallScanner.discover") {
            let home = NSHomeDirectory()
            let environment = UninstallEnvironment(
                home: home, hasFullDiskAccess: detectFullDiskAccess(home: home))
            guard
                let identity = UninstallIdentity.make(
                    target: target, otherAppNames: otherAppNames, otherBundleIDs: otherBundleIDs,
                    ownBundleID: Bundle.main.bundleIdentifier, ownBundleURL: Bundle.main.bundleURL)
            else { throw Failure.refused }

            let bundlePath = target.bundleURL.standardizedFileURL.path
            let bundle = row(
                path: bundlePath, evidence: .bundle, environment: environment,
                displayName: target.bundleURL.deletingPathExtension().lastPathComponent)

            var buckets = [[UninstallCandidate]](repeating: [], count: roots.count)
            try await withThrowingTaskGroup(of: (Int, [UninstallCandidate]).self) { group in
                for (index, root) in roots.enumerated() {
                    group.addTask {
                        try Task.checkCancellation()
                        return (
                            index,
                            rows(
                                in: root, identity: identity, environment: environment,
                                bundlePath: bundlePath)
                        )
                    }
                }
                // 按各自的索引写入，使 `UninstallSearchRoot.all` 的顺序不受完成先后影响。
                for try await (index, found) in group { buckets[index] = found }
            }

            let gathered =
                [bundle].compactMap { $0 } + buckets.flatMap { $0 }
                + (try binRows(environment: environment, bundlePath: bundlePath))

            // 按收集顺序单趟去重：跨任务共享 `Set` 才会产生竞态。
            var seen = Set<String>()
            let candidates = gathered.filter { seen.insert($0.path).inserted }

            // 应用包固定在最前，其余按路径排序，即列表展示顺序。
            let leftovers = candidates.filter { $0.evidence != .bundle }.sorted { $0.path < $1.path }
            return UninstallPlan(
                target: target, candidates: candidates.filter { $0.evidence == .bundle } + leftovers,
                isTargetRunning: isTargetRunning)
        }
    }

    /// 每完成一次遍历就立即回传，使某一行不必等待相邻行；nil 表示未能测量。
    nonisolated static func measure(
        paths: [String], budget: SizeBudget = .default,
        onMeasured: @escaping @Sendable @MainActor (String, MeasuredSize) -> Void
    ) async {
        await Signposts.interval("UninstallScanner.measure") {
            await withTaskGroup(of: (String, MeasuredSize)?.self) { group in
                for path in paths {
                    group.addTask {
                        guard let size = try? directorySize(of: path, budget: budget) else {
                            return nil
                        }
                        return (path, size)
                    }
                }
                // 被取消或不可读的遍历不产出结果，对应行保持待测量状态。
                for await measured in group {
                    guard let (path, size) = measured else { continue }
                    await onMeasured(path, size)
                }
            }
        }
    }

    // MARK: - Private

    private static func rows(
        in root: UninstallSearchRoot, identity: UninstallIdentity,
        environment: UninstallEnvironment, bundlePath: String
    ) -> [UninstallCandidate] {
        let rootPath = root.path(home: environment.home)
        guard let names = childNames(of: rootPath) else { return [] }
        // 每个搜索根只 stat 一次，而不是每行一次。
        let parent = parentFacts(of: rootPath)
        return UninstallRules.matches(childNames: names, in: root, identity: identity)
            .compactMap { match -> UninstallCandidate? in
                let path = (rootPath + "/" + match.name as NSString).standardizingPath
                guard
                    UninstallRules.isAcceptableCandidate(
                        path: path, rootPath: rootPath, home: environment.home,
                        bundlePath: bundlePath)
                else { return nil }
                return row(
                    path: path, evidence: match.evidence, environment: environment, parent: parent)
            }
    }

    /// 串行执行：只读四个目录的符号链接，开销很小，且无需遍历。
    private static func binRows(
        environment: UninstallEnvironment, bundlePath: String
    ) throws
        -> [UninstallCandidate]
    {
        var rows: [UninstallCandidate] = []
        for directory in UninstallSearchRoot.binDirectories {
            try Task.checkCancellation()
            let rootPath = (directory as NSString).expandingTildeInPath
            guard let names = childNames(of: rootPath) else { continue }
            let parent = parentFacts(of: rootPath)
            for name in names {
                let path = (rootPath + "/" + name as NSString).standardizingPath
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
                else { continue }
                // 相对符号链接相对于它所在目录解析，而不是当前工作目录。
                let resolved =
                    target.hasPrefix("/")
                    ? target : (rootPath as NSString).appendingPathComponent(target)
                guard UninstallRules.isBundleSymlink(target: resolved, bundlePath: bundlePath),
                    let row = row(
                        path: path, evidence: .binSymlink, environment: environment, parent: parent)
                else { continue }
                rows.append(row)
            }
        }
        return rows
    }

    /// 列出目录下的直接子项名称；不可读时返回 nil。
    private static func childNames(of directory: String) -> [String]? {
        // 不使用 `.skipsHiddenFiles`：以点开头的残留正是用户永远找不到的那些。
        try? FileManager.default.contentsOfDirectory(atPath: directory)
    }

    /// 组装单个候选条目；无法检视（如路径已消失）时返回 nil。
    private static func row(
        path: String, evidence: UninstallEvidence, environment: UninstallEnvironment,
        displayName: String? = nil, parent: ParentFacts? = nil
    ) -> UninstallCandidate? {
        guard let scanned = inspect(path, parent: parent) else { return nil }
        let protection = UninstallProtectionRules.classify(scanned.facts, environment: environment)
        guard protection != .missing else { return nil }
        // 符号链接按其链接本身移入废纸篓，因此体积不会超过链接自身。
        let walkable = scanned.isDirectory && !scanned.facts.isSymbolicLink
        return UninstallCandidate(
            path: path,
            name: displayName ?? (path as NSString).lastPathComponent,
            locationLabel: UninstallRules.abbreviate(
                (path as NSString).deletingLastPathComponent, home: environment.home),
            evidence: evidence,
            isDirectory: scanned.isDirectory,
            size: walkable ? nil : MeasuredSize(bytes: scanned.byteSize),
            protection: protection)
    }

    /// 只用 `lstat` 而非 `stat`：符号链接按链接本身判定，而不是它指向的对象。
    private static func inspect(
        _ path: String, parent: ParentFacts?
    )
        -> (facts: PathFacts, isDirectory: Bool, byteSize: Int64)?
    {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let parent = parent ?? parentFacts(of: (path as NSString).deletingLastPathComponent)
        let volumeIsReadOnly =
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey]))?
            .volumeIsReadOnly ?? false
        let facts = PathFacts(
            path: path,
            isSymbolicLink: (info.st_mode & S_IFMT) == S_IFLNK,
            volumeIsReadOnly: volumeIsReadOnly,
            isSystemRestricted: info.st_flags & UInt32(SF_RESTRICTED | SF_IMMUTABLE) != 0,
            isUserImmutable: info.st_flags & UInt32(UF_IMMUTABLE) != 0,
            isOwnedByCurrentUser: info.st_uid == geteuid(),
            parentIsWritable: parent.isWritable,
            parentIsSticky: parent.isSticky)
        // 用 `st_size` 而非 `st_blocks`：593 字节的 plist 也占一个块，不能读成 4 kB。
        return (facts, (info.st_mode & S_IFMT) == S_IFDIR, Int64(info.st_size))
    }

    /// 真正决定能否移入废纸篓的权限，每个搜索根只解析一次。
    private static func parentFacts(of directory: String) -> ParentFacts {
        var info = stat()
        let sticky = stat(directory, &info) == 0 && (info.st_mode & S_ISVTX) != 0
        return ParentFacts(
            isWritable: FileManager.default.isWritableFile(atPath: directory), isSticky: sticky)
    }

    /// 父目录的写权限与粘滞位。
    private struct ParentFacts {
        let isWritable: Bool
        let isSticky: Bool
    }

    /// 逻辑字节数，与 Finder 一致；不可读的子树跳过，而不是整体放弃。
    private static func directorySize(of path: String, budget: SizeBudget) throws -> MeasuredSize {
        let url = URL(fileURLWithPath: path)
        // 不用分配大小相关的 key：Xcode 采用 decmpfs 压缩分发，按块计算会把 9.45 GB 读成 4.19 GB。
        let keys: [URLResourceKey] = [.totalFileSizeKey, .fileSizeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in true })
        else { return .zero }

        // 提到循环外：循环最多执行 `maxEntries` 次，放在循环内每次都会分配一个 `Set`。
        let keySet = Set(keys)
        var size = MeasuredSize()
        var entries = 0
        for case let item as URL in enumerator {
            // 最耗时的一环：取消必须能在遍历内部生效，而不只是在两次遍历之间。
            try Task.checkCancellation()
            entries += 1
            if entries > budget.maxEntries {
                size.isLowerBound = true
                break
            }
            let values = try? item.resourceValues(forKeys: keySet)
            size.bytes += Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
        }
        return size
    }

    /// 只做探测而不申请权限：TCC 会静默拒绝，宁可少报也只是让某行显示为锁定。
    private static func detectFullDiskAccess(home: String) -> Bool {
        let descriptor = open(home + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
