// 文件职责：定义应用搜索范围（默认文件夹、路径缩写/展开/规范化）与在各范围内枚举 `.app` bundle 的逻辑。
// 分层：Model；不得 import AppKit/SwiftUI，仅依赖 Foundation。
import Foundation

/// `AppIndex` 扫描应用时使用的文件夹与 bundle。
enum SearchScopes {
    /// 全新安装时的初始值；顺序有意义，扫描会按 bundle ID 去重。
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        // 由 Cryptex 分发的系统应用；`/Applications` 中的 Safari 是隐藏的符号链接。
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        // CoreServices 中唯一面向用户的应用，因此该目录本身不作为默认扫描范围。
        "/System/Library/CoreServices/Finder.app",
        "~/Applications"
    ]

    /// 使用波浪号缩写并去掉尾部斜杠，使设置备份可跨机器移植。
    static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    /// 把波浪号缩写展开为绝对路径，并去掉尾部斜杠。
    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    /// 缩写每条路径并去重，同时保持原顺序。
    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// bundle 自带应用的存放位置：Xcode 把 Instruments 与 Simulator 放在这里。
    private static let embeddedAppFolders = [
        "Contents/Applications", "Contents/Developer/Applications"
    ]

    /// 所有扫描范围指向的 `.app`。只深入一层子目录；更深嵌套需单独配置范围。
    static func appBundles(in scopes: [String]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(contentsOf: withEmbedded(url)) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// 对 `.app` 只会进入其内嵌应用文件夹，不再继续深入。
    private static func appBundles(under url: URL, subfolderDepth: Int) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        for item in newestFirst(items) {
            if item.pathExtension == "app" {
                result.append(contentsOf: withEmbedded(item))
            } else if subfolderDepth > 0,
                (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            {
                result.append(contentsOf: appBundles(under: item, subfolderDepth: subfolderDepth - 1))
            }
        }
        return result
    }

    /// 扫描保留同一 bundle ID 的第一个副本，因此文件夹内会优先列出最新版本。
    private static func newestFirst(_ items: [URL]) -> [URL] {
        items
            .map { (url: $0, version: shortVersion(of: $0)) }
            .sorted { lhs, rhs in
                let byVersion = lhs.version.compare(rhs.version, options: .numeric)
                if byVersion != .orderedSame { return byVersion == .orderedDescending }
                // 版本相同时回退到 Finder 的顺序，避免由文件系统决定胜出者。
                return displayName(of: lhs.url).localizedStandardCompare(displayName(of: rhs.url))
                    == .orderedAscending
            }
            .map(\.url)
    }

    /// 无法读取时为空字符串，`.numeric` 会让它排在任何真实版本之后。
    private static func shortVersion(of url: URL) -> String {
        guard url.pathExtension == "app" else { return "" }
        return Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// 去掉 `.app`，使 `Xcode` 排在 `Xcode-beta` 之前而非之后。
    private static func displayName(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 把一个 bundle 与其内嵌应用文件夹中的 `.app` 合并为列表。
    private static func withEmbedded(_ app: URL) -> [URL] {
        [app]
            + embeddedAppFolders.flatMap {
                appBundles(under: app.appendingPathComponent($0), subfolderDepth: 0)
            }
    }

    /// 去掉首尾空白与多余的尾部斜杠；根路径 "/" 保留。
    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
