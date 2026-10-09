// 文件职责：统计并清理扩展安装留下的残留目录与数据（孤儿 support/data 目录、崩溃残留的临时工作目录）。
// 分层：Service；根目录一律由调用方注入，不直接读 `Bundle.main`，避免误删真实安装。
import Foundation

/// 它同时命名工作目录，因此「创建工作目录」与「扫描工作目录」不会产生分歧。
enum ExtensionCleanup {
    /// 清理扫描涉及的三个根目录，由调用方注入。
    /// 通过注入传入，绝不从 `Bundle.main` 读取：否则测试环境会删除真实的安装内容。
    struct Roots: Sendable {
        var temp: URL
        var support: URL
        var data: URL
    }

    /// 清理结果统计：条目数与释放的字节数。
    struct Report: Sendable, Equatable {
        var items = 0
        var bytes: Int64 = 0

        var isEmpty: Bool { items == 0 }
    }

    /// 一次构建的临时工作目录。每次安装都唯一，因此两个安装可并行而不冲突。
    static func workspace(in temp: URL) -> URL {
        temp.appendingPathComponent(workspacePrefix + UUID().uuidString, isDirectory: true)
    }

    /// 真实运行环境使用的三个根目录。
    nonisolated static func defaultRoots() -> Roots {
        Roots(
            temp: FileManager.default.temporaryDirectory,
            support: ExtensionCatalog.supportRoot(),
            data: ExtensionCatalog.storageDirectory())
    }

    /// 预估 `clean` 将删除的内容，使按钮在被按下前就能给出提示。
    nonisolated static func reclaimable(installed: Set<String>, in roots: Roots) -> Report {
        var report = Report()
        for url in strays(installed: installed, in: roots) {
            report.items += 1
            report.bytes += size(of: url)
        }
        return report
    }

    /// 删除失败则跳过且不计数，因此统计值不会虚报它并未释放的空间。
    @discardableResult
    nonisolated static func clean(installed: Set<String>, in roots: Roots) -> Report {
        var report = Report()
        for url in strays(installed: installed, in: roots) {
            let bytes = size(of: url)
            guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            report.items += 1
            report.bytes += bytes
        }
        return report
    }

    /// 正常退出时由 `defer` 清理工作目录；这里收集崩溃后残留的工作目录。
    nonisolated static func sweepWorkspaces(in temp: URL) {
        for url in staleWorkspaces(in: temp) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 采用与 Finder 一致的计算方式，使这里的数字与「显示简介」中的一致。
    nonisolated static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - What counts as a stray

    private static let workspacePrefix = "gearmac-install-"

    /// 范围天然很窄：仅三个根目录，且只包含以自身前缀标明归属或无归属的条目。
    private nonisolated static func strays(installed: Set<String>, in roots: Roots) -> [URL] {
        let safe = Set(installed.map(ExtensionCatalog.safeName))
        let orphanedSupport = contents(of: roots.support).filter {
            !safe.contains($0.lastPathComponent)
        }
        let orphanedData = contents(of: roots.data).filter {
            $0.pathExtension == "json" && !safe.contains($0.deletingPathExtension().lastPathComponent)
        }
        return staleWorkspaces(in: roots.temp) + orphanedSupport + orphanedData
    }

    private nonisolated static func staleWorkspaces(in temp: URL) -> [URL] {
        contents(of: temp).filter { $0.lastPathComponent.hasPrefix(workspacePrefix) }
    }

    private nonisolated static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    /// 无法读取的条目不计入：该数字只用于副标题展示，而非精确账单。
    private nonisolated static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func bytes(_ item: URL) -> Int64 {
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return 0 }
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            return bytes(url)
        }
        guard
            let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [])
        else { return 0 }
        return walker.reduce(into: Int64(0)) { total, item in
            if let item = item as? URL { total += bytes(item) }
        }
    }
}
