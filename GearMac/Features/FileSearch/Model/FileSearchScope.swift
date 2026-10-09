// 文件职责：处理搜索范围字符串：~ 缩写与展开、去重规范化，以及家目录根部候选范围的筛选与拆分。
// 分层：Model；纯路径计算，不读取磁盘。
import Foundation
import UniformTypeIdentifiers

/// 搜索范围的展开、缩写、去重与家目录根部候选的挑选。
enum FileSearchScope {
    /// 以 ~ 缩写形式存储，使设置备份在不同机器之间可移植。
    static let defaultScopes = ["~"]

    /// 一个待分类的候选条目及其磁盘属性。
    struct Candidate: Sendable {
        let url: URL
        let isDirectory: Bool
        let isHidden: Bool
        let isPackage: Bool
        /// 从磁盘解析得到，使家目录根部分支的分类结果与 Spotlight 完全一致。
        let contentType: UTType?

        /// 是否为应用程序（按内容类型判断）。
        var isApplication: Bool { contentType?.conforms(to: .application) == true }
    }

    /// 从候选集中拆分出的搜索目录与家目录根部的展示条目。
    struct Selection: Sendable {
        let directories: [URL]
        let rootItems: [Candidate]
    }

    /// 过滤掉隐藏项、应用程序与 Library，并拆分为可搜索目录与根展示项。
    static func select(_ candidates: [Candidate]) -> Selection {
        var directories: [URL] = []
        var rootItems: [Candidate] = []
        for candidate in candidates
        where !candidate.isHidden && !candidate.isApplication
            && candidate.url.lastPathComponent.caseInsensitiveCompare("Library") != .orderedSame
        {
            rootItems.append(candidate)
            if candidate.isDirectory && !candidate.isPackage {
                directories.append(candidate.url)
            }
        }
        return Selection(directories: directories, rootItems: rootItems)
    }

    /// 把一条范围字符串展开为绝对 URL（~ 前缀展开为家目录）。
    static func expand(_ scope: String, homeDirectory: URL) -> URL {
        guard scope.hasPrefix("~") else {
            return URL(fileURLWithPath: scope, isDirectory: true).standardizedFileURL
        }
        let relative = String(scope.dropFirst()).trimmingPrefix("/")
        guard !relative.isEmpty else { return homeDirectory.standardizedFileURL }
        return homeDirectory.appending(path: relative, directoryHint: .isDirectory)
            .standardizedFileURL
    }

    /// 把绝对路径缩写为以 ~ 开头（位于家目录下时）。
    static func abbreviate(_ path: String, homeDirectory: URL) -> String {
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// 缩写并去重，同时保留用户添加时的顺序。
    static func normalize(_ scopes: [String], homeDirectory: URL) -> [String] {
        var seen = Set<String>()
        let abbreviated = roots(for: scopes, homeDirectory: homeDirectory)
            .map { abbreviate($0.path, homeDirectory: homeDirectory) }
        return abbreviated.filter { seen.insert($0).inserted }
    }

    /// 把范围列表展开为去重后的绝对根目录 URL 列表。
    static func roots(for scopes: [String], homeDirectory: URL) -> [URL] {
        var seen = Set<String>()
        let expanded = scopes.map { expand($0, homeDirectory: homeDirectory) }
        return expanded.filter { seen.insert($0.path).inserted }
    }
}
